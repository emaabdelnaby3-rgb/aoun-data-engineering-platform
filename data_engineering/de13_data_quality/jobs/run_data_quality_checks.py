from pyspark.sql import SparkSession
from pyspark.sql.functions import col, trim
from datetime import datetime, timezone
import os
import csv
import traceback

SILVER_BASE = "hdfs://hdfs-namenode:9000/charity_data_lake/silver"
GOLD_BASE = "hdfs://hdfs-namenode:9000/charity_data_lake/gold"

DQ_RESULTS_HDFS_CSV = "hdfs://hdfs-namenode:9000/charity_data_lake/silver/data_quality_issues/de13_run_results_csv"
DQ_RESULTS_HDFS_PARQUET = "hdfs://hdfs-namenode:9000/charity_data_lake/silver/data_quality_issues/de13_run_results_parquet"
FAILED_RECORDS_BASE = "hdfs://hdfs-namenode:9000/charity_data_lake/silver/data_quality_issues/failed_records"

LOCAL_RESULTS_DIR = "/opt/spark/data_engineering/de13_data_quality/results"
LOCAL_RESULTS_FILE = f"{LOCAL_RESULTS_DIR}/de13_latest_results.csv"

SQLSERVER_JDBC_URL = (
    "jdbc:sqlserver://sqlserver:1433;"
    "databaseName=charity_dwh;"
    "encrypt=false;"
    "trustServerCertificate=true"
)

SQLSERVER_USER = "sa"
SQLSERVER_PASSWORD = "ChangeMe_StrongPassword_2026!"
SQLSERVER_DRIVER = "com.microsoft.sqlserver.jdbc.SQLServerDriver"

ALLOWED_ORGS = ["food_bank", "resala", "haya_karima"]

spark = (
    SparkSession.builder
    .appName("DE13_Data_Quality_Great_Expectations_Style")
    .getOrCreate()
)

spark.sparkContext.setLogLevel("WARN")

results = []


def now_utc():
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


def add_result(
    check_id,
    layer,
    dataset,
    expectation_type,
    column_name,
    rule_description,
    severity,
    status,
    total_rows,
    failed_rows,
    details
):
    total_rows = int(total_rows) if total_rows is not None else 0
    failed_rows = int(failed_rows) if failed_rows is not None else 0

    if total_rows == 0:
        success_percentage = 0.0 if status != "PASS" else 100.0
    else:
        success_percentage = round(((total_rows - failed_rows) / total_rows) * 100, 2)

    results.append({
        "check_id": check_id,
        "layer": layer,
        "dataset": dataset,
        "expectation_type": expectation_type,
        "column_name": column_name if column_name else "",
        "rule_description": rule_description,
        "severity": severity,
        "status": status,
        "total_rows": total_rows,
        "failed_rows": failed_rows,
        "success_percentage": success_percentage,
        "details": details,
        "checked_at": now_utc()
    })


def safe_count(df):
    try:
        return df.count()
    except Exception:
        return 0


def write_failed_records(df, layer, dataset, check_id):
    try:
        output_path = f"{FAILED_RECORDS_BASE}/{layer}/{dataset}/{check_id}"
        (
            df.limit(1000)
            .write
            .mode("overwrite")
            .json(output_path)
        )
    except Exception as ex:
        print(f"Could not write failed records for {check_id}: {ex}")


def read_parquet_dataset(layer, dataset, path):
    try:
        df = spark.read.parquet(path)
        return df, None
    except Exception as ex:
        add_result(
            check_id=f"{layer}_{dataset}_readable",
            layer=layer,
            dataset=dataset,
            expectation_type="expect_dataset_to_be_readable",
            column_name="",
            rule_description=f"{dataset} must be readable from {path}",
            severity="CRITICAL",
            status="FAIL",
            total_rows=0,
            failed_rows=1,
            details=str(ex)[:500]
        )
        return None, ex


def read_dwh_table(table_name):
    try:
        df = (
            spark.read
            .format("jdbc")
            .option("url", SQLSERVER_JDBC_URL)
            .option("dbtable", table_name)
            .option("user", SQLSERVER_USER)
            .option("password", SQLSERVER_PASSWORD)
            .option("driver", SQLSERVER_DRIVER)
            .load()
        )
        return df, None
    except Exception as ex:
        add_result(
            check_id=f"dwh_{table_name.replace('.', '_')}_readable",
            layer="dwh",
            dataset=table_name,
            expectation_type="expect_table_to_be_readable",
            column_name="",
            rule_description=f"{table_name} must be readable from SQL Server DWH",
            severity="CRITICAL",
            status="FAIL",
            total_rows=0,
            failed_rows=1,
            details=str(ex)[:500]
        )
        return None, ex


def expect_not_empty(df, layer, dataset):
    total = safe_count(df)
    status = "PASS" if total > 0 else "FAIL"

    add_result(
        check_id=f"{layer}_{dataset}_not_empty",
        layer=layer,
        dataset=dataset,
        expectation_type="expect_table_row_count_to_be_greater_than",
        column_name="",
        rule_description=f"{dataset} must contain at least one row",
        severity="CRITICAL",
        status=status,
        total_rows=total,
        failed_rows=0 if total > 0 else 1,
        details=f"Row count = {total}"
    )

    return total


def expect_required_columns(df, layer, dataset, required_columns):
    total = safe_count(df)
    missing = [c for c in required_columns if c not in df.columns]
    status = "PASS" if not missing else "FAIL"

    add_result(
        check_id=f"{layer}_{dataset}_required_columns",
        layer=layer,
        dataset=dataset,
        expectation_type="expect_table_columns_to_exist",
        column_name=", ".join(required_columns),
        rule_description=f"{dataset} must contain required columns: {required_columns}",
        severity="CRITICAL",
        status=status,
        total_rows=total,
        failed_rows=len(missing),
        details=f"Missing columns: {missing}" if missing else "All required columns exist"
    )


def expect_column_not_null(df, layer, dataset, column_name, severity="CRITICAL"):
    total = safe_count(df)

    if column_name not in df.columns:
        status = "FAIL" if severity == "CRITICAL" else "WARN"
        add_result(
            check_id=f"{layer}_{dataset}_{column_name}_not_null",
            layer=layer,
            dataset=dataset,
            expectation_type="expect_column_values_to_not_be_null",
            column_name=column_name,
            rule_description=f"{column_name} must not be null",
            severity=severity,
            status=status,
            total_rows=total,
            failed_rows=total,
            details=f"Column {column_name} does not exist"
        )
        return

    failed_df = df.filter(
        col(column_name).isNull() |
        (trim(col(column_name).cast("string")) == "")
    )

    failed = failed_df.count()
    status = "PASS" if failed == 0 else ("FAIL if severity == CRITICAL else WARN")
    if failed > 0:
        status = "FAIL" if severity == "CRITICAL" else "WARN"

    add_result(
        check_id=f"{layer}_{dataset}_{column_name}_not_null",
        layer=layer,
        dataset=dataset,
        expectation_type="expect_column_values_to_not_be_null",
        column_name=column_name,
        rule_description=f"{column_name} must not be null or empty",
        severity=severity,
        status=status,
        total_rows=total,
        failed_rows=failed,
        details=f"Failed null/empty rows = {failed}"
    )

    if failed > 0:
        write_failed_records(failed_df, layer, dataset, f"{column_name}_not_null")


def expect_column_values_in_set(df, layer, dataset, column_name, allowed_values, severity="CRITICAL"):
    total = safe_count(df)

    if column_name not in df.columns:
        status = "FAIL" if severity == "CRITICAL" else "WARN"
        add_result(
            check_id=f"{layer}_{dataset}_{column_name}_in_set",
            layer=layer,
            dataset=dataset,
            expectation_type="expect_column_values_to_be_in_set",
            column_name=column_name,
            rule_description=f"{column_name} must be one of {allowed_values}",
            severity=severity,
            status=status,
            total_rows=total,
            failed_rows=total,
            details=f"Column {column_name} does not exist"
        )
        return

    failed_df = df.filter(~col(column_name).isin(allowed_values))
    failed = failed_df.count()
    status = "PASS" if failed == 0 else ("FAIL" if severity == "CRITICAL" else "WARN")

    add_result(
        check_id=f"{layer}_{dataset}_{column_name}_in_set",
        layer=layer,
        dataset=dataset,
        expectation_type="expect_column_values_to_be_in_set",
        column_name=column_name,
        rule_description=f"{column_name} must be one of {allowed_values}",
        severity=severity,
        status=status,
        total_rows=total,
        failed_rows=failed,
        details=f"Invalid values count = {failed}"
    )

    if failed > 0:
        write_failed_records(failed_df, layer, dataset, f"{column_name}_in_set")


def expect_no_duplicate_keys(df, layer, dataset, key_columns, severity="CRITICAL"):
    total = safe_count(df)

    missing = [c for c in key_columns if c not in df.columns]
    if missing:
        status = "FAIL" if severity == "CRITICAL" else "WARN"
        add_result(
            check_id=f"{layer}_{dataset}_no_duplicate_keys",
            layer=layer,
            dataset=dataset,
            expectation_type="expect_compound_columns_to_be_unique",
            column_name=", ".join(key_columns),
            rule_description=f"{dataset} key columns must be unique: {key_columns}",
            severity=severity,
            status=status,
            total_rows=total,
            failed_rows=len(missing),
            details=f"Missing key columns: {missing}"
        )
        return

    distinct_count = df.select(*key_columns).dropDuplicates().count()
    duplicate_count = total - distinct_count
    status = "PASS" if duplicate_count == 0 else ("FAIL" if severity == "CRITICAL" else "WARN")

    add_result(
        check_id=f"{layer}_{dataset}_no_duplicate_keys",
        layer=layer,
        dataset=dataset,
        expectation_type="expect_compound_columns_to_be_unique",
        column_name=", ".join(key_columns),
        rule_description=f"{dataset} key columns must be unique: {key_columns}",
        severity=severity,
        status=status,
        total_rows=total,
        failed_rows=duplicate_count,
        details=f"Duplicate key count = {duplicate_count}"
    )


def expect_numeric_min(df, layer, dataset, column_name, min_value, severity="CRITICAL"):
    total = safe_count(df)

    if column_name not in df.columns:
        add_result(
            check_id=f"{layer}_{dataset}_{column_name}_min",
            layer=layer,
            dataset=dataset,
            expectation_type="expect_column_values_to_be_greater_than_or_equal_to",
            column_name=column_name,
            rule_description=f"{column_name} should be >= {min_value}",
            severity=severity,
            status="SKIP",
            total_rows=total,
            failed_rows=0,
            details=f"Column {column_name} does not exist, rule skipped"
        )
        return

    failed_df = df.filter(col(column_name).cast("double") < min_value)
    failed = failed_df.count()
    status = "PASS" if failed == 0 else ("FAIL" if severity == "CRITICAL" else "WARN")

    add_result(
        check_id=f"{layer}_{dataset}_{column_name}_min",
        layer=layer,
        dataset=dataset,
        expectation_type="expect_column_values_to_be_greater_than_or_equal_to",
        column_name=column_name,
        rule_description=f"{column_name} should be >= {min_value}",
        severity=severity,
        status=status,
        total_rows=total,
        failed_rows=failed,
        details=f"Rows below minimum = {failed}"
    )

    if failed > 0:
        write_failed_records(failed_df, layer, dataset, f"{column_name}_min")


def expect_numeric_between(df, layer, dataset, column_name, min_value, max_value, severity="WARNING"):
    total = safe_count(df)

    if column_name not in df.columns:
        add_result(
            check_id=f"{layer}_{dataset}_{column_name}_between",
            layer=layer,
            dataset=dataset,
            expectation_type="expect_column_values_to_be_between",
            column_name=column_name,
            rule_description=f"{column_name} should be between {min_value} and {max_value}",
            severity=severity,
            status="SKIP",
            total_rows=total,
            failed_rows=0,
            details=f"Column {column_name} does not exist, rule skipped"
        )
        return

    numeric_col = col(column_name).cast("double")
    failed_df = df.filter(numeric_col.isNotNull() & ((numeric_col < min_value) | (numeric_col > max_value)))
    failed = failed_df.count()
    status = "PASS" if failed == 0 else ("FAIL" if severity == "CRITICAL" else "WARN")

    add_result(
        check_id=f"{layer}_{dataset}_{column_name}_between",
        layer=layer,
        dataset=dataset,
        expectation_type="expect_column_values_to_be_between",
        column_name=column_name,
        rule_description=f"{column_name} should be between {min_value} and {max_value}",
        severity=severity,
        status=status,
        total_rows=total,
        failed_rows=failed,
        details=f"Rows outside range = {failed}"
    )

    if failed > 0:
        write_failed_records(failed_df, layer, dataset, f"{column_name}_between")


# -----------------------------
# SILVER LAYER CHECKS
# -----------------------------
silver_tables = [
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

for table in silver_tables:
    path = f"{SILVER_BASE}/{table}"
    df, error = read_parquet_dataset("silver", table, path)
    if df is None:
        continue

    expect_not_empty(df, "silver", table)
    expect_required_columns(df, "silver", table, ["source_org", "source_table"])
    expect_column_not_null(df, "silver", table, "source_org")
    expect_column_not_null(df, "silver", table, "source_table")
    expect_column_values_in_set(df, "silver", table, "source_org", ALLOWED_ORGS)

# -----------------------------
# GOLD LAYER CHECKS
# -----------------------------
gold_datasets = {
    "dim_organization": {
        "path": f"{GOLD_BASE}/dimensions/dim_organization",
        "key": "organization_sk",
        "numeric_min": [],
        "between": []
    },
    "dim_beneficiary": {
        "path": f"{GOLD_BASE}/dimensions/dim_beneficiary",
        "key": "beneficiary_sk",
        "numeric_min": ["monthly_income", "family_members"],
        "between": []
    },
    "dim_donor": {
        "path": f"{GOLD_BASE}/dimensions/dim_donor",
        "key": "donor_sk",
        "numeric_min": [],
        "between": []
    },
    "fact_applications": {
        "path": f"{GOLD_BASE}/facts/fact_applications",
        "key": "application_sk",
        "numeric_min": [],
        "between": ["priority_score"]
    },
    "fact_cases": {
        "path": f"{GOLD_BASE}/facts/fact_cases",
        "key": "case_sk",
        "numeric_min": ["target_amount", "collected_amount"],
        "between": ["priority_score"]
    },
    "fact_donations": {
        "path": f"{GOLD_BASE}/facts/fact_donations",
        "key": "donation_sk",
        "numeric_min": ["donation_amount"],
        "between": []
    },
    "fact_inventory_transactions": {
        "path": f"{GOLD_BASE}/facts/fact_inventory_transactions",
        "key": "inventory_transaction_sk",
        "numeric_min": ["quantity"],
        "between": []
    }
}

for dataset, config in gold_datasets.items():
    df, error = read_parquet_dataset("gold", dataset, config["path"])
    if df is None:
        continue

    expect_not_empty(df, "gold", dataset)
    expect_required_columns(df, "gold", dataset, [config["key"], "organization_sk"])
    expect_column_not_null(df, "gold", dataset, config["key"])
    expect_column_not_null(df, "gold", dataset, "organization_sk")
    expect_no_duplicate_keys(df, "gold", dataset, [config["key"]])

    for numeric_column in config["numeric_min"]:
        expect_numeric_min(df, "gold", dataset, numeric_column, 0, severity="WARNING")

    for between_column in config["between"]:
        expect_numeric_between(df, "gold", dataset, between_column, 0, 100, severity="WARNING")

# -----------------------------
# SQL SERVER DWH CHECKS
# -----------------------------
dwh_tables = {
    "gold.dim_organization": "organization_sk",
    "gold.dim_beneficiary": "beneficiary_sk",
    "gold.dim_donor": "donor_sk",
    "gold.fact_applications": "application_sk",
    "gold.fact_cases": "case_sk",
    "gold.fact_donations": "donation_sk",
    "gold.fact_inventory_transactions": "inventory_transaction_sk"
}

for table_name, key_column in dwh_tables.items():
    df, error = read_dwh_table(table_name)
    if df is None:
        continue

    safe_dataset_name = table_name.replace(".", "_")
    expect_not_empty(df, "dwh", safe_dataset_name)
    expect_required_columns(df, "dwh", safe_dataset_name, [key_column])
    expect_column_not_null(df, "dwh", safe_dataset_name, key_column)
    expect_no_duplicate_keys(df, "dwh", safe_dataset_name, [key_column])

# -----------------------------
# WRITE RESULTS
# -----------------------------
print("Writing DE-13 Data Quality results...")

results_df = spark.createDataFrame(results)

(
    results_df
    .coalesce(1)
    .write
    .mode("overwrite")
    .option("header", "true")
    .csv(DQ_RESULTS_HDFS_CSV)
)

(
    results_df
    .write
    .mode("overwrite")
    .parquet(DQ_RESULTS_HDFS_PARQUET)
)

os.makedirs(LOCAL_RESULTS_DIR, exist_ok=True)

fieldnames = [
    "check_id",
    "layer",
    "dataset",
    "expectation_type",
    "column_name",
    "rule_description",
    "severity",
    "status",
    "total_rows",
    "failed_rows",
    "success_percentage",
    "details",
    "checked_at"
]

with open(LOCAL_RESULTS_FILE, "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    for row in results:
        writer.writerow(row)

total_checks = len(results)
passed_checks = len([r for r in results if r["status"] == "PASS"])
warn_checks = len([r for r in results if r["status"] == "WARN"])
failed_checks = len([r for r in results if r["status"] == "FAIL"])
skipped_checks = len([r for r in results if r["status"] == "SKIP"])

print("")
print("DE-13 DATA QUALITY SUMMARY")
print(f"Total checks: {total_checks}")
print(f"Passed checks: {passed_checks}")
print(f"Warning checks: {warn_checks}")
print(f"Failed checks: {failed_checks}")
print(f"Skipped checks: {skipped_checks}")
print(f"Local result file: {LOCAL_RESULTS_FILE}")
print(f"HDFS CSV results: {DQ_RESULTS_HDFS_CSV}")
print(f"HDFS Parquet results: {DQ_RESULTS_HDFS_PARQUET}")
print("")
print("DE-13 completed: Data Quality / Great Expectations-style checks finished.")

spark.stop()

