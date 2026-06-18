USE charity_dwh;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'analytics')
BEGIN
    EXEC('CREATE SCHEMA analytics');
END
GO

CREATE OR ALTER VIEW analytics.v_dim_organization AS
SELECT * FROM gold.dim_organization;
GO

CREATE OR ALTER VIEW analytics.v_dim_beneficiary AS
SELECT * FROM gold.dim_beneficiary;
GO

CREATE OR ALTER VIEW analytics.v_dim_donor AS
SELECT * FROM gold.dim_donor;
GO

CREATE OR ALTER VIEW analytics.v_fact_applications AS
SELECT * FROM gold.fact_applications;
GO

CREATE OR ALTER VIEW analytics.v_fact_cases AS
SELECT * FROM gold.fact_cases;
GO

CREATE OR ALTER VIEW analytics.v_fact_donations AS
SELECT * FROM gold.fact_donations;
GO

CREATE OR ALTER VIEW analytics.v_fact_inventory_transactions AS
SELECT * FROM gold.fact_inventory_transactions;
GO

CREATE OR ALTER VIEW analytics.v_kpi_overview AS
SELECT
    (SELECT COUNT_BIG(*) FROM gold.dim_organization) AS total_organizations,
    (SELECT COUNT_BIG(*) FROM gold.dim_beneficiary) AS total_beneficiaries,
    (SELECT COUNT_BIG(*) FROM gold.dim_donor) AS total_donors,
    (SELECT COUNT_BIG(*) FROM gold.fact_applications) AS total_applications,
    (SELECT COUNT_BIG(*) FROM gold.fact_cases) AS total_cases,
    (SELECT COUNT_BIG(*) FROM gold.fact_donations) AS total_donations,
    (SELECT COUNT_BIG(*) FROM gold.fact_inventory_transactions) AS total_inventory_transactions,
    COALESCE((SELECT SUM(CAST(donation_amount AS DECIMAL(18,2))) FROM gold.fact_donations), 0) AS total_donation_amount;
GO

CREATE OR ALTER VIEW analytics.v_donation_summary_by_organization AS
SELECT
    organization_sk,
    COUNT_BIG(*) AS donation_count,
    SUM(CAST(donation_amount AS DECIMAL(18,2))) AS total_donation_amount
FROM gold.fact_donations
GROUP BY organization_sk;
GO

CREATE OR ALTER VIEW analytics.v_application_summary_by_organization AS
SELECT
    organization_sk,
    COUNT_BIG(*) AS application_count,
    AVG(CAST(priority_score AS DECIMAL(18,2))) AS avg_priority_score
FROM gold.fact_applications
GROUP BY organization_sk;
GO

CREATE OR ALTER VIEW analytics.v_case_summary_by_organization AS
SELECT
    organization_sk,
    COUNT_BIG(*) AS case_count,
    SUM(CAST(target_amount AS DECIMAL(18,2))) AS total_target_amount,
    SUM(CAST(collected_amount AS DECIMAL(18,2))) AS total_collected_amount,
    AVG(CAST(priority_score AS DECIMAL(18,2))) AS avg_case_priority_score
FROM gold.fact_cases
GROUP BY organization_sk;
GO

CREATE OR ALTER VIEW analytics.v_inventory_summary_by_organization AS
SELECT
    organization_sk,
    COUNT_BIG(*) AS inventory_transaction_count,
    SUM(CAST(quantity AS DECIMAL(18,2))) AS total_quantity
FROM gold.fact_inventory_transactions
GROUP BY organization_sk;
GO

CREATE OR ALTER VIEW analytics.v_dashboard_manifest AS
SELECT
    'Unified Charity Platform' AS project_name,
    'DE-17 Power BI Analytics Layer' AS phase_name,
    'analytics schema views created for dashboard consumption' AS description,
    GETDATE() AS generated_at;
GO

PRINT 'DE-17 Power BI analytics views created successfully.';
GO
