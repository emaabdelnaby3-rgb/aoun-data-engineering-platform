from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    col,
    current_timestamp,
    from_json,
    schema_of_json,
    lit
)

BRONZE_PATH = "hdfs://hdfs-namenode:9000/charity_data_lake/bronze/kafka_events"
SILVER_BASE_PATH = "hdfs://hdfs-namenode:9000/charity_data_lake/silver"

TARGET_TABLES = [
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

spark = (
    SparkSession.builder
    .appName("DE9_Bronze_To_Silver_Cleaning")
    .getOrCreate()
)

spark.sparkContext.setLogLevel("WARN")

bronze_df = spark.read.parquet(BRONZE_PATH)

for table_name in TARGET_TABLES:
    table_bronze = bronze_df.filter(col("source_table") == table_name)

    if table_bronze.rdd.isEmpty():
        print(f"Skipping {table_name}: no bronze data found.")
        continue

    sample_json = (
        table_bronze
        .select("kafka_message_value")
        .where(col("kafka_message_value").isNotNull())
        .limit(1)
        .collect()[0][0]
    )

    envelope_schema = schema_of_json(sample_json)

    parsed_df = (
        table_bronze
        .withColumn("debezium_payload", from_json(col("kafka_message_value"), envelope_schema))
    )

    # Debezium envelope contains payload.after for the current row.
    after_schema = parsed_df.select("debezium_payload.payload.after").schema[0].dataType

    silver_df = (
        parsed_df
        .withColumn("after", col("debezium_payload.payload.after").cast(after_schema))
        .select(
            col("source_org"),
            col("source_database"),
            col("source_table"),
            col("kafka_partition"),
            col("kafka_offset"),
            col("kafka_timestamp"),
            col("bronze_ingested_at"),
            col("after.*")
        )
        .withColumn("silver_processed_at", current_timestamp())
        .dropDuplicates(["source_org", "source_table", "kafka_partition", "kafka_offset"])
    )

    output_path = f"{SILVER_BASE_PATH}/{table_name}"

    (
        silver_df
        .write
        .mode("overwrite")
        .parquet(output_path)
    )

    print(f"DE-9 written Silver table: {table_name} -> {output_path}")

print("DE-9 completed: Bronze data cleaned and written to Silver.")
