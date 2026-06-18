docker exec ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/gold/dimensions
docker exec ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/gold/facts
docker exec ucp_hdfs_namenode hdfs dfs -chmod -R 777 /charity_data_lake

docker exec -it ucp_spark_master /opt/spark/bin/spark-submit `
  --master spark://spark-master:7077 `
  --deploy-mode client `
  --driver-memory 1g `
  --executor-memory 1g `
  /opt/spark/data_engineering/de10_spark_gold/jobs/gold_from_silver.py
