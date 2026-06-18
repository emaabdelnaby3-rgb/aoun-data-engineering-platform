$ErrorActionPreference = "Continue"

Write-Host "Validating DE-8 Spark Bronze..."

$containers = docker ps --format "{{.Names}}"

if ($containers -contains "ucp_spark_master") {
    Write-Host "PASS: Spark master is running"
} else {
    Write-Host "FAIL: Spark master is not running"
}

if ($containers -contains "ucp_spark_worker") {
    Write-Host "PASS: Spark worker is running"
} else {
    Write-Host "FAIL: Spark worker is not running"
}

docker exec ucp_hdfs_namenode hdfs dfs -test -d /charity_data_lake/bronze/kafka_events
if ($LASTEXITCODE -eq 0) {
    Write-Host "PASS: Bronze kafka_events folder exists"
} else {
    Write-Host "FAIL: Bronze kafka_events folder missing"
}

$parquetFiles = docker exec ucp_hdfs_namenode hdfs dfs -find /charity_data_lake/bronze/kafka_events -name "*.parquet" 2>$null
$fileCount = @($parquetFiles | Where-Object { $_ -match "\.parquet$" }).Count

Write-Host "Bronze parquet files count: $fileCount"

if ($fileCount -gt 0) {
    Write-Host "PASS: Kafka/Debezium events were written to HDFS Bronze"
    Write-Host ""
    Write-Host "Sample files:"
    $parquetFiles | Select-Object -First 10
} else {
    Write-Host "FAIL: No parquet files found in HDFS Bronze yet"
    Write-Host ""
    Write-Host "Showing Bronze folder structure:"
    docker exec ucp_hdfs_namenode hdfs dfs -ls -R /charity_data_lake/bronze/kafka_events
}
