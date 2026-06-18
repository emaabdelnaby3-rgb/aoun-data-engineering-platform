docker exec ucp_sqlserver /opt/mssql-tools18/bin/sqlcmd `
  -C `
  -S localhost `
  -U sa `
  -P "ChangeMe_StrongPassword_2026!" `
  -Q "USE charity_dwh; IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'gold') EXEC('CREATE SCHEMA gold');"

docker exec -it ucp_spark_master /opt/spark/bin/spark-submit `
  --master spark://spark-master:7077 `
  --deploy-mode client `
  --driver-memory 1g `
  --executor-memory 1g `
  --packages com.microsoft.sqlserver:mssql-jdbc:12.6.1.jre11 `
  /opt/spark/data_engineering/de11_gold_to_dwh/jobs/load_gold_to_sqlserver.py

