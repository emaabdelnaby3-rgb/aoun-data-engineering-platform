/*
DE-1 verification script
Run on: master
Purpose: confirm synthetic data exists in all 3 operational source databases.
*/
SET NOCOUNT ON;
GO

DECLARE @results TABLE (
    source_db SYSNAME,
    table_name SYSNAME,
    rows_count BIGINT
);

INSERT INTO @results
EXEC('USE charity_food_bank_operational;
SELECT DB_NAME(), ''branches'', COUNT(*) FROM dbo.branches UNION ALL
SELECT DB_NAME(), ''staff_users'', COUNT(*) FROM dbo.staff_users UNION ALL
SELECT DB_NAME(), ''beneficiaries'', COUNT(*) FROM dbo.beneficiaries UNION ALL
SELECT DB_NAME(), ''applications'', COUNT(*) FROM dbo.applications UNION ALL
SELECT DB_NAME(), ''cases'', COUNT(*) FROM dbo.cases UNION ALL
SELECT DB_NAME(), ''donors'', COUNT(*) FROM dbo.donors UNION ALL
SELECT DB_NAME(), ''donations'', COUNT(*) FROM dbo.donations UNION ALL
SELECT DB_NAME(), ''inventory_items'', COUNT(*) FROM dbo.inventory_items UNION ALL
SELECT DB_NAME(), ''inventory_transactions'', COUNT(*) FROM dbo.inventory_transactions UNION ALL
SELECT DB_NAME(), ''beneficiary_documents'', COUNT(*) FROM dbo.beneficiary_documents UNION ALL
SELECT DB_NAME(), ''source_event_outbox'', COUNT(*) FROM dbo.source_event_outbox;');

INSERT INTO @results
EXEC('USE charity_resala_operational;
SELECT DB_NAME(), ''branches'', COUNT(*) FROM dbo.branches UNION ALL
SELECT DB_NAME(), ''staff_users'', COUNT(*) FROM dbo.staff_users UNION ALL
SELECT DB_NAME(), ''beneficiaries'', COUNT(*) FROM dbo.beneficiaries UNION ALL
SELECT DB_NAME(), ''applications'', COUNT(*) FROM dbo.applications UNION ALL
SELECT DB_NAME(), ''cases'', COUNT(*) FROM dbo.cases UNION ALL
SELECT DB_NAME(), ''donors'', COUNT(*) FROM dbo.donors UNION ALL
SELECT DB_NAME(), ''donations'', COUNT(*) FROM dbo.donations UNION ALL
SELECT DB_NAME(), ''inventory_items'', COUNT(*) FROM dbo.inventory_items UNION ALL
SELECT DB_NAME(), ''inventory_transactions'', COUNT(*) FROM dbo.inventory_transactions UNION ALL
SELECT DB_NAME(), ''beneficiary_documents'', COUNT(*) FROM dbo.beneficiary_documents UNION ALL
SELECT DB_NAME(), ''source_event_outbox'', COUNT(*) FROM dbo.source_event_outbox;');

INSERT INTO @results
EXEC('USE charity_haya_karima_operational;
SELECT DB_NAME(), ''branches'', COUNT(*) FROM dbo.branches UNION ALL
SELECT DB_NAME(), ''staff_users'', COUNT(*) FROM dbo.staff_users UNION ALL
SELECT DB_NAME(), ''beneficiaries'', COUNT(*) FROM dbo.beneficiaries UNION ALL
SELECT DB_NAME(), ''applications'', COUNT(*) FROM dbo.applications UNION ALL
SELECT DB_NAME(), ''cases'', COUNT(*) FROM dbo.cases UNION ALL
SELECT DB_NAME(), ''donors'', COUNT(*) FROM dbo.donors UNION ALL
SELECT DB_NAME(), ''donations'', COUNT(*) FROM dbo.donations UNION ALL
SELECT DB_NAME(), ''inventory_items'', COUNT(*) FROM dbo.inventory_items UNION ALL
SELECT DB_NAME(), ''inventory_transactions'', COUNT(*) FROM dbo.inventory_transactions UNION ALL
SELECT DB_NAME(), ''beneficiary_documents'', COUNT(*) FROM dbo.beneficiary_documents UNION ALL
SELECT DB_NAME(), ''source_event_outbox'', COUNT(*) FROM dbo.source_event_outbox;');

SELECT *
FROM @results
ORDER BY source_db, table_name;

SELECT
    CASE WHEN SUM(CASE WHEN rows_count = 0 AND table_name NOT IN ('cases','inventory_transactions') THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'WARN' END AS de1_status,
    SUM(rows_count) AS total_source_rows
FROM @results;
GO

/* Cross-organization duplicate national IDs for Beneficiary 360 / Fraud scenarios */
WITH all_beneficiaries AS (
    SELECT 'FOOD_BANK' AS source_system, national_id FROM charity_food_bank_operational.dbo.beneficiaries
    UNION ALL
    SELECT 'RESALA', national_id FROM charity_resala_operational.dbo.beneficiaries
    UNION ALL
    SELECT 'HAYA_KARIMA', national_id FROM charity_haya_karima_operational.dbo.beneficiaries
)
SELECT TOP 20
    national_id,
    COUNT(DISTINCT source_system) AS organizations_count,
    COUNT(*) AS duplicated_rows
FROM all_beneficiaries
WHERE LEN(national_id) = 14
GROUP BY national_id
HAVING COUNT(DISTINCT source_system) > 1
ORDER BY organizations_count DESC, duplicated_rows DESC;
GO
