$ErrorActionPreference = "Continue"

Write-Host "Validating DE-10 Gold Layer..."

$goldTables = @(
    "/charity_data_lake/gold/dimensions/dim_organization",
    "/charity_data_lake/gold/dimensions/dim_beneficiary",
    "/charity_data_lake/gold/dimensions/dim_donor",
    "/charity_data_lake/gold/facts/fact_applications",
    "/charity_data_lake/gold/facts/fact_cases",
    "/charity_data_lake/gold/facts/fact_donations",
    "/charity_data_lake/gold/facts/fact_inventory_transactions"
)

foreach ($tablePath in $goldTables) {
    docker exec ucp_hdfs_namenode hdfs dfs -test -d $tablePath

    if ($LASTEXITCODE -eq 0) {
        $files = docker exec ucp_hdfs_namenode hdfs dfs -find $tablePath -name "*.parquet" 2>$null
        $count = @($files | Where-Object { $_ -match "\.parquet$" }).Count

        if ($count -gt 0) {
            Write-Host "PASS: $tablePath has $count parquet file(s)"
        } else {
            Write-Host "FAIL: $tablePath exists but has no parquet files"
        }
    } else {
        Write-Host "FAIL: $tablePath is missing"
    }
}
