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
