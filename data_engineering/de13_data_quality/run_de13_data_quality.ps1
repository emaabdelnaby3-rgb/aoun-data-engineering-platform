docker exec ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/silver/data_quality_issues
docker exec ucp_hdfs_namenode hdfs dfs -chmod -R 777 /charity_data_lake/silver/data_quality_issues

docker exec -it ucp_spark_master /opt/spark/bin/spark-submit `
  --master spark://spark-master:7077 `
  --deploy-mode client `
  --driver-memory 1g `
  --executor-memory 1g `
  --packages com.microsoft.sqlserver:mssql-jdbc:12.6.1.jre11 `
  /opt/spark/data_engineering/de13_data_quality/jobs/run_data_quality_checks.py
