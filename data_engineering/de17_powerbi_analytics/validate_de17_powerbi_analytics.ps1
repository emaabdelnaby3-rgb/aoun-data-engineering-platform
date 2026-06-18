$ErrorActionPreference = "Continue"

Write-Host "Validating DE-17 Power BI Analytics..."

$baseDir = ".\data_engineering\de17_powerbi_analytics"
$sqlFile = "$baseDir\sql\01_create_powerbi_analytics_views.sql"
$daxFile = "$baseDir\docs\DE17_POWERBI_DAX_MEASURES.md"
$guideFile = "$baseDir\docs\DE17_POWERBI_DASHBOARD_GUIDE.md"
$resultFile = "$baseDir\results\de17_powerbi_views_validation.txt"

foreach ($file in @($sqlFile, $daxFile, $guideFile)) {
    if (Test-Path $file) {
        Write-Host "PASS: $file exists"
    } else {
        Write-Host "FAIL: $file is missing"
    }
}

$query = @"
SET NOCOUNT ON;
USE charity_dwh;

SELECT COUNT(*) AS analytics_view_count
FROM sys.views v
JOIN sys.schemas s ON v.schema_id = s.schema_id
WHERE s.name = 'analytics';

SELECT
    s.name + '.' + v.name AS view_name
FROM sys.views v
JOIN sys.schemas s ON v.schema_id = s.schema_id
WHERE s.name = 'analytics'
ORDER BY view_name;

SELECT 'analytics.v_kpi_overview' AS view_name, COUNT_BIG(*) AS row_count FROM analytics.v_kpi_overview
UNION ALL SELECT 'analytics.v_dim_organization', COUNT_BIG(*) FROM analytics.v_dim_organization
UNION ALL SELECT 'analytics.v_dim_beneficiary', COUNT_BIG(*) FROM analytics.v_dim_beneficiary
UNION ALL SELECT 'analytics.v_dim_donor', COUNT_BIG(*) FROM analytics.v_dim_donor
UNION ALL SELECT 'analytics.v_fact_applications', COUNT_BIG(*) FROM analytics.v_fact_applications
UNION ALL SELECT 'analytics.v_fact_cases', COUNT_BIG(*) FROM analytics.v_fact_cases
UNION ALL SELECT 'analytics.v_fact_donations', COUNT_BIG(*) FROM analytics.v_fact_donations
UNION ALL SELECT 'analytics.v_fact_inventory_transactions', COUNT_BIG(*) FROM analytics.v_fact_inventory_transactions
UNION ALL SELECT 'analytics.v_donation_summary_by_organization', COUNT_BIG(*) FROM analytics.v_donation_summary_by_organization
UNION ALL SELECT 'analytics.v_application_summary_by_organization', COUNT_BIG(*) FROM analytics.v_application_summary_by_organization
UNION ALL SELECT 'analytics.v_case_summary_by_organization', COUNT_BIG(*) FROM analytics.v_case_summary_by_organization
UNION ALL SELECT 'analytics.v_inventory_summary_by_organization', COUNT_BIG(*) FROM analytics.v_inventory_summary_by_organization
UNION ALL SELECT 'analytics.v_dashboard_manifest', COUNT_BIG(*) FROM analytics.v_dashboard_manifest;
"@

$validationSql = "$baseDir\sql\validate_powerbi_views.sql"
$query | Set-Content $validationSql -Encoding UTF8

docker cp $validationSql "ucp_sqlserver:/tmp/validate_powerbi_views.sql"

$output = docker exec ucp_sqlserver /opt/mssql-tools18/bin/sqlcmd `
  -C `
  -S localhost `
  -U sa `
  -P "ChangeMe_StrongPassword_2026!" `
  -i /tmp/validate_powerbi_views.sql

$output | Set-Content $resultFile -Encoding UTF8

Write-Host ""
Write-Host "SQL Server validation output:"
$output

$viewCountOutput = docker exec ucp_sqlserver /opt/mssql-tools18/bin/sqlcmd `
  -C `
  -S localhost `
  -U sa `
  -P "ChangeMe_StrongPassword_2026!" `
  -Q "SET NOCOUNT ON; USE charity_dwh; SELECT COUNT(*) FROM sys.views v JOIN sys.schemas s ON v.schema_id=s.schema_id WHERE s.name='analytics';" `
  -h -1 -W

$viewCount = ($viewCountOutput | Where-Object { $_.Trim() -match "^\d+$" } | Select-Object -First 1).Trim()

if ($viewCount -and [int]$viewCount -ge 13) {
    Write-Host "PASS: Analytics schema has $viewCount Power BI views"
} else {
    Write-Host "FAIL: Expected at least 13 analytics views, found $viewCount"
}

docker exec ucp_hdfs_namenode hdfs dfs -test -d /charity_data_lake/gold/powerbi_exports/de17
if ($LASTEXITCODE -eq 0) {
    Write-Host "PASS: HDFS Power BI artifact archive exists"
} else {
    Write-Host "FAIL: HDFS Power BI artifact archive is missing"
}

docker exec ucp_hdfs_namenode hdfs dfs -ls /charity_data_lake/gold/powerbi_exports/de17

