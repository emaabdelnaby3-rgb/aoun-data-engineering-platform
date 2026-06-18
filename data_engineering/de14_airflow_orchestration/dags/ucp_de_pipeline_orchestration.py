from datetime import datetime
from airflow import DAG
from airflow.operators.bash import BashOperator

DEFAULT_ARGS = {
    "owner": "ucp_data_engineering_team",
    "depends_on_past": False,
    "retries": 0,
}

with DAG(
    dag_id="ucp_de_pipeline_orchestration",
    description="Unified Charity Platform full Data Engineering orchestration DAG",
    default_args=DEFAULT_ARGS,
    start_date=datetime(2026, 1, 1),
    schedule_interval=None,
    catchup=False,
    tags=["ucp", "data-engineering", "graduation-project", "hdfs", "spark", "dwh"],
) as dag:

    check_core_containers = BashOperator(
        task_id="check_core_containers",
        bash_command="""
        set -e
        echo "Checking required containers..."
        docker ps --format '{% raw %}{{.Names}}{% endraw %}' | grep -E '^ucp_sqlserver$'
        docker ps --format '{% raw %}{{.Names}}{% endraw %}' | grep -E '^ucp_kafka$'
        docker ps --format '{% raw %}{{.Names}}{% endraw %}' | grep -E '^ucp_debezium_connect$'
        docker ps --format '{% raw %}{{.Names}}{% endraw %}' | grep -E '^ucp_hdfs_namenode$'
        docker ps --format '{% raw %}{{.Names}}{% endraw %}' | grep -E '^ucp_spark_master$'
        docker ps --format '{% raw %}{{.Names}}{% endraw %}' | grep -E '^ucp_spark_worker$'
        echo "Core containers are running."
        """,
    )

    check_schema_registry = BashOperator(
        task_id="check_schema_registry",
        bash_command="""
        set -e
        echo "Checking Schema Registry..."
        docker ps --format '{% raw %}{{.Names}}{% endraw %}' | grep -E '^ucp_schema_registry$'
        python -c "import urllib.request; print(urllib.request.urlopen('http://ucp_schema_registry:8081/subjects', timeout=20).read().decode())"
        echo ""
        echo "Schema Registry is reachable."
        """,
    )

    check_hdfs_data_lake = BashOperator(
        task_id="check_hdfs_data_lake",
        bash_command="""
        set -e
        echo "Checking HDFS data lake folders..."
        docker exec ucp_hdfs_namenode hdfs dfs -test -d /charity_data_lake/bronze
        docker exec ucp_hdfs_namenode hdfs dfs -test -d /charity_data_lake/silver
        docker exec ucp_hdfs_namenode hdfs dfs -test -d /charity_data_lake/gold
        echo "HDFS Bronze/Silver/Gold folders exist."
        """,
    )

    run_de8_bronze = BashOperator(
        task_id="run_de8_kafka_to_bronze",
        bash_command="""
        set -e
        echo "Running DE-8 Kafka/Debezium to HDFS Bronze..."
        docker exec ucp_hdfs_namenode hdfs dfs -chmod -R 777 /charity_data_lake
        docker exec ucp_spark_master /opt/spark/bin/spark-submit \
          --master spark://spark-master:7077 \
          --deploy-mode client \
          --driver-memory 1g \
          --executor-memory 1g \
          --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.1 \
          /opt/spark/data_engineering/de8_spark_bronze/jobs/bronze_kafka_to_hdfs.py
        echo "DE-8 completed."
        """,
    )

    run_de9_silver = BashOperator(
        task_id="run_de9_bronze_to_silver",
        bash_command="""
        set -e
        echo "Running DE-9 Bronze to Silver..."
        docker exec ucp_hdfs_namenode hdfs dfs -chmod -R 777 /charity_data_lake
        docker exec ucp_spark_master /opt/spark/bin/spark-submit \
          --master spark://spark-master:7077 \
          --deploy-mode client \
          --driver-memory 1g \
          --executor-memory 1g \
          /opt/spark/data_engineering/de9_spark_silver/jobs/silver_from_bronze.py
        echo "DE-9 completed."
        """,
    )

    run_de10_gold = BashOperator(
        task_id="run_de10_silver_to_gold",
        bash_command="""
        set -e
        echo "Running DE-10 Silver to Gold..."
        docker exec ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/gold/dimensions
        docker exec ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/gold/facts
        docker exec ucp_hdfs_namenode hdfs dfs -chmod -R 777 /charity_data_lake
        docker exec ucp_spark_master /opt/spark/bin/spark-submit \
          --master spark://spark-master:7077 \
          --deploy-mode client \
          --driver-memory 1g \
          --executor-memory 1g \
          /opt/spark/data_engineering/de10_spark_gold/jobs/gold_from_silver.py
        echo "DE-10 completed."
        """,
    )

    run_de11_dwh = BashOperator(
        task_id="run_de11_gold_to_sqlserver_dwh",
        bash_command="""
        set -e
        echo "Running DE-11 Gold to SQL Server DWH..."
        docker exec ucp_sqlserver /opt/mssql-tools18/bin/sqlcmd \
          -C \
          -S localhost \
          -U sa \
          -P "ChangeMe_StrongPassword_2026!" \
          -Q "USE charity_dwh; IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'gold') EXEC('CREATE SCHEMA gold');"

        docker exec ucp_spark_master /opt/spark/bin/spark-submit \
          --master spark://spark-master:7077 \
          --deploy-mode client \
          --driver-memory 1g \
          --executor-memory 1g \
          --packages com.microsoft.sqlserver:mssql-jdbc:12.6.1.jre11 \
          /opt/spark/data_engineering/de11_gold_to_dwh/jobs/load_gold_to_sqlserver.py
        echo "DE-11 completed."
        """,
    )

    run_de13_quality = BashOperator(
        task_id="run_de13_data_quality_checks",
        bash_command="""
        set -e
        echo "Running DE-13 Data Quality checks..."
        docker exec ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/silver/data_quality_issues
        docker exec ucp_hdfs_namenode hdfs dfs -chmod -R 777 /charity_data_lake/silver/data_quality_issues
        docker exec ucp_spark_master /opt/spark/bin/spark-submit \
          --master spark://spark-master:7077 \
          --deploy-mode client \
          --driver-memory 1g \
          --executor-memory 1g \
          --packages com.microsoft.sqlserver:mssql-jdbc:12.6.1.jre11 \
          /opt/spark/data_engineering/de13_data_quality/jobs/run_data_quality_checks.py
        echo "DE-13 completed."
        """,
    )

    (
        check_core_containers
        >> check_schema_registry
        >> check_hdfs_data_lake
        >> run_de8_bronze
        >> run_de9_silver
        >> run_de10_gold
        >> run_de11_dwh
        >> run_de13_quality
    )



