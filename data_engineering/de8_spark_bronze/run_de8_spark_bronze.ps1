docker exec ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/bronze/kafka_events
docker exec ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/bronze/checkpoints/kafka_events
docker exec ucp_hdfs_namenode hdfs dfs -chmod -R 777 /charity_data_lake

docker exec -it ucp_spark_master /opt/spark/bin/spark-submit `
  --master spark://spark-master:7077 `
  --deploy-mode client `
  --driver-memory 1g `
  --executor-memory 1g `
  --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.1 `
  /opt/spark/data_engineering/de8_spark_bronze/jobs/bronze_kafka_to_hdfs.py
