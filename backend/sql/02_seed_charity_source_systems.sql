USE unified_charity_platform_clean;
GO

/*
Step 2 - Smart Seed Data for 3 Charity Source Systems
Sources:
  - src_food_bank
  - src_resala
  - src_haya_karima

Purpose:
  This seed creates realistic overlapping and non-overlapping records so the
  integration pipeline can demonstrate:
  1. multi-source ingestion
  2. schema standardization
  3. beneficiary matching by national_id
  4. cross-organization duplicates
  5. support overlap / fraud signals
  6. cases, donations, and inventory activity

Safe to re-run:
  The script deletes only rows inserted into the source schemas, then reseeds.
*/

SET NOCOUNT ON;

BEGIN TRY
    BEGIN TRAN;

    /* =========================
       0) CLEAN EXISTING SOURCE SEED
       ========================= */

    IF OBJECT_ID('src_food_bank.inventory_transactions', 'U') IS NOT NULL DELETE FROM src_food_bank.inventory_transactions;
    IF OBJECT_ID('src_food_bank.donations', 'U') IS NOT NULL DELETE FROM src_food_bank.donations;
    IF OBJECT_ID('src_food_bank.cases', 'U') IS NOT NULL DELETE FROM src_food_bank.cases;
    IF OBJECT_ID('src_food_bank.applications', 'U') IS NOT NULL DELETE FROM src_food_bank.applications;
    IF OBJECT_ID('src_food_bank.beneficiaries', 'U') IS NOT NULL DELETE FROM src_food_bank.beneficiaries;

    IF OBJECT_ID('src_resala.stock_movements', 'U') IS NOT NULL DELETE FROM src_resala.stock_movements;
    IF OBJECT_ID('src_resala.donation_payments', 'U') IS NOT NULL DELETE FROM src_resala.donation_payments;
    IF OBJECT_ID('src_resala.charity_cases', 'U') IS NOT NULL DELETE FROM src_resala.charity_cases;
    IF OBJECT_ID('src_resala.support_requests', 'U') IS NOT NULL DELETE FROM src_resala.support_requests;
    IF OBJECT_ID('src_resala.beneficiary_records', 'U') IS NOT NULL DELETE FROM src_resala.beneficiary_records;

    IF OBJECT_ID('src_haya_karima.aid_stock_logs', 'U') IS NOT NULL DELETE FROM src_haya_karima.aid_stock_logs;
    IF OBJECT_ID('src_haya_karima.donor_transactions', 'U') IS NOT NULL DELETE FROM src_haya_karima.donor_transactions;
    IF OBJECT_ID('src_haya_karima.public_cases', 'U') IS NOT NULL DELETE FROM src_haya_karima.public_cases;
    IF OBJECT_ID('src_haya_karima.aid_applications', 'U') IS NOT NULL DELETE FROM src_haya_karima.aid_applications;
    IF OBJECT_ID('src_haya_karima.people', 'U') IS NOT NULL DELETE FROM src_haya_karima.people;

    /* Reseed identities for clean deterministic demo IDs */
    IF OBJECT_ID('src_food_bank.beneficiaries', 'U') IS NOT NULL DBCC CHECKIDENT ('src_food_bank.beneficiaries', RESEED, 0);
    IF OBJECT_ID('src_food_bank.applications', 'U') IS NOT NULL DBCC CHECKIDENT ('src_food_bank.applications', RESEED, 0);
    IF OBJECT_ID('src_food_bank.cases', 'U') IS NOT NULL DBCC CHECKIDENT ('src_food_bank.cases', RESEED, 0);
    IF OBJECT_ID('src_food_bank.donations', 'U') IS NOT NULL DBCC CHECKIDENT ('src_food_bank.donations', RESEED, 0);
    IF OBJECT_ID('src_food_bank.inventory_transactions', 'U') IS NOT NULL DBCC CHECKIDENT ('src_food_bank.inventory_transactions', RESEED, 0);

    IF OBJECT_ID('src_resala.beneficiary_records', 'U') IS NOT NULL DBCC CHECKIDENT ('src_resala.beneficiary_records', RESEED, 0);
    IF OBJECT_ID('src_resala.support_requests', 'U') IS NOT NULL DBCC CHECKIDENT ('src_resala.support_requests', RESEED, 0);
    IF OBJECT_ID('src_resala.charity_cases', 'U') IS NOT NULL DBCC CHECKIDENT ('src_resala.charity_cases', RESEED, 0);
    IF OBJECT_ID('src_resala.donation_payments', 'U') IS NOT NULL DBCC CHECKIDENT ('src_resala.donation_payments', RESEED, 0);
    IF OBJECT_ID('src_resala.stock_movements', 'U') IS NOT NULL DBCC CHECKIDENT ('src_resala.stock_movements', RESEED, 0);

    IF OBJECT_ID('src_haya_karima.people', 'U') IS NOT NULL DBCC CHECKIDENT ('src_haya_karima.people', RESEED, 0);
    IF OBJECT_ID('src_haya_karima.aid_applications', 'U') IS NOT NULL DBCC CHECKIDENT ('src_haya_karima.aid_applications', RESEED, 0);
    IF OBJECT_ID('src_haya_karima.public_cases', 'U') IS NOT NULL DBCC CHECKIDENT ('src_haya_karima.public_cases', RESEED, 0);
    IF OBJECT_ID('src_haya_karima.donor_transactions', 'U') IS NOT NULL DBCC CHECKIDENT ('src_haya_karima.donor_transactions', RESEED, 0);
    IF OBJECT_ID('src_haya_karima.aid_stock_logs', 'U') IS NOT NULL DBCC CHECKIDENT ('src_haya_karima.aid_stock_logs', RESEED, 0);

    /* =========================
       1) FOOD BANK SOURCE DATA
       ========================= */

    INSERT INTO src_food_bank.beneficiaries
        (beneficiary_name, national_id, mobile, city, governorate, family_members, monthly_income, created_at)
    VALUES
        (N'أحمد محمد علي',       N'2990101123456', N'01099000001', N'مدينة نصر',  N'القاهرة',      5, 1800.00, '2026-05-01T10:00:00'),
        (N'سارة محمود حسن',      N'2980202123456', N'01099000002', N'الدقي',       N'الجيزة',       4, 1200.00, '2026-05-02T11:00:00'),
        (N'محمود إبراهيم سالم',  N'2960303123456', N'01099000003', N'الإسكندرية',  N'الإسكندرية',   3, 2200.00, '2026-05-03T12:00:00'),
        (N'ليلى مصطفى عبدالعزيز',N'3000404123456', N'01099000004', N'طنطا',        N'الغربية',      6, 1500.00, '2026-05-04T09:00:00'),
        (N'فاطمة السيد عبدالله', N'2920505123456', N'01099000005', N'أسوان',       N'أسوان',        7, 900.00,  '2026-05-05T13:00:00');

    INSERT INTO src_food_bank.applications
        (national_id, application_date, support_category, requested_amount, application_status, notes)
    VALUES
        (N'2990101123456', '2026-05-04T14:24:32', N'دعم غذائي',       3000.00, N'APPROVED',     N'طلب غذائي حسب المحافظة ونوع الدعم'),
        (N'2980202123456', '2026-05-08T14:24:32', N'دعم طبي',          5000.00, N'APPROVED',     N'عملية علاجية تحتاج دعم'),
        (N'2960303123456', '2026-05-09T09:30:00', N'دعم نقدي',         1500.00, N'UNDER_REVIEW', N'مراجعة دخل الأسرة'),
        (N'3000404123456', '2026-05-10T10:15:00', N'بطاطين وملابس',    1200.00, N'REJECTED',     N'بيانات غير مكتملة'),
        (N'2920505123456', '2026-05-11T16:00:00', N'كراتين رمضان',     2200.00, N'APPROVED',     N'طلب موسمي');

    INSERT INTO src_food_bank.cases
        (national_id, case_title, support_category, target_amount, collected_amount, case_status, created_at)
    VALUES
        (N'2990101123456', N'حالة دعم غذائي لأحمد محمد',    N'دعم غذائي',     3000.00, 3000.00, N'CLOSED', '2026-05-05T14:24:32'),
        (N'2980202123456', N'حالة دعم طبي لسارة محمود',     N'دعم طبي',       5000.00, 500.00,  N'OPEN',   '2026-05-09T14:24:32'),
        (N'2920505123456', N'حالة كراتين رمضان لفاطمة',     N'كراتين رمضان',  2200.00, 800.00,  N'OPEN',   '2026-05-12T10:00:00');

    INSERT INTO src_food_bank.donations
        (national_id, donor_name, donor_mobile, amount, payment_method, donation_date)
    VALUES
        (N'2990101123456', N'فاعل خير 1', N'01011110001', 1500.00, N'محفظة إلكترونية', '2026-05-06T15:45:26'),
        (N'2990101123456', N'فاعل خير 2', N'01011110002', 1500.00, N'بطاقة بنكية',      '2026-05-07T15:45:26'),
        (N'2980202123456', N'فاعل خير 3', N'01011110003', 500.00,  N'كاش',             '2026-05-10T15:45:26'),
        (N'2920505123456', N'فاعل خير 4', N'01011110004', 800.00,  N'محفظة إلكترونية', '2026-05-13T15:45:26');

    INSERT INTO src_food_bank.inventory_transactions
        (national_id, item_name, quantity, transaction_type, transaction_date)
    VALUES
        (NULL,              N'كرتونة غذائية', 40, N'IN',  '2026-05-01T09:00:00'),
        (N'2990101123456',  N'كرتونة غذائية',  3, N'OUT', '2026-05-07T12:00:00'),
        (N'2920505123456',  N'كراتين رمضان',   2, N'OUT', '2026-05-13T12:00:00');

    /* =========================
       2) RESALA SOURCE DATA
       ========================= */

    INSERT INTO src_resala.beneficiary_records
        (full_name, nid, phone_number, area, governorate_name, household_size, income_value, inserted_on)
    VALUES
        (N'أحمد محمد علي',       N'2990101123456', N'01099000001', N'الجيزة',   N'الجيزة',      5, 1800.00, '2026-05-03T10:00:00'),
        (N'سارة محمود حسن',      N'2980202123456', N'01099000002', N'الدقي',    N'الجيزة',      4, 1200.00, '2026-05-04T10:00:00'),
        (N'خالد عبدالله كامل',   N'2950606123456', N'01099000006', N'المنصورة', N'الدقهلية',    4, 1600.00, '2026-05-05T10:00:00'),
        (N'منى عادل حسين',       N'2940707123456', N'01099000007', N'شبرا',     N'القاهرة',     3, 2500.00, '2026-05-06T10:00:00'),
        (N'فاطمة السيد عبدالله', N'2920505123456', N'01099000005', N'أسوان',    N'أسوان',       7, 900.00,  '2026-05-07T10:00:00');

    INSERT INTO src_resala.support_requests
        (nid, request_date, support_type, amount_needed, request_status, request_reason)
    VALUES
        (N'2990101123456', '2026-05-06T14:24:32', N'دعم غذائي',       2500.00, N'APPROVED',     N'نفس نوع الدعم من جمعية أخرى'),
        (N'2980202123456', '2026-05-08T14:24:32', N'دعم طبي',          4500.00, N'UNDER_REVIEW', N'مراجعة التقرير الطبي'),
        (N'2950606123456', '2026-05-11T09:30:00', N'دعم سكن',          7000.00, N'APPROVED',     N'إصلاحات عاجلة'),
        (N'2940707123456', '2026-05-12T10:15:00', N'دعم تعليمي',       1800.00, N'REJECTED',     N'غير مطابق للشروط'),
        (N'2920505123456', '2026-05-13T16:00:00', N'كراتين رمضان',     2100.00, N'APPROVED',     N'تكرار موسمي عبر جمعيات مختلفة');

    INSERT INTO src_resala.charity_cases
        (nid, title, support_type, required_money, raised_money, status, opened_at)
    VALUES
        (N'2990101123456', N'حالة دعم غذائي ثانية لنفس المستفيد', N'دعم غذائي',     2500.00, 1200.00, N'OPEN', '2026-05-07T14:24:32'),
        (N'2950606123456', N'إصلاح منزل خالد عبدالله',             N'دعم سكن',       7000.00, 7000.00, N'CLOSED', '2026-05-12T14:24:32'),
        (N'2920505123456', N'كراتين رمضان لفاطمة عبر رسالة',       N'كراتين رمضان',  2100.00, 900.00,  N'OPEN', '2026-05-14T10:00:00');

    INSERT INTO src_resala.donation_payments
        (nid, giver_name, giver_phone, paid_amount, pay_type, paid_at)
    VALUES
        (N'2990101123456', N'متبرع رسالة 1', N'01022220001', 1200.00, N'بطاقة بنكية', '2026-05-10T15:45:26'),
        (N'2950606123456', N'متبرع رسالة 2', N'01022220002', 7000.00, N'تحويل بنكي',  '2026-05-12T15:45:26'),
        (N'2920505123456', N'متبرع رسالة 3', N'01022220003', 900.00,  N'محفظة إلكترونية', '2026-05-15T15:45:26');

    INSERT INTO src_resala.stock_movements
        (nid, product_name, qty, movement_type, movement_date)
    VALUES
        (NULL,             N'بطاطين',       25, N'RECEIVED', '2026-05-01T09:00:00'),
        (N'2990101123456', N'كراتين غذائية', 2, N'ISSUED',   '2026-05-10T12:00:00'),
        (N'2920505123456', N'كراتين رمضان',  2, N'ISSUED',   '2026-05-15T12:00:00');

    /* =========================
       3) HAYA KARIMA SOURCE DATA
       ========================= */

    INSERT INTO src_haya_karima.people
        (person_name, national_code, contact_phone, district, gov, family_count, income_monthly, registration_date)
    VALUES
        (N'أحمد محمد علي',       N'2990101123456', N'01099000001', N'مدينة نصر', N'القاهرة',   5, 1800.00, '2026-05-08T10:00:00'),
        (N'فاطمة السيد عبدالله', N'2920505123456', N'01099000005', N'أسوان',     N'أسوان',     7, 900.00,  '2026-05-09T10:00:00'),
        (N'يوسف جمال عبدالرحمن', N'2930808123456', N'01099000008', N'المنيا',    N'المنيا',    4, 1700.00, '2026-05-10T10:00:00'),
        (N'نورهان سمير كمال',    N'2910909123456', N'01099000009', N'الشرقية',   N'الشرقية',   3, 2100.00, '2026-05-11T10:00:00'),
        (N'حسن علي مرسي',        N'2901010123456', N'01099000010', N'بني سويف',  N'بني سويف', 6, 1300.00, '2026-05-12T10:00:00');

    INSERT INTO src_haya_karima.aid_applications
        (national_code, submitted_at, aid_type, estimated_cost, current_status, description)
    VALUES
        (N'2990101123456', '2026-05-14T14:24:32', N'دعم نقدي',      1000.00, N'APPROVED',     N'دعم نقدي سريع من حياة كريمة'),
        (N'2920505123456', '2026-05-15T14:24:32', N'كراتين رمضان',  2000.00, N'APPROVED',     N'تكرار نفس الدعم الموسمي'),
        (N'2930808123456', '2026-05-16T09:30:00', N'دعم طبي',       3500.00, N'UNDER_REVIEW', N'تحليل مستندات طبية'),
        (N'2910909123456', '2026-05-17T10:15:00', N'دعم تعليمي',    2200.00, N'APPROVED',     N'مصاريف مدرسية'),
        (N'2901010123456', '2026-05-18T16:00:00', N'دعم غذائي',     1600.00, N'REJECTED',     N'بيانات دخل غير مؤكدة');

    INSERT INTO src_haya_karima.public_cases
        (national_code, headline, aid_type, needed_amount, received_amount, case_state, publish_date)
    VALUES
        (N'2990101123456', N'دعم نقدي عاجل لأحمد محمد',       N'دعم نقدي',     1000.00, 1000.00, N'CLOSED', '2026-05-14T16:00:00'),
        (N'2920505123456', N'كراتين رمضان لفاطمة - حياة كريمة',N'كراتين رمضان', 2000.00, 500.00,  N'OPEN',   '2026-05-15T16:00:00'),
        (N'2910909123456', N'دعم تعليمي لنورهان سمير',        N'دعم تعليمي',   2200.00, 200.00,  N'OPEN',   '2026-05-17T16:00:00');

    INSERT INTO src_haya_karima.donor_transactions
        (national_code, donor_full_name, donor_contact, donation_value, payment_channel, transaction_time)
    VALUES
        (N'2990101123456', N'متبرع حياة 1', N'01033330001', 1000.00, N'محفظة إلكترونية', '2026-05-14T17:00:00'),
        (N'2920505123456', N'متبرع حياة 2', N'01033330002', 500.00,  N'بطاقة بنكية',      '2026-05-15T17:00:00'),
        (N'2910909123456', N'متبرع حياة 3', N'01033330003', 200.00,  N'كاش',             '2026-05-18T17:00:00');

    INSERT INTO src_haya_karima.aid_stock_logs
        (national_code, aid_item, item_count, log_type, log_date)
    VALUES
        (NULL,             N'شنطة مدرسية',   30, N'IN',  '2026-05-02T09:00:00'),
        (N'2920505123456', N'كراتين رمضان',   1, N'OUT', '2026-05-15T12:00:00'),
        (N'2910909123456', N'شنطة مدرسية',    1, N'OUT', '2026-05-18T12:00:00');

    COMMIT;

    PRINT N'✅ Step 2 completed: Smart seed data inserted into 3 charity source schemas.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;

    DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @ErrLine INT = ERROR_LINE();
    RAISERROR(N'❌ Step 2 failed at line %d: %s', 16, 1, @ErrLine, @ErrMsg);
END CATCH;
GO

/* =========================
   4) VERIFICATION QUERIES
   ========================= */

SELECT 'src_food_bank.beneficiaries' AS table_name, COUNT(*) AS row_count FROM src_food_bank.beneficiaries
UNION ALL SELECT 'src_food_bank.applications', COUNT(*) FROM src_food_bank.applications
UNION ALL SELECT 'src_food_bank.cases', COUNT(*) FROM src_food_bank.cases
UNION ALL SELECT 'src_food_bank.donations', COUNT(*) FROM src_food_bank.donations
UNION ALL SELECT 'src_food_bank.inventory_transactions', COUNT(*) FROM src_food_bank.inventory_transactions
UNION ALL SELECT 'src_resala.beneficiary_records', COUNT(*) FROM src_resala.beneficiary_records
UNION ALL SELECT 'src_resala.support_requests', COUNT(*) FROM src_resala.support_requests
UNION ALL SELECT 'src_resala.charity_cases', COUNT(*) FROM src_resala.charity_cases
UNION ALL SELECT 'src_resala.donation_payments', COUNT(*) FROM src_resala.donation_payments
UNION ALL SELECT 'src_resala.stock_movements', COUNT(*) FROM src_resala.stock_movements
UNION ALL SELECT 'src_haya_karima.people', COUNT(*) FROM src_haya_karima.people
UNION ALL SELECT 'src_haya_karima.aid_applications', COUNT(*) FROM src_haya_karima.aid_applications
UNION ALL SELECT 'src_haya_karima.public_cases', COUNT(*) FROM src_haya_karima.public_cases
UNION ALL SELECT 'src_haya_karima.donor_transactions', COUNT(*) FROM src_haya_karima.donor_transactions
UNION ALL SELECT 'src_haya_karima.aid_stock_logs', COUNT(*) FROM src_haya_karima.aid_stock_logs;
GO

/* Expected integration signals:
   - Ahmed 2990101123456 exists in Food Bank + Resala + Haya Karima.
   - Fatma 2920505123456 exists in Food Bank + Resala + Haya Karima.
   - Sara 2980202123456 exists in Food Bank + Resala.
   - Some beneficiaries exist in one source only.
*/

SELECT
    national_id,
    beneficiary_name,
    source_system
FROM (
    SELECT national_id, beneficiary_name, 'FOOD_BANK' AS source_system FROM src_food_bank.beneficiaries
    UNION ALL
    SELECT nid, full_name, 'RESALA' FROM src_resala.beneficiary_records
    UNION ALL
    SELECT national_code, person_name, 'HAYA_KARIMA' FROM src_haya_karima.people
) x
ORDER BY national_id, source_system;
GO

USE unified_charity_platform_clean;
GO

SELECT 'Food Bank beneficiaries' AS table_name, COUNT(*) AS row_count
FROM src_food_bank.beneficiaries
UNION ALL
SELECT 'Resala beneficiaries', COUNT(*)
FROM src_resala.beneficiary_records
UNION ALL
SELECT 'Haya Karima beneficiaries', COUNT(*)
FROM src_haya_karima.people;

SELECT 'Food Bank applications' AS table_name, COUNT(*) AS row_count
FROM src_food_bank.applications
UNION ALL
SELECT 'Resala requests', COUNT(*)
FROM src_resala.support_requests
UNION ALL
SELECT 'Haya applications', COUNT(*)
FROM src_haya_karima.aid_applications;