USE charity_dwh;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'analytics_real')
BEGIN
    EXEC('CREATE SCHEMA analytics_real');
END
GO

CREATE OR ALTER VIEW analytics_real.v_dim_organization AS
SELECT 1 AS organization_sk, 'food_bank' AS organization_code, 'Food Bank' AS organization_name
UNION ALL
SELECT 2, 'resala', 'Resala'
UNION ALL
SELECT 3, 'haya_karima', 'Haya Karima';
GO

CREATE OR ALTER VIEW analytics_real.v_dim_beneficiary AS
SELECT
    1 AS organization_sk,
    'food_bank' AS organization_code,
    source_beneficiary_id AS beneficiary_id,
    national_id,
    COALESCE(full_name, 'Unknown') AS full_name,
    COALESCE(gender, 'Unknown') AS gender,
    birth_date,
    COALESCE(governorate_name, 'Unknown') AS governorate,
    COALESCE(city_name, 'Unknown') AS city,
    COALESCE(family_size, 0) AS family_size,
    COALESCE(monthly_income, 0) AS monthly_income,
    COALESCE(employment_status, 'Unknown') AS employment_status,
    created_at
FROM charity_food_bank_operational.dbo.beneficiaries

UNION ALL

SELECT
    2,
    'resala',
    source_beneficiary_id,
    national_id,
    COALESCE(full_name, 'Unknown'),
    COALESCE(gender, 'Unknown'),
    birth_date,
    COALESCE(governorate_name, 'Unknown'),
    COALESCE(city_name, 'Unknown'),
    COALESCE(family_size, 0),
    COALESCE(monthly_income, 0),
    COALESCE(employment_status, 'Unknown'),
    created_at
FROM charity_resala_operational.dbo.beneficiaries

UNION ALL

SELECT
    3,
    'haya_karima',
    source_beneficiary_id,
    national_id,
    COALESCE(full_name, 'Unknown'),
    COALESCE(gender, 'Unknown'),
    birth_date,
    COALESCE(governorate_name, 'Unknown'),
    COALESCE(city_name, 'Unknown'),
    COALESCE(family_size, 0),
    COALESCE(monthly_income, 0),
    COALESCE(employment_status, 'Unknown'),
    created_at
FROM charity_haya_karima_operational.dbo.beneficiaries;
GO

CREATE OR ALTER VIEW analytics_real.v_dim_donor AS
SELECT
    1 AS organization_sk,
    'food_bank' AS organization_code,
    source_donor_id AS donor_id,
    donor_code,
    COALESCE(donor_name, 'Unknown') AS donor_name,
    COALESCE(donor_category, 'Unknown') AS donor_category,
    COALESCE(email, 'Unknown') AS email,
    COALESCE(phone, 'Unknown') AS phone,
    created_at
FROM charity_food_bank_operational.dbo.donors

UNION ALL

SELECT
    2,
    'resala',
    source_donor_id,
    donor_code,
    COALESCE(donor_name, 'Unknown'),
    COALESCE(donor_category, 'Unknown'),
    COALESCE(email, 'Unknown'),
    COALESCE(phone, 'Unknown'),
    created_at
FROM charity_resala_operational.dbo.donors

UNION ALL

SELECT
    3,
    'haya_karima',
    source_donor_id,
    donor_code,
    COALESCE(donor_name, 'Unknown'),
    COALESCE(donor_category, 'Unknown'),
    COALESCE(email, 'Unknown'),
    COALESCE(phone, 'Unknown'),
    created_at
FROM charity_haya_karima_operational.dbo.donors;
GO

CREATE OR ALTER VIEW analytics_real.v_fact_applications AS
SELECT
    1 AS organization_sk,
    'food_bank' AS organization_code,
    source_application_id AS application_id,
    source_beneficiary_id AS beneficiary_id,
    source_branch_id AS branch_id,
    application_code,
    COALESCE(support_type_name, 'Unknown') AS support_type,
    COALESCE(requested_amount, 0) AS requested_amount,
    COALESCE(application_status, 'Unknown') AS application_status,
    COALESCE(priority_level, 'Unknown') AS priority_level,
    CASE
        WHEN priority_level = 'CRITICAL' THEN 100
        WHEN priority_level = 'HIGH' THEN 80
        WHEN priority_level = 'MEDIUM' THEN 50
        WHEN priority_level = 'LOW' THEN 25
        ELSE 0
    END AS priority_score,
    submitted_at,
    reviewed_at
FROM charity_food_bank_operational.dbo.applications

UNION ALL

SELECT
    2,
    'resala',
    source_application_id,
    source_beneficiary_id,
    source_branch_id,
    application_code,
    COALESCE(support_type_name, 'Unknown'),
    COALESCE(requested_amount, 0),
    COALESCE(application_status, 'Unknown'),
    COALESCE(priority_level, 'Unknown'),
    CASE
        WHEN priority_level = 'CRITICAL' THEN 100
        WHEN priority_level = 'HIGH' THEN 80
        WHEN priority_level = 'MEDIUM' THEN 50
        WHEN priority_level = 'LOW' THEN 25
        ELSE 0
    END,
    submitted_at,
    reviewed_at
FROM charity_resala_operational.dbo.applications

UNION ALL

SELECT
    3,
    'haya_karima',
    source_application_id,
    source_beneficiary_id,
    source_branch_id,
    application_code,
    COALESCE(support_type_name, 'Unknown'),
    COALESCE(requested_amount, 0),
    COALESCE(application_status, 'Unknown'),
    COALESCE(priority_level, 'Unknown'),
    CASE
        WHEN priority_level = 'CRITICAL' THEN 100
        WHEN priority_level = 'HIGH' THEN 80
        WHEN priority_level = 'MEDIUM' THEN 50
        WHEN priority_level = 'LOW' THEN 25
        ELSE 0
    END,
    submitted_at,
    reviewed_at
FROM charity_haya_karima_operational.dbo.applications;
GO

CREATE OR ALTER VIEW analytics_real.v_fact_cases AS
SELECT
    1 AS organization_sk,
    'food_bank' AS organization_code,
    source_case_id AS case_id,
    source_application_id AS application_id,
    source_beneficiary_id AS beneficiary_id,
    source_branch_id AS branch_id,
    case_code,
    COALESCE(case_title, 'Unknown') AS case_title,
    COALESCE(support_type_name, 'Unknown') AS support_type,
    COALESCE(case_status, 'Unknown') AS case_status,
    COALESCE(target_amount, 0) AS target_amount,
    COALESCE(collected_amount, 0) AS collected_amount,
    opened_at,
    closed_at
FROM charity_food_bank_operational.dbo.cases

UNION ALL

SELECT
    2,
    'resala',
    source_case_id,
    source_application_id,
    source_beneficiary_id,
    source_branch_id,
    case_code,
    COALESCE(case_title, 'Unknown'),
    COALESCE(support_type_name, 'Unknown'),
    COALESCE(case_status, 'Unknown'),
    COALESCE(target_amount, 0),
    COALESCE(collected_amount, 0),
    opened_at,
    closed_at
FROM charity_resala_operational.dbo.cases

UNION ALL

SELECT
    3,
    'haya_karima',
    source_case_id,
    source_application_id,
    source_beneficiary_id,
    source_branch_id,
    case_code,
    COALESCE(case_title, 'Unknown'),
    COALESCE(support_type_name, 'Unknown'),
    COALESCE(case_status, 'Unknown'),
    COALESCE(target_amount, 0),
    COALESCE(collected_amount, 0),
    opened_at,
    closed_at
FROM charity_haya_karima_operational.dbo.cases;
GO

CREATE OR ALTER VIEW analytics_real.v_fact_donations AS
SELECT
    1 AS organization_sk,
    'food_bank' AS organization_code,
    source_donation_id AS donation_id,
    source_donor_id AS donor_id,
    source_case_id AS case_id,
    source_branch_id AS branch_id,
    donation_code,
    COALESCE(amount, 0) AS donation_amount,
    COALESCE(payment_method_name, 'Unknown') AS payment_method,
    COALESCE(donation_status, 'Unknown') AS donation_status,
    donated_at
FROM charity_food_bank_operational.dbo.donations

UNION ALL

SELECT
    2,
    'resala',
    source_donation_id,
    source_donor_id,
    source_case_id,
    source_branch_id,
    donation_code,
    COALESCE(amount, 0),
    COALESCE(payment_method_name, 'Unknown'),
    COALESCE(donation_status, 'Unknown'),
    donated_at
FROM charity_resala_operational.dbo.donations

UNION ALL

SELECT
    3,
    'haya_karima',
    source_donation_id,
    source_donor_id,
    source_case_id,
    source_branch_id,
    donation_code,
    COALESCE(amount, 0),
    COALESCE(payment_method_name, 'Unknown'),
    COALESCE(donation_status, 'Unknown'),
    donated_at
FROM charity_haya_karima_operational.dbo.donations;
GO

CREATE OR ALTER VIEW analytics_real.v_fact_inventory_transactions AS
SELECT
    1 AS organization_sk,
    'food_bank' AS organization_code,
    source_inventory_transaction_id AS inventory_transaction_id,
    source_branch_id AS branch_id,
    source_item_id AS item_id,
    source_case_id AS case_id,
    transaction_code,
    COALESCE(transaction_type, 'Unknown') AS transaction_type,
    COALESCE(quantity, 0) AS quantity,
    COALESCE(unit_cost, 0) AS unit_cost,
    COALESCE(quantity, 0) * COALESCE(unit_cost, 0) AS inventory_value,
    transaction_date
FROM charity_food_bank_operational.dbo.inventory_transactions

UNION ALL

SELECT
    2,
    'resala',
    source_inventory_transaction_id,
    source_branch_id,
    source_item_id,
    source_case_id,
    transaction_code,
    COALESCE(transaction_type, 'Unknown'),
    COALESCE(quantity, 0),
    COALESCE(unit_cost, 0),
    COALESCE(quantity, 0) * COALESCE(unit_cost, 0),
    transaction_date
FROM charity_resala_operational.dbo.inventory_transactions

UNION ALL

SELECT
    3,
    'haya_karima',
    source_inventory_transaction_id,
    source_branch_id,
    source_item_id,
    source_case_id,
    transaction_code,
    COALESCE(transaction_type, 'Unknown'),
    COALESCE(quantity, 0),
    COALESCE(unit_cost, 0),
    COALESCE(quantity, 0) * COALESCE(unit_cost, 0),
    transaction_date
FROM charity_haya_karima_operational.dbo.inventory_transactions;
GO

CREATE OR ALTER VIEW analytics_real.v_kpi_overview AS
SELECT
    (SELECT COUNT_BIG(*) FROM analytics_real.v_dim_organization) AS total_organizations,
    (SELECT COUNT_BIG(*) FROM analytics_real.v_dim_beneficiary) AS total_beneficiaries,
    (SELECT COUNT_BIG(*) FROM analytics_real.v_dim_donor) AS total_donors,
    (SELECT COUNT_BIG(*) FROM analytics_real.v_fact_applications) AS total_applications,
    (SELECT COUNT_BIG(*) FROM analytics_real.v_fact_cases) AS total_cases,
    (SELECT COUNT_BIG(*) FROM analytics_real.v_fact_donations) AS total_donations,
    (SELECT COUNT_BIG(*) FROM analytics_real.v_fact_inventory_transactions) AS total_inventory_transactions,
    (SELECT SUM(donation_amount) FROM analytics_real.v_fact_donations) AS total_donation_amount,
    (SELECT SUM(requested_amount) FROM analytics_real.v_fact_applications) AS total_requested_amount,
    (SELECT SUM(target_amount) FROM analytics_real.v_fact_cases) AS total_case_target_amount,
    (SELECT SUM(collected_amount) FROM analytics_real.v_fact_cases) AS total_case_collected_amount,
    (SELECT SUM(inventory_value) FROM analytics_real.v_fact_inventory_transactions) AS total_inventory_value;
GO

CREATE OR ALTER VIEW analytics_real.v_donation_summary_by_organization AS
SELECT
    organization_sk,
    organization_code,
    COUNT_BIG(*) AS donation_count,
    SUM(donation_amount) AS total_donation_amount,
    AVG(CAST(donation_amount AS DECIMAL(18,2))) AS avg_donation_amount
FROM analytics_real.v_fact_donations
GROUP BY organization_sk, organization_code;
GO

CREATE OR ALTER VIEW analytics_real.v_application_summary_by_organization AS
SELECT
    organization_sk,
    organization_code,
    COUNT_BIG(*) AS application_count,
    SUM(requested_amount) AS total_requested_amount,
    AVG(CAST(priority_score AS DECIMAL(18,2))) AS avg_priority_score
FROM analytics_real.v_fact_applications
GROUP BY organization_sk, organization_code;
GO

CREATE OR ALTER VIEW analytics_real.v_case_summary_by_organization AS
SELECT
    organization_sk,
    organization_code,
    COUNT_BIG(*) AS case_count,
    SUM(target_amount) AS total_target_amount,
    SUM(collected_amount) AS total_collected_amount,
    AVG(CAST(target_amount AS DECIMAL(18,2))) AS avg_target_amount
FROM analytics_real.v_fact_cases
GROUP BY organization_sk, organization_code;
GO

CREATE OR ALTER VIEW analytics_real.v_inventory_summary_by_organization AS
SELECT
    organization_sk,
    organization_code,
    COUNT_BIG(*) AS inventory_transaction_count,
    SUM(quantity) AS total_quantity,
    SUM(inventory_value) AS total_inventory_value
FROM analytics_real.v_fact_inventory_transactions
GROUP BY organization_sk, organization_code;
GO

PRINT 'analytics_real Power BI semantic layer created successfully.';
GO
