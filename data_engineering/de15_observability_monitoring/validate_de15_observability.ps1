$ErrorActionPreference = "Continue"

Write-Host "Validating DE-15 Observability / Monitoring..."

$baseDir = ".\data_engineering\de15_observability_monitoring"
$csvFile = "$baseDir\results\de15_observability_latest.csv"
$jsonFile = "$baseDir\results\de15_observability_latest.json"
$mdFile = "$baseDir\reports\DE15_OBSERVABILITY_HEALTH_REPORT.md"

if (Test-Path $csvFile) {
    Write-Host "PASS: Observability CSV report exists"
    $rows = Import-Csv $csvFile

    $total = @($rows).Count
    $passed = @($rows | Where-Object { $_.status -eq "PASS" }).Count
    $warn = @($rows | Where-Object { $_.status -eq "WARN" }).Count
    $failed = @($rows | Where-Object { $_.status -eq "FAIL" }).Count

    Write-Host "Total metrics: $total"
    Write-Host "Passed metrics: $passed"
    Write-Host "Warning metrics: $warn"
    Write-Host "Failed metrics: $failed"

    if ($failed -eq 0) {
        Write-Host "PASS: No failed observability metrics detected"
    } else {
        Write-Host "WARNING: Some observability metrics failed"
        $rows | Where-Object { $_.status -eq "FAIL" } | Select-Object component, metric_name, value, details | Format-Table -AutoSize
    }
} else {
    Write-Host "FAIL: Observability CSV report is missing"
}

if (Test-Path $jsonFile) {
    Write-Host "PASS: Observability JSON report exists"
} else {
    Write-Host "FAIL: Observability JSON report is missing"
}

if (Test-Path $mdFile) {
    Write-Host "PASS: Observability Markdown report exists"
} else {
    Write-Host "FAIL: Observability Markdown report is missing"
}

docker exec ucp_hdfs_namenode hdfs dfs -test -d /charity_data_lake/gold/observability/de15
if ($LASTEXITCODE -eq 0) {
    Write-Host "PASS: HDFS observability archive folder exists"
} else {
    Write-Host "FAIL: HDFS observability archive folder is missing"
}

docker exec ucp_hdfs_namenode hdfs dfs -ls /charity_data_lake/gold/observability/de15
