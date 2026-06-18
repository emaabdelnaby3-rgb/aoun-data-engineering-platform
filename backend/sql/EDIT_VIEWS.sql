SELECT
    beneficiary_code,
    full_name,
    national_id,
    organizations_count,
    organizations_names,
    applications_count,
    cases_count,
    fraud_alerts_count,
    duplicate_candidates_count
FROM dbo.v_beneficiary_360
WHERE national_id = '2920505123456';


USE unified_charity_platform_clean;
GO

SELECT
    duplicate_candidate_id,
    rule_code,
    national_id,
    phone,
    candidate_reason,
    confidence_score,
    candidate_status,
    detected_at
FROM dbo.v_duplicate_beneficiary_candidates
ORDER BY confidence_score DESC;



USE unified_charity_platform_clean;
GO

CREATE OR ALTER VIEW dbo.v_beneficiary_360 AS
WITH orgs AS (
    SELECT
        r.beneficiary_id,
        COUNT(DISTINCT r.organization_id) AS organizations_count,
        STRING_AGG(CAST(o.organization_name_ar AS NVARCHAR(MAX)), N'، ') AS organizations_names
    FROM (
        SELECT DISTINCT beneficiary_id, organization_id
        FROM dbo.beneficiary_org_registrations
    ) r
    JOIN dbo.organizations o
        ON r.organization_id = o.organization_id
    GROUP BY r.beneficiary_id
),
apps AS (
    SELECT
        beneficiary_id,
        COUNT(*) AS applications_count,
        SUM(CASE WHEN application_status = N'APPROVED' THEN 1 ELSE 0 END) AS approved_applications_count,
        SUM(CASE WHEN application_status = N'REJECTED' THEN 1 ELSE 0 END) AS rejected_applications_count,
        MAX(submitted_at) AS last_application_at
    FROM dbo.beneficiary_applications
    GROUP BY beneficiary_id
),
cases AS (
    SELECT
        beneficiary_id,
        COUNT(*) AS cases_count,
        SUM(CASE WHEN case_status = N'OPEN' THEN 1 ELSE 0 END) AS open_cases_count,
        SUM(CASE WHEN case_status IN (N'CLOSED', N'COMPLETED') THEN 1 ELSE 0 END) AS closed_cases_count,
        ISNULL(SUM(required_amount), 0) AS total_required_amount,
        ISNULL(SUM(collected_amount), 0) AS total_collected_amount,
        MAX(created_at) AS last_case_at
    FROM dbo.charity_cases
    GROUP BY beneficiary_id
),
donations AS (
    SELECT
        cc.beneficiary_id,
        COUNT(d.donation_id) AS financial_donations_count,
        ISNULL(SUM(d.amount), 0) AS total_financial_donations_amount,
        MAX(d.created_at) AS last_donation_at
    FROM dbo.charity_cases cc
    JOIN dbo.donations d
        ON cc.case_id = d.case_id
       AND d.donation_status = N'COMPLETED'
       AND d.payment_status = N'SUCCESS'
    GROUP BY cc.beneficiary_id
),
inventory AS (
    SELECT
        cc.beneficiary_id,
        COUNT(it.transaction_id) AS inventory_support_count,
        MAX(it.transaction_date) AS last_inventory_at
    FROM dbo.charity_cases cc
    JOIN dbo.inventory_transactions it
        ON cc.case_id = it.case_id
       AND it.transaction_type = N'OUT'
    GROUP BY cc.beneficiary_id
),
fraud AS (
    SELECT
        beneficiary_id,
        COUNT(*) AS fraud_alerts_count,
        MAX(created_at) AS last_fraud_at
    FROM dbo.fraud_alerts
    WHERE alert_status = N'OPEN'
    GROUP BY beneficiary_id
),
dups AS (
    SELECT
        primary_beneficiary_id AS beneficiary_id,
        COUNT(*) AS duplicate_candidates_count,
        MAX(detected_at) AS last_duplicate_at
    FROM dbo.duplicate_candidates
    WHERE candidate_status = N'OPEN'
    GROUP BY primary_beneficiary_id
)
SELECT
    b.beneficiary_id,
    b.beneficiary_code,
    b.national_id,
    b.full_name,
    b.phone,
    b.email,
    g.governorate_name_ar AS governorate,
    c.city_name_ar AS city,
    b.family_size,
    b.monthly_income,

    ISNULL(orgs.organizations_count, 0) AS organizations_count,
    ISNULL(orgs.organizations_names, N'لا يوجد') AS organizations_names,

    ISNULL(apps.applications_count, 0) AS applications_count,
    ISNULL(apps.approved_applications_count, 0) AS approved_applications_count,
    ISNULL(apps.rejected_applications_count, 0) AS rejected_applications_count,

    ISNULL(cases.cases_count, 0) AS cases_count,
    ISNULL(cases.open_cases_count, 0) AS open_cases_count,
    ISNULL(cases.closed_cases_count, 0) AS closed_cases_count,
    ISNULL(cases.total_required_amount, 0) AS total_required_amount,
    ISNULL(cases.total_collected_amount, 0) AS total_collected_amount,

    ISNULL(donations.financial_donations_count, 0) AS financial_donations_count,
    ISNULL(donations.total_financial_donations_amount, 0) AS total_financial_donations_amount,
    ISNULL(inventory.inventory_support_count, 0) AS inventory_support_count,

    ISNULL(fraud.fraud_alerts_count, 0) AS fraud_alerts_count,
    ISNULL(dups.duplicate_candidates_count, 0) AS duplicate_candidates_count,

    (
        SELECT MAX(v)
        FROM (VALUES
            (b.created_at),
            (apps.last_application_at),
            (cases.last_case_at),
            (donations.last_donation_at),
            (inventory.last_inventory_at),
            (fraud.last_fraud_at),
            (dups.last_duplicate_at)
        ) AS all_dates(v)
    ) AS last_activity_date
FROM dbo.beneficiary_profiles b
LEFT JOIN dbo.governorates g ON b.governorate_id = g.governorate_id
LEFT JOIN dbo.cities c ON b.city_id = c.city_id
LEFT JOIN orgs ON b.beneficiary_id = orgs.beneficiary_id
LEFT JOIN apps ON b.beneficiary_id = apps.beneficiary_id
LEFT JOIN cases ON b.beneficiary_id = cases.beneficiary_id
LEFT JOIN donations ON b.beneficiary_id = donations.beneficiary_id
LEFT JOIN inventory ON b.beneficiary_id = inventory.beneficiary_id
LEFT JOIN fraud ON b.beneficiary_id = fraud.beneficiary_id
LEFT JOIN dups ON b.beneficiary_id = dups.beneficiary_id;
GO

SELECT
    full_name,
    national_id,
    organizations_count,
    organizations_names,
    last_activity_date
FROM dbo.v_beneficiary_360
WHERE organizations_count > 1;



SELECT
    beneficiary_code,
    full_name,
    national_id,
    organizations_count,
    organizations_names,
    applications_count,
    cases_count,
    fraud_alerts_count
FROM dbo.v_beneficiary_360



USE unified_charity_platform_clean;
GO

SELECT
    d.donation_id,
    d.donation_code,
    d.donor_name,
    d.donor_phone,
    d.donor_email,
    d.amount,
    d.currency,
    d.donation_target_type,
    d.donation_status,
    d.payment_status,
    d.campaign_name,
    d.general_notes,
    d.created_at,

    c.case_code,
    c.case_title,

    o.organization_name_ar,

    pm.method_name_ar AS payment_method

FROM dbo.donations d
LEFT JOIN dbo.charity_cases c
    ON d.case_id = c.case_id
LEFT JOIN dbo.organizations o
    ON d.organization_id = o.organization_id
LEFT JOIN dbo.payment_methods pm
    ON d.payment_method_id = pm.payment_method_id
WHERE d.donation_code = 'DON-0120';