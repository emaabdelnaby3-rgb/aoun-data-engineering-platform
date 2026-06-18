$ErrorActionPreference = "Continue"

Write-Host "Validating DE-12 Power BI Views..."

$query = @"
USE charity_dwh;

SELECT 'gold.vw_government_overview' AS view_name, COUNT(*) AS rows_count FROM gold.vw_government_overview
UNION ALL
SELECT 'gold.vw_organization_performance', COUNT(*) FROM gold.vw_organization_performance
UNION ALL
SELECT 'gold.vw_case_funding_analysis', COUNT(*) FROM gold.vw_case_funding_analysis
UNION ALL
SELECT 'gold.vw_donation_analysis', COUNT(*) FROM gold.vw_donation_analysis
UNION ALL
SELECT 'gold.vw_inventory_support_analysis', COUNT(*) FROM gold.vw_inventory_support_analysis
UNION ALL
SELECT 'gold.vw_beneficiary_360', COUNT(*) FROM gold.vw_beneficiary_360;
"@

docker exec ucp_sqlserver /opt/mssql-tools18/bin/sqlcmd `
  -C `
  -S localhost `
  -U sa `
  -P "ChangeMe_StrongPassword_2026!" `
  -W `
  -Q $query

