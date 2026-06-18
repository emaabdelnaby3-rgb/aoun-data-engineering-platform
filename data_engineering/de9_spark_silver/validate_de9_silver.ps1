$ErrorActionPreference = "Continue"

Write-Host "Validating DE-9 Silver Layer..."

$tables = @(
    "beneficiaries",
    "applications",
    "cases",
    "donations",
    "donors",
    "inventory_items",
    "inventory_transactions",
    "beneficiary_documents",
    "source_event_outbox"
)

foreach ($table in $tables) {
    docker exec ucp_hdfs_namenode hdfs dfs -test -d "/charity_data_lake/silver/$table"

    if ($LASTEXITCODE -eq 0) {
        $files = docker exec ucp_hdfs_namenode hdfs dfs -find "/charity_data_lake/silver/$table" -name "*.parquet" 2>$null
        $count = @($files | Where-Object { $_ -match "\.parquet$" }).Count

        if ($count -gt 0) {
            Write-Host "PASS: Silver table $table has $count parquet file(s)"
        } else {
            Write-Host "FAIL: Silver table $table folder exists but has no parquet files"
        }
    } else {
        Write-Host "FAIL: Silver table $table folder missing"
    }
}
