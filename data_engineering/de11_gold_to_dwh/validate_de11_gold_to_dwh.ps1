$ErrorActionPreference = "Continue"

Write-Host "Validating DE-11 Gold to SQL Server DWH..."

$query = @"
USE charity_dwh;

SELECT 'gold.dim_organization' AS table_name, COUNT(*) AS rows_count FROM gold.dim_organization
UNION ALL
SELECT 'gold.dim_beneficiary', COUNT(*) FROM gold.dim_beneficiary
UNION ALL
SELECT 'gold.dim_donor', COUNT(*) FROM gold.dim_donor
UNION ALL
SELECT 'gold.fact_applications', COUNT(*) FROM gold.fact_applications
UNION ALL
SELECT 'gold.fact_cases', COUNT(*) FROM gold.fact_cases
UNION ALL
SELECT 'gold.fact_donations', COUNT(*) FROM gold.fact_donations
UNION ALL
SELECT 'gold.fact_inventory_transactions', COUNT(*) FROM gold.fact_inventory_transactions;
"@

docker exec ucp_sqlserver /opt/mssql-tools18/bin/sqlcmd `
  -C `
  -S localhost `
  -U sa `
  -P "ChangeMe_StrongPassword_2026!" `
  -W `
  -Q $query

