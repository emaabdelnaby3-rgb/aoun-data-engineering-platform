from pyspark.sql import SparkSession

GOLD_BASE_PATH = "hdfs://hdfs-namenode:9000/charity_data_lake/gold"

SQLSERVER_JDBC_URL = (
    "jdbc:sqlserver://sqlserver:1433;"
    "databaseName=charity_dwh;"
    "encrypt=false;"
    "trustServerCertificate=true"
)

SQLSERVER_USER = "sa"
SQLSERVER_PASSWORD = "ChangeMe_StrongPassword_2026!"
SQLSERVER_DRIVER = "com.microsoft.sqlserver.jdbc.SQLServerDriver"

DATASETS = {
    "gold.dim_organization": f"{GOLD_BASE_PATH}/dimensions/dim_organization",
    "gold.dim_beneficiary": f"{GOLD_BASE_PATH}/dimensions/dim_beneficiary",
    "gold.dim_donor": f"{GOLD_BASE_PATH}/dimensions/dim_donor",
    "gold.fact_applications": f"{GOLD_BASE_PATH}/facts/fact_applications",
    "gold.fact_cases": f"{GOLD_BASE_PATH}/facts/fact_cases",
    "gold.fact_donations": f"{GOLD_BASE_PATH}/facts/fact_donations",
    "gold.fact_inventory_transactions": f"{GOLD_BASE_PATH}/facts/fact_inventory_transactions",
}

spark = (
    SparkSession.builder
    .appName("DE11_Gold_To_SQLServer_DWH")
    .getOrCreate()
)

spark.sparkContext.setLogLevel("WARN")

for target_table, source_path in DATASETS.items():
    print(f"Reading Gold dataset: {source_path}")
    df = spark.read.parquet(source_path)

    row_count = df.count()
    print(f"Loading {row_count} rows into SQL Server table: {target_table}")

    (
        df.write
        .format("jdbc")
        .mode("overwrite")
        .option("url", SQLSERVER_JDBC_URL)
        .option("dbtable", target_table)
        .option("user", SQLSERVER_USER)
        .option("password", SQLSERVER_PASSWORD)
        .option("driver", SQLSERVER_DRIVER)
        .save()
    )

    print(f"Loaded table successfully: {target_table}")

print("DE-11 completed: Gold HDFS datasets loaded into SQL Server DWH.")

