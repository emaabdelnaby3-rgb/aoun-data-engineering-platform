USE master;
GO

DECLARE @checks TABLE (
    check_name NVARCHAR(200),
    status NVARCHAR(20),
    details NVARCHAR(1000)
);

INSERT INTO @checks
SELECT 'database unified_charity_platform_clean', CASE WHEN DB_ID('unified_charity_platform_clean') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END, NULL;
INSERT INTO @checks
SELECT 'database charity_dwh', CASE WHEN DB_ID('charity_dwh') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END, NULL;

IF DB_ID('unified_charity_platform_clean') IS NOT NULL
BEGIN
    INSERT INTO @checks
    SELECT 'unified phase3 tables', CASE WHEN COUNT(*) = 13 THEN 'PASS' ELSE 'FAIL' END, CONCAT('found=', COUNT(*), '/13')
    FROM unified_charity_platform_clean.INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME IN (
        'organizations','branches','platform_users','beneficiary_profiles','beneficiary_applications','charity_cases',
        'beneficiary_documents','donations','donor_favorites','support_disbursements','case_priority_scores','eligibility_checks','fraud_alerts'
    );

    INSERT INTO @checks
    SELECT 'public donor cases view compiles', CASE WHEN OBJECT_ID('unified_charity_platform_clean.dbo.v_public_donor_cases') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END, NULL;

    INSERT INTO @checks
    SELECT 'support profiles view compiles', CASE WHEN OBJECT_ID('unified_charity_platform_clean.dbo.v_beneficiary_support_profiles') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END, NULL;

    INSERT INTO @checks
    SELECT 'phase3 procedures exist', CASE WHEN COUNT(*) = 3 THEN 'PASS' ELSE 'FAIL' END, CONCAT('found=', COUNT(*), '/3')
    FROM unified_charity_platform_clean.sys.objects
    WHERE type = 'P' AND name IN ('sp_phase3_recalculate_priority','sp_phase3_record_eligibility','sp_phase3_close_case_if_funded');

    INSERT INTO @checks
    SELECT 'cases visible to donors', CASE WHEN COUNT(*) >= 1 THEN 'PASS' ELSE 'WARN' END, CONCAT('rows=', COUNT(*))
    FROM unified_charity_platform_clean.dbo.v_public_donor_cases;

    INSERT INTO @checks
    SELECT 'support profiles rows', CASE WHEN COUNT(*) >= 1 THEN 'PASS' ELSE 'WARN' END, CONCAT('rows=', COUNT(*))
    FROM unified_charity_platform_clean.dbo.v_beneficiary_support_profiles;
END

IF DB_ID('charity_dwh') IS NOT NULL
BEGIN
    INSERT INTO @checks
    SELECT 'dwh core tables', CASE WHEN COUNT(*) = 4 THEN 'PASS' ELSE 'FAIL' END, CONCAT('found=', COUNT(*), '/4')
    FROM charity_dwh.INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME IN ('dim_time','dim_organization','fact_applications','fact_donations');

    INSERT INTO @checks
    SELECT 'dwh powerbi views', CASE WHEN COUNT(*) = 2 THEN 'PASS' ELSE 'FAIL' END, CONCAT('found=', COUNT(*), '/2')
    FROM charity_dwh.INFORMATION_SCHEMA.VIEWS
    WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME IN ('v_powerbi_government_overview','v_powerbi_donations_overview');

    INSERT INTO @checks SELECT 'dwh fact_applications rows', CASE WHEN COUNT(*) >= 1 THEN 'PASS' ELSE 'WARN' END, CONCAT('rows=', COUNT(*)) FROM charity_dwh.dbo.fact_applications;
    INSERT INTO @checks SELECT 'dwh fact_donations rows', CASE WHEN COUNT(*) >= 1 THEN 'PASS' ELSE 'WARN' END, CONCAT('rows=', COUNT(*)) FROM charity_dwh.dbo.fact_donations;
END

SELECT status, COUNT(*) AS checks_count FROM @checks GROUP BY status ORDER BY status;
SELECT * FROM @checks ORDER BY CASE status WHEN 'FAIL' THEN 1 WHEN 'WARN' THEN 2 ELSE 3 END, check_name;
GO
