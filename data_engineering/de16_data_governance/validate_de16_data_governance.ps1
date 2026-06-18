$ErrorActionPreference = "Continue"

Write-Host "Validating DE-16 Data Governance..."

$baseDir = ".\data_engineering\de16_data_governance"

$requiredFiles = @(
    "$baseDir\catalog\ucp_data_catalog.csv",
    "$baseDir\classification\ucp_pii_classification.csv",
    "$baseDir\lineage\ucp_data_lineage.csv",
    "$baseDir\policies\ucp_retention_policy.csv",
    "$baseDir\policies\ucp_access_control_policy.csv",
    "$baseDir\results\de16_data_governance_latest.json",
    "$baseDir\reports\DE16_DATA_GOVERNANCE_REPORT.md"
)

foreach ($file in $requiredFiles) {
    if (Test-Path $file) {
        Write-Host "PASS: $file exists"
    } else {
        Write-Host "FAIL: $file is missing"
    }
}

$catalog = Import-Csv "$baseDir\catalog\ucp_data_catalog.csv"
$class = Import-Csv "$baseDir\classification\ucp_pii_classification.csv"
$lineage = Import-Csv "$baseDir\lineage\ucp_data_lineage.csv"
$retention = Import-Csv "$baseDir\policies\ucp_retention_policy.csv"
$access = Import-Csv "$baseDir\policies\ucp_access_control_policy.csv"

Write-Host ""
Write-Host "Governance artifact counts:"
Write-Host "Data catalog records: $(@($catalog).Count)"
Write-Host "PII classification records: $(@($class).Count)"
Write-Host "Lineage steps: $(@($lineage).Count)"
Write-Host "Retention rules: $(@($retention).Count)"
Write-Host "Access roles: $(@($access).Count)"

if (@($catalog).Count -ge 15) {
    Write-Host "PASS: Data catalog has enough coverage"
} else {
    Write-Host "FAIL: Data catalog coverage is too small"
}

if (@($class).Count -ge 8) {
    Write-Host "PASS: PII classification has enough coverage"
} else {
    Write-Host "FAIL: PII classification coverage is too small"
}

if (@($lineage).Count -ge 7) {
    Write-Host "PASS: Data lineage covers the full pipeline"
} else {
    Write-Host "FAIL: Data lineage is incomplete"
}

docker exec ucp_hdfs_namenode hdfs dfs -test -d /charity_data_lake/gold/governance/de16
if ($LASTEXITCODE -eq 0) {
    Write-Host "PASS: HDFS governance archive folder exists"
} else {
    Write-Host "FAIL: HDFS governance archive folder is missing"
}

docker exec ucp_hdfs_namenode hdfs dfs -ls /charity_data_lake/gold/governance/de16
