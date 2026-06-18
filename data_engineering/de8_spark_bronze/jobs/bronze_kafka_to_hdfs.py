from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    col,
    current_timestamp,
    split,
    to_date
)

KAFKA_BOOTSTRAP_SERVERS = "kafka:29092"

TOPIC_PATTERN = (
    "(food_bank|resala|haya_karima)"
    "\\.charity_.*\\.dbo\\."
    "(beneficiaries|applications|cases|donors|donations|inventory_items|"
    "inventory_transactions|beneficiary_documents|source_event_outbox)"
)

BRONZE_OUTPUT_PATH = "hdfs://hdfs-namenode:9000/charity_data_lake/bronze/kafka_events"
CHECKPOINT_PATH = "hdfs://hdfs-namenode:9000/charity_data_lake/bronze/checkpoints/kafka_events"

spark = (
    SparkSession.builder
    .appName("DE8_Kafka_Debezium_To_HDFS_Bronze")
    .getOrCreate()
)

spark.sparkContext.setLogLevel("WARN")

raw_kafka_df = (
    spark.readStream
    .format("kafka")
    .option("kafka.bootstrap.servers", KAFKA_BOOTSTRAP_SERVERS)
    .option("subscribePattern", TOPIC_PATTERN)
    .option("startingOffsets", "earliest")
    .option("failOnDataLoss", "false")
    .load()
)

topic_parts = split(col("topic"), "\\.")

bronze_df = (
    raw_kafka_df
    .select(
        col("topic"),
        col("partition").alias("kafka_partition"),
        col("offset").alias("kafka_offset"),
        col("timestamp").alias("kafka_timestamp"),
        col("key").cast("string").alias("kafka_message_key"),
        col("value").cast("string").alias("kafka_message_value")
    )
    .withColumn("source_org", topic_parts.getItem(0))
    .withColumn("source_database", topic_parts.getItem(1))
    .withColumn("source_schema", topic_parts.getItem(2))
    .withColumn("source_table", topic_parts.getItem(3))
    .withColumn("bronze_ingested_at", current_timestamp())
    .withColumn("ingestion_date", to_date(col("bronze_ingested_at")))
)

query = (
    bronze_df.writeStream
    .format("parquet")
    .option("path", BRONZE_OUTPUT_PATH)
    .option("checkpointLocation", CHECKPOINT_PATH)
    .partitionBy("source_org", "source_table", "ingestion_date")
    .trigger(availableNow=True)
    .start()
)

query.awaitTermination()

print("DE-8 completed: Kafka/Debezium events written to HDFS Bronze.")
