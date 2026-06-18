$ErrorActionPreference = "Stop"

Write-Host "Running DE-17 Power BI Analytics Layer..."

$baseDir = ".\data_engineering\de17_powerbi_analytics"
$sqlFile = "$baseDir\sql\01_create_powerbi_analytics_views.sql"
$daxFile = "$baseDir\docs\DE17_POWERBI_DAX_MEASURES.md"
$guideFile = "$baseDir\docs\DE17_POWERBI_DASHBOARD_GUIDE.md"

Write-Host "Copying SQL script into SQL Server container..."
docker cp $sqlFile "ucp_sqlserver:/tmp/01_create_powerbi_analytics_views.sql"

Write-Host "Creating analytics views in charity_dwh..."
docker exec ucp_sqlserver /opt/mssql-tools18/bin/sqlcmd `
  -C `
  -S localhost `
  -U sa `
  -P "ChangeMe_StrongPassword_2026!" `
  -i /tmp/01_create_powerbi_analytics_views.sql

Write-Host "Archiving DE-17 Power BI artifacts into HDFS..."

docker exec ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/gold/powerbi_exports/de17
docker exec ucp_hdfs_namenode hdfs dfs -chmod -R 777 /charity_data_lake/gold/powerbi_exports

$filesToArchive = @($sqlFile, $daxFile, $guideFile)

foreach ($file in $filesToArchive) {
    $fileName = Split-Path $file -Leaf
    docker cp $file "ucp_hdfs_namenode:/tmp/$fileName"
    docker exec ucp_hdfs_namenode hdfs dfs -put -f "/tmp/$fileName" "/charity_data_lake/gold/powerbi_exports/de17/$fileName"
}

Write-Host ""
Write-Host "DE-17 completed: Power BI analytics views and documentation are ready."
Write-Host "Power BI server: localhost,1433"
Write-Host "Database: charity_dwh"
Write-Host "Schema: analytics"

