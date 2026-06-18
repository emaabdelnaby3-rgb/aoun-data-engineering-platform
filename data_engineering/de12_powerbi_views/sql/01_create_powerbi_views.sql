USE charity_dwh;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'gold')
BEGIN
    EXEC('CREATE SCHEMA gold');
END;
GO

CREATE OR ALTER VIEW gold.vw_government_overview AS
WITH beneficiary_counts AS (
    SELECT organization_sk, COUNT(*) AS total_beneficiaries
    FROM gold.dim_beneficiary
    GROUP BY organization_sk
),
donor_counts AS (
    SELECT organization_sk, COUNT(*) AS total_donors
    FROM gold.dim_donor
    GROUP BY organization_sk
),
application_counts AS (
    SELECT
        organization_sk,
        COUNT(*) AS total_applications,
        SUM(CASE WHEN LOWER(ISNULL(application_status, '')) LIKE '%approved%' OR application_status IN ('APPROVED', 'Approved', N'مقبول') THEN 1 ELSE 0 END) AS approved_applications,
        SUM(CASE WHEN LOWER(ISNULL(application_status, '')) LIKE '%rejected%' OR application_status IN ('REJECTED', 'Rejected', N'مرفوض') THEN 1 ELSE 0 END) AS rejected_applications,
        SUM(CASE WHEN LOWER(ISNULL(application_status, '')) LIKE '%pending%' OR application_status IN ('PENDING', 'Pending', N'قيد المراجعة') THEN 1 ELSE 0 END) AS pending_applications,
        AVG(TRY_CONVERT(float, priority_score)) AS avg_application_priority
    FROM gold.fact_applications
    GROUP BY organization_sk
),
case_counts AS (
    SELECT
        organization_sk,
        COUNT(*) AS total_cases,
        SUM(TRY_CONVERT(float, target_amount)) AS total_target_amount,
        SUM(TRY_CONVERT(float, collected_amount)) AS total_collected_amount,
        AVG(TRY_CONVERT(float, priority_score)) AS avg_case_priority
    FROM gold.fact_cases
    GROUP BY organization_sk
),
donation_counts AS (
    SELECT
        organization_sk,
        COUNT(*) AS total_donations,
        SUM(TRY_CONVERT(float, donation_amount)) AS total_donation_amount,
        AVG(TRY_CONVERT(float, donation_amount)) AS avg_donation_amount
    FROM gold.fact_donations
    GROUP BY organization_sk
),
inventory_counts AS (
    SELECT
        organization_sk,
        COUNT(*) AS total_inventory_transactions,
        SUM(TRY_CONVERT(float, quantity)) AS total_inventory_quantity
    FROM gold.fact_inventory_transactions
    GROUP BY organization_sk
)
SELECT
    o.organization_sk,
    o.source_org,
    o.organization_name,
    ISNULL(b.total_beneficiaries, 0) AS total_beneficiaries,
    ISNULL(dc.total_donors, 0) AS total_donors,
    ISNULL(a.total_applications, 0) AS total_applications,
    ISNULL(a.approved_applications, 0) AS approved_applications,
    ISNULL(a.rejected_applications, 0) AS rejected_applications,
    ISNULL(a.pending_applications, 0) AS pending_applications,
    ISNULL(c.total_cases, 0) AS total_cases,
    ISNULL(d.total_donations, 0) AS total_donations,
    ISNULL(d.total_donation_amount, 0) AS total_donation_amount,
    ISNULL(c.total_target_amount, 0) AS total_case_target_amount,
    ISNULL(c.total_collected_amount, 0) AS total_case_collected_amount,
    CASE 
        WHEN ISNULL(c.total_target_amount, 0) = 0 THEN 0
        ELSE ROUND((ISNULL(c.total_collected_amount, 0) / NULLIF(c.total_target_amount, 0)) * 100, 2)
    END AS case_funding_percentage,
    ISNULL(i.total_inventory_transactions, 0) AS total_inventory_transactions,
    ISNULL(i.total_inventory_quantity, 0) AS total_inventory_quantity,
    a.avg_application_priority,
    c.avg_case_priority,
    GETDATE() AS view_refreshed_at
FROM gold.dim_organization o
LEFT JOIN beneficiary_counts b ON o.organization_sk = b.organization_sk
LEFT JOIN donor_counts dc ON o.organization_sk = dc.organization_sk
LEFT JOIN application_counts a ON o.organization_sk = a.organization_sk
LEFT JOIN case_counts c ON o.organization_sk = c.organization_sk
LEFT JOIN donation_counts d ON o.organization_sk = d.organization_sk
LEFT JOIN inventory_counts i ON o.organization_sk = i.organization_sk;
GO

CREATE OR ALTER VIEW gold.vw_organization_performance AS
SELECT
    o.organization_name,
    a.source_org,
    a.application_status,
    a.support_type,
    COUNT(*) AS applications_count,
    AVG(TRY_CONVERT(float, a.priority_score)) AS avg_priority_score,
    MIN(a.application_date_raw) AS first_application_date_raw,
    MAX(a.application_date_raw) AS latest_application_date_raw
FROM gold.fact_applications a
LEFT JOIN gold.dim_organization o ON a.organization_sk = o.organization_sk
GROUP BY
    o.organization_name,
    a.source_org,
    a.application_status,
    a.support_type;
GO

CREATE OR ALTER VIEW gold.vw_case_funding_analysis AS
WITH donations_by_case AS (
    SELECT
        case_sk,
        COUNT(*) AS donations_count,
        SUM(TRY_CONVERT(float, donation_amount)) AS donation_amount_from_fact
    FROM gold.fact_donations
    GROUP BY case_sk
)
SELECT
    c.case_sk,
    c.case_nk,
    o.organization_name,
    c.source_org,
    b.beneficiary_name,
    b.governorate,
    b.city,
    c.case_status,
    c.case_category,
    TRY_CONVERT(float, c.target_amount) AS target_amount,
    TRY_CONVERT(float, c.collected_amount) AS collected_amount_from_case,
    ISNULL(d.donation_amount_from_fact, 0) AS donation_amount_from_fact,
    ISNULL(d.donations_count, 0) AS donations_count,
    CASE
        WHEN TRY_CONVERT(float, c.target_amount) IS NULL OR TRY_CONVERT(float, c.target_amount) = 0 THEN 0
        ELSE ROUND((TRY_CONVERT(float, c.collected_amount) / NULLIF(TRY_CONVERT(float, c.target_amount), 0)) * 100, 2)
    END AS funding_percentage,
    CASE
        WHEN TRY_CONVERT(float, c.collected_amount) >= TRY_CONVERT(float, c.target_amount)
             AND TRY_CONVERT(float, c.target_amount) > 0
        THEN 1 ELSE 0
    END AS is_fully_funded,
    TRY_CONVERT(float, c.priority_score) AS priority_score,
    c.case_date_raw,
    c.kafka_timestamp,
    c.gold_processed_at
FROM gold.fact_cases c
LEFT JOIN gold.dim_organization o ON c.organization_sk = o.organization_sk
LEFT JOIN gold.dim_beneficiary b ON c.beneficiary_sk = b.beneficiary_sk
LEFT JOIN donations_by_case d ON c.case_sk = d.case_sk;
GO

CREATE OR ALTER VIEW gold.vw_donation_analysis AS
SELECT
    d.donation_sk,
    d.donation_nk,
    o.organization_name,
    d.source_org,
    donor.donor_name,
    donor.donor_type,
    donor.governorate AS donor_governorate,
    donor.city AS donor_city,
    d.case_nk,
    TRY_CONVERT(float, d.donation_amount) AS donation_amount,
    d.payment_method,
    d.payment_status,
    d.donation_date_raw,
    d.kafka_timestamp,
    d.gold_processed_at
FROM gold.fact_donations d
LEFT JOIN gold.dim_organization o ON d.organization_sk = o.organization_sk
LEFT JOIN gold.dim_donor donor ON d.donor_sk = donor.donor_sk;
GO

CREATE OR ALTER VIEW gold.vw_inventory_support_analysis AS
SELECT
    i.inventory_transaction_sk,
    i.transaction_nk,
    o.organization_name,
    i.source_org,
    b.beneficiary_name,
    b.governorate,
    b.city,
    i.item_nk,
    i.transaction_type,
    TRY_CONVERT(float, i.quantity) AS quantity,
    i.transaction_date_raw,
    i.kafka_timestamp,
    i.gold_processed_at
FROM gold.fact_inventory_transactions i
LEFT JOIN gold.dim_organization o ON i.organization_sk = o.organization_sk
LEFT JOIN gold.dim_beneficiary b ON i.beneficiary_sk = b.beneficiary_sk;
GO

CREATE OR ALTER VIEW gold.vw_beneficiary_360 AS
WITH app_summary AS (
    SELECT
        beneficiary_sk,
        COUNT(*) AS total_applications,
        AVG(TRY_CONVERT(float, priority_score)) AS avg_application_priority
    FROM gold.fact_applications
    GROUP BY beneficiary_sk
),
case_summary AS (
    SELECT
        beneficiary_sk,
        COUNT(*) AS total_cases,
        SUM(TRY_CONVERT(float, target_amount)) AS total_case_target_amount,
        SUM(TRY_CONVERT(float, collected_amount)) AS total_case_collected_amount,
        AVG(TRY_CONVERT(float, priority_score)) AS avg_case_priority
    FROM gold.fact_cases
    GROUP BY beneficiary_sk
),
donation_summary AS (
    SELECT
        c.beneficiary_sk,
        COUNT(d.donation_sk) AS total_related_donations,
        SUM(TRY_CONVERT(float, d.donation_amount)) AS total_related_donation_amount
    FROM gold.fact_cases c
    LEFT JOIN gold.fact_donations d ON c.case_sk = d.case_sk
    GROUP BY c.beneficiary_sk
),
inventory_summary AS (
    SELECT
        beneficiary_sk,
        COUNT(*) AS total_inventory_support_transactions,
        SUM(TRY_CONVERT(float, quantity)) AS total_inventory_quantity
    FROM gold.fact_inventory_transactions
    GROUP BY beneficiary_sk
)
SELECT
    b.beneficiary_sk,
    b.beneficiary_nk,
    o.organization_name,
    b.source_org,
    b.beneficiary_name,
    b.gender,
    b.governorate,
    b.city,
    b.marital_status,
    b.employment_status,
    TRY_CONVERT(float, b.monthly_income) AS monthly_income,
    TRY_CONVERT(int, b.family_members) AS family_members,
    b.has_disability,
    b.has_chronic_disease,
    ISNULL(a.total_applications, 0) AS total_applications,
    ISNULL(c.total_cases, 0) AS total_cases,
    ISNULL(ds.total_related_donations, 0) AS total_related_donations,
    ISNULL(ds.total_related_donation_amount, 0) AS total_related_donation_amount,
    ISNULL(c.total_case_target_amount, 0) AS total_case_target_amount,
    ISNULL(c.total_case_collected_amount, 0) AS total_case_collected_amount,
    ISNULL(inv.total_inventory_support_transactions, 0) AS total_inventory_support_transactions,
    ISNULL(inv.total_inventory_quantity, 0) AS total_inventory_quantity,
    a.avg_application_priority,
    c.avg_case_priority,
    b.gold_processed_at
FROM gold.dim_beneficiary b
LEFT JOIN gold.dim_organization o ON b.organization_sk = o.organization_sk
LEFT JOIN app_summary a ON b.beneficiary_sk = a.beneficiary_sk
LEFT JOIN case_summary c ON b.beneficiary_sk = c.beneficiary_sk
LEFT JOIN donation_summary ds ON b.beneficiary_sk = ds.beneficiary_sk
LEFT JOIN inventory_summary inv ON b.beneficiary_sk = inv.beneficiary_sk;
GO
