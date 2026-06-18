from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    col,
    lit,
    current_timestamp,
    sha2,
    concat_ws,
    coalesce,
    when
)

SILVER_BASE_PATH = "hdfs://hdfs-namenode:9000/charity_data_lake/silver"
GOLD_BASE_PATH = "hdfs://hdfs-namenode:9000/charity_data_lake/gold"

spark = (
    SparkSession.builder
    .appName("DE10_Silver_To_Gold_Curated_Analytics")
    .getOrCreate()
)

spark.sparkContext.setLogLevel("WARN")


def read_silver(table_name):
    return spark.read.parquet(f"{SILVER_BASE_PATH}/{table_name}")


def pick(df, candidates, alias_name, dtype=None, default_value=None):
    for candidate in candidates:
        if candidate in df.columns:
            expression = col(candidate)
            if dtype:
                expression = expression.cast(dtype)
            return expression.alias(alias_name)

    expression = lit(default_value)
    if dtype:
        expression = expression.cast(dtype)
    return expression.alias(alias_name)


def add_hash_key(df, key_name, key_columns):
    expressions = [coalesce(col(c).cast("string"), lit("")) for c in key_columns]
    return df.withColumn(key_name, sha2(concat_ws("||", *expressions), 256))


def write_gold(df, output_path, dedupe_columns=None):
    if dedupe_columns:
        df = df.dropDuplicates(dedupe_columns)

    (
        df.coalesce(1)
        .write
        .mode("overwrite")
        .parquet(output_path)
    )

    print(f"Written Gold dataset: {output_path}")


# ----------------------------
# DIM ORGANIZATION
# ----------------------------
source_tables = [
    "beneficiaries",
    "applications",
    "cases",
    "donations",
    "donors",
    "inventory_items",
    "inventory_transactions",
    "beneficiary_documents",
    "source_event_outbox"
]

org_df = spark.createDataFrame([], "source_org string, source_database string")

for table_name in source_tables:
    temp_df = read_silver(table_name).select("source_org", "source_database").distinct()
    org_df = org_df.unionByName(temp_df, allowMissingColumns=True)

dim_organization = (
    org_df
    .dropDuplicates(["source_org"])
    .withColumn(
        "organization_name",
        when(col("source_org") == "food_bank", lit("Food Bank"))
        .when(col("source_org") == "resala", lit("Resala"))
        .when(col("source_org") == "haya_karima", lit("Haya Karima"))
        .otherwise(col("source_org"))
    )
    .withColumn("gold_processed_at", current_timestamp())
)

dim_organization = add_hash_key(dim_organization, "organization_sk", ["source_org"])

dim_organization = dim_organization.select(
    "organization_sk",
    "source_org",
    "source_database",
    "organization_name",
    "gold_processed_at"
)

write_gold(
    dim_organization,
    f"{GOLD_BASE_PATH}/dimensions/dim_organization",
    ["organization_sk"]
)


# ----------------------------
# DIM BENEFICIARY
# ----------------------------
beneficiaries = read_silver("beneficiaries")

dim_beneficiary = beneficiaries.select(
    col("source_org"),
    col("source_database"),
    pick(beneficiaries, ["beneficiary_id", "id", "beneficiary_uuid"], "beneficiary_nk", "string"),
    col("kafka_offset").cast("string").alias("_fallback_offset"),
    pick(beneficiaries, ["full_name", "beneficiary_name", "name", "name_ar"], "beneficiary_name", "string"),
    pick(beneficiaries, ["gender"], "gender", "string"),
    pick(beneficiaries, ["birth_date", "date_of_birth"], "birth_date", "string"),
    pick(beneficiaries, ["governorate"], "governorate", "string"),
    pick(beneficiaries, ["city", "district"], "city", "string"),
    pick(beneficiaries, ["marital_status"], "marital_status", "string"),
    pick(beneficiaries, ["employment_status"], "employment_status", "string"),
    pick(beneficiaries, ["monthly_income", "income"], "monthly_income", "double"),
    pick(beneficiaries, ["family_members", "family_size"], "family_members", "int"),
    pick(beneficiaries, ["has_disability"], "has_disability", "string"),
    pick(beneficiaries, ["has_chronic_disease", "has_disease"], "has_chronic_disease", "string"),
    pick(beneficiaries, ["created_at"], "created_at_raw", "string")
)

dim_beneficiary = (
    dim_beneficiary
    .withColumn("beneficiary_nk", coalesce(col("beneficiary_nk"), col("_fallback_offset")))
    .drop("_fallback_offset")
    .withColumn("gold_processed_at", current_timestamp())
)

dim_beneficiary = add_hash_key(dim_beneficiary, "organization_sk", ["source_org"])
dim_beneficiary = add_hash_key(dim_beneficiary, "beneficiary_sk", ["source_org", "beneficiary_nk"])

dim_beneficiary = dim_beneficiary.select(
    "beneficiary_sk",
    "organization_sk",
    "source_org",
    "source_database",
    "beneficiary_nk",
    "beneficiary_name",
    "gender",
    "birth_date",
    "governorate",
    "city",
    "marital_status",
    "employment_status",
    "monthly_income",
    "family_members",
    "has_disability",
    "has_chronic_disease",
    "created_at_raw",
    "gold_processed_at"
)

write_gold(
    dim_beneficiary,
    f"{GOLD_BASE_PATH}/dimensions/dim_beneficiary",
    ["beneficiary_sk"]
)


# ----------------------------
# DIM DONOR
# ----------------------------
donors = read_silver("donors")

dim_donor = donors.select(
    col("source_org"),
    col("source_database"),
    pick(donors, ["donor_id", "id", "donor_uuid"], "donor_nk", "string"),
    col("kafka_offset").cast("string").alias("_fallback_offset"),
    pick(donors, ["full_name", "donor_name", "name"], "donor_name", "string"),
    pick(donors, ["donor_type", "type"], "donor_type", "string"),
    pick(donors, ["governorate"], "governorate", "string"),
    pick(donors, ["city"], "city", "string"),
    pick(donors, ["created_at"], "created_at_raw", "string")
)

dim_donor = (
    dim_donor
    .withColumn("donor_nk", coalesce(col("donor_nk"), col("_fallback_offset")))
    .drop("_fallback_offset")
    .withColumn("gold_processed_at", current_timestamp())
)

dim_donor = add_hash_key(dim_donor, "organization_sk", ["source_org"])
dim_donor = add_hash_key(dim_donor, "donor_sk", ["source_org", "donor_nk"])

dim_donor = dim_donor.select(
    "donor_sk",
    "organization_sk",
    "source_org",
    "source_database",
    "donor_nk",
    "donor_name",
    "donor_type",
    "governorate",
    "city",
    "created_at_raw",
    "gold_processed_at"
)

write_gold(
    dim_donor,
    f"{GOLD_BASE_PATH}/dimensions/dim_donor",
    ["donor_sk"]
)


# ----------------------------
# FACT APPLICATIONS
# ----------------------------
applications = read_silver("applications")

fact_applications = applications.select(
    col("source_org"),
    col("source_database"),
    pick(applications, ["application_id", "id"], "application_nk", "string"),
    pick(applications, ["beneficiary_id"], "beneficiary_nk", "string"),
    col("kafka_offset").cast("string").alias("_fallback_offset"),
    pick(applications, ["branch_id"], "branch_nk", "string"),
    pick(applications, ["status", "application_status"], "application_status", "string"),
    pick(applications, ["support_type", "support_category"], "support_type", "string"),
    pick(applications, ["priority_score"], "priority_score", "double"),
    pick(applications, ["created_at", "submitted_at", "application_date"], "application_date_raw", "string"),
    col("kafka_timestamp")
)

fact_applications = (
    fact_applications
    .withColumn("application_nk", coalesce(col("application_nk"), col("_fallback_offset")))
    .drop("_fallback_offset")
    .withColumn("gold_processed_at", current_timestamp())
)

fact_applications = add_hash_key(fact_applications, "organization_sk", ["source_org"])
fact_applications = add_hash_key(fact_applications, "beneficiary_sk", ["source_org", "beneficiary_nk"])
fact_applications = add_hash_key(fact_applications, "application_sk", ["source_org", "application_nk"])

write_gold(
    fact_applications,
    f"{GOLD_BASE_PATH}/facts/fact_applications",
    ["application_sk"]
)


# ----------------------------
# FACT CASES
# ----------------------------
cases = read_silver("cases")

fact_cases = cases.select(
    col("source_org"),
    col("source_database"),
    pick(cases, ["case_id", "id"], "case_nk", "string"),
    pick(cases, ["beneficiary_id"], "beneficiary_nk", "string"),
    col("kafka_offset").cast("string").alias("_fallback_offset"),
    pick(cases, ["status", "case_status"], "case_status", "string"),
    pick(cases, ["case_category", "support_type"], "case_category", "string"),
    pick(cases, ["target_amount", "required_amount"], "target_amount", "double"),
    pick(cases, ["collected_amount", "funded_amount"], "collected_amount", "double"),
    pick(cases, ["priority_score"], "priority_score", "double"),
    pick(cases, ["created_at", "case_date"], "case_date_raw", "string"),
    col("kafka_timestamp")
)

fact_cases = (
    fact_cases
    .withColumn("case_nk", coalesce(col("case_nk"), col("_fallback_offset")))
    .drop("_fallback_offset")
    .withColumn("gold_processed_at", current_timestamp())
)

fact_cases = add_hash_key(fact_cases, "organization_sk", ["source_org"])
fact_cases = add_hash_key(fact_cases, "beneficiary_sk", ["source_org", "beneficiary_nk"])
fact_cases = add_hash_key(fact_cases, "case_sk", ["source_org", "case_nk"])

write_gold(
    fact_cases,
    f"{GOLD_BASE_PATH}/facts/fact_cases",
    ["case_sk"]
)


# ----------------------------
# FACT DONATIONS
# ----------------------------
donations = read_silver("donations")

fact_donations = donations.select(
    col("source_org"),
    col("source_database"),
    pick(donations, ["donation_id", "id"], "donation_nk", "string"),
    pick(donations, ["donor_id"], "donor_nk", "string"),
    pick(donations, ["case_id"], "case_nk", "string"),
    col("kafka_offset").cast("string").alias("_fallback_offset"),
    pick(donations, ["amount", "donation_amount"], "donation_amount", "double"),
    pick(donations, ["payment_method"], "payment_method", "string"),
    pick(donations, ["payment_status", "status"], "payment_status", "string"),
    pick(donations, ["created_at", "donation_date"], "donation_date_raw", "string"),
    col("kafka_timestamp")
)

fact_donations = (
    fact_donations
    .withColumn("donation_nk", coalesce(col("donation_nk"), col("_fallback_offset")))
    .drop("_fallback_offset")
    .withColumn("gold_processed_at", current_timestamp())
)

fact_donations = add_hash_key(fact_donations, "organization_sk", ["source_org"])
fact_donations = add_hash_key(fact_donations, "donor_sk", ["source_org", "donor_nk"])
fact_donations = add_hash_key(fact_donations, "case_sk", ["source_org", "case_nk"])
fact_donations = add_hash_key(fact_donations, "donation_sk", ["source_org", "donation_nk"])

write_gold(
    fact_donations,
    f"{GOLD_BASE_PATH}/facts/fact_donations",
    ["donation_sk"]
)


# ----------------------------
# FACT INVENTORY TRANSACTIONS
# ----------------------------
inventory_transactions = read_silver("inventory_transactions")

fact_inventory_transactions = inventory_transactions.select(
    col("source_org"),
    col("source_database"),
    pick(inventory_transactions, ["transaction_id", "inventory_transaction_id", "id"], "transaction_nk", "string"),
    pick(inventory_transactions, ["item_id"], "item_nk", "string"),
    pick(inventory_transactions, ["beneficiary_id"], "beneficiary_nk", "string"),
    col("kafka_offset").cast("string").alias("_fallback_offset"),
    pick(inventory_transactions, ["transaction_type", "movement_type"], "transaction_type", "string"),
    pick(inventory_transactions, ["quantity"], "quantity", "double"),
    pick(inventory_transactions, ["created_at", "transaction_date"], "transaction_date_raw", "string"),
    col("kafka_timestamp")
)

fact_inventory_transactions = (
    fact_inventory_transactions
    .withColumn("transaction_nk", coalesce(col("transaction_nk"), col("_fallback_offset")))
    .drop("_fallback_offset")
    .withColumn("gold_processed_at", current_timestamp())
)

fact_inventory_transactions = add_hash_key(fact_inventory_transactions, "organization_sk", ["source_org"])
fact_inventory_transactions = add_hash_key(fact_inventory_transactions, "beneficiary_sk", ["source_org", "beneficiary_nk"])
fact_inventory_transactions = add_hash_key(fact_inventory_transactions, "inventory_transaction_sk", ["source_org", "transaction_nk"])

write_gold(
    fact_inventory_transactions,
    f"{GOLD_BASE_PATH}/facts/fact_inventory_transactions",
    ["inventory_transaction_sk"]
)

print("DE-10 completed: Silver data curated and written to Gold analytics layer.")
