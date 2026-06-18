docker exec ucp_hdfs_namenode hdfs dfs -chmod -R 777 /charity_data_lake

docker exec -it ucp_spark_master /opt/spark/bin/spark-submit `
  --master spark://spark-master:7077 `
  --deploy-mode client `
  --driver-memory 1g `
  --executor-memory 1g `
  /opt/spark/data_engineering/de9_spark_silver/jobs/silver_from_bronze.py
