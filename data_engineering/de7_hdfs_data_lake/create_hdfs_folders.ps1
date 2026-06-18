docker exec -it ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/bronze/kafka_events
docker exec -it ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/bronze/source_snapshots
docker exec -it ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/bronze/rejected_records

docker exec -it ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/silver/beneficiaries
docker exec -it ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/silver/applications
docker exec -it ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/silver/cases
docker exec -it ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/silver/donations
docker exec -it ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/silver/inventory_transactions
docker exec -it ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/silver/fraud_alerts
docker exec -it ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/silver/data_quality_issues

docker exec -it ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/gold/dimensions
docker exec -it ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/gold/facts
docker exec -it ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/gold/powerbi_exports

docker exec -it ucp_hdfs_namenode hdfs dfs -ls /charity_data_lake
docker exec -it ucp_hdfs_namenode hdfs dfs -ls /charity_data_lake/bronze
docker exec -it ucp_hdfs_namenode hdfs dfs -ls /charity_data_lake/silver
docker exec -it ucp_hdfs_namenode hdfs dfs -ls /charity_data_lake/gold
