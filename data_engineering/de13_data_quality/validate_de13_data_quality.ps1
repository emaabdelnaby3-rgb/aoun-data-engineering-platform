$ErrorActionPreference = "Continue"

Write-Host "Validating DE-13 Data Quality..."

$localResult = ".\data_engineering\de13_data_quality\results\de13_latest_results.csv"

if (Test-Path $localResult) {
    Write-Host "PASS: Local data quality result file exists"
    $rows = Import-Csv $localResult

    $total = @($rows).Count
    $passed = @($rows | Where-Object { $_.status -eq "PASS" }).Count
    $warn = @($rows | Where-Object { $_.status -eq "WARN" }).Count
    $failed = @($rows | Where-Object { $_.status -eq "FAIL" }).Count
    $skipped = @($rows | Where-Object { $_.status -eq "SKIP" }).Count

    Write-Host "Total checks: $total"
    Write-Host "Passed checks: $passed"
    Write-Host "Warning checks: $warn"
    Write-Host "Failed checks: $failed"
    Write-Host "Skipped checks: $skipped"

    if ($failed -eq 0) {
        Write-Host "PASS: No critical data quality failures detected"
    } else {
        Write-Host "WARNING: Some data quality checks failed"
        $rows | Where-Object { $_.status -eq "FAIL" } | Select-Object check_id, layer, dataset, column_name, details | Format-Table -AutoSize
    }
} else {
    Write-Host "FAIL: Local data quality result file is missing"
}

docker exec ucp_hdfs_namenode hdfs dfs -test -d /charity_data_lake/silver/data_quality_issues/de13_run_results_csv
if ($LASTEXITCODE -eq 0) {
    Write-Host "PASS: HDFS CSV data quality results folder exists"
} else {
    Write-Host "FAIL: HDFS CSV data quality results folder is missing"
}

docker exec ucp_hdfs_namenode hdfs dfs -test -d /charity_data_lake/silver/data_quality_issues/de13_run_results_parquet
if ($LASTEXITCODE -eq 0) {
    Write-Host "PASS: HDFS Parquet data quality results folder exists"
} else {
    Write-Host "FAIL: HDFS Parquet data quality results folder is missing"
}
