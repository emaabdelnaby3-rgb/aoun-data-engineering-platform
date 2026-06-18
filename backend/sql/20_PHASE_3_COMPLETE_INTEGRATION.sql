/*
================================================================================
PHASE 3 COMPLETE INTEGRATION - Presentation Ready
================================================================================
Run this file on database: master
It finishes the operational DB + donor/beneficiary/admin/government views +
helper stored procedures used by the Phase 3 frontend/backend.

Safe behavior:
- Does NOT drop unified_charity_platform_clean.
- Does NOT delete operational data.
- Recreates only views/procedures and adds missing columns/tables.
================================================================================
*/

USE unified_charity_platform_clean;
GO

/* -----------------------------------------------------------------------------
   1) Make sure Phase 2/3 business columns exist
----------------------------------------------------------------------------- */
IF COL_LENGTH('dbo.beneficiary_applications', 'children_count') IS NULL
    ALTER TABLE dbo.beneficiary_applications ADD children_count INT NULL;
GO
IF COL_LENGTH('dbo.beneficiary_applications', 'has_chronic_disease') IS NULL
    ALTER TABLE dbo.beneficiary_applications ADD has_chronic_disease BIT NOT NULL CONSTRAINT df_p3_app_has_chronic_disease DEFAULT 0;
GO
IF COL_LENGTH('dbo.beneficiary_applications', 'has_disability') IS NULL
    ALTER TABLE dbo.beneficiary_applications ADD has_disability BIT NOT NULL CONSTRAINT df_p3_app_has_disability DEFAULT 0;
GO
IF COL_LENGTH('dbo.beneficiary_applications', 'is_widow_or_single_mother') IS NULL
    ALTER TABLE dbo.beneficiary_applications ADD is_widow_or_single_mother BIT NOT NULL CONSTRAINT df_p3_app_widow DEFAULT 0;
GO
IF COL_LENGTH('dbo.beneficiary_applications', 'rent_amount') IS NULL
    ALTER TABLE dbo.beneficiary_applications ADD rent_amount DECIMAL(18,2) NULL;
GO
IF COL_LENGTH('dbo.beneficiary_applications', 'emergency_level') IS NULL
    ALTER TABLE dbo.beneficiary_applications ADD emergency_level NVARCHAR(50) NULL;
GO
IF COL_LENGTH('dbo.beneficiary_applications', 'monthly_support_limit') IS NULL
    ALTER TABLE dbo.beneficiary_applications ADD monthly_support_limit DECIMAL(18,2) NULL;
GO
IF COL_LENGTH('dbo.beneficiary_applications', 'public_case_description') IS NULL
    ALTER TABLE dbo.beneficiary_applications ADD public_case_description NVARCHAR(2000) NULL;
GO
IF COL_LENGTH('dbo.beneficiary_applications', 'internal_review_notes') IS NULL
    ALTER TABLE dbo.beneficiary_applications ADD internal_review_notes NVARCHAR(2000) NULL;
GO

IF COL_LENGTH('dbo.charity_cases', 'is_public') IS NULL
    ALTER TABLE dbo.charity_cases ADD is_public BIT NOT NULL CONSTRAINT df_p3_cases_is_public DEFAULT 1;
GO
IF COL_LENGTH('dbo.charity_cases', 'is_monthly_case') IS NULL
    ALTER TABLE dbo.charity_cases ADD is_monthly_case BIT NOT NULL CONSTRAINT df_p3_cases_monthly DEFAULT 0;
GO
IF COL_LENGTH('dbo.charity_cases', 'eligibility_status') IS NULL
    ALTER TABLE dbo.charity_cases ADD eligibility_status NVARCHAR(50) NOT NULL CONSTRAINT df_p3_cases_elig DEFAULT N'ELIGIBLE';
GO
IF COL_LENGTH('dbo.charity_cases', 'donation_enabled') IS NULL
    ALTER TABLE dbo.charity_cases ADD donation_enabled BIT NOT NULL CONSTRAINT df_p3_cases_donation_enabled DEFAULT 1;
GO
IF COL_LENGTH('dbo.charity_cases', 'public_display_name') IS NULL
    ALTER TABLE dbo.charity_cases ADD public_display_name NVARCHAR(200) NULL;
GO
IF COL_LENGTH('dbo.charity_cases', 'documents_verified') IS NULL
    ALTER TABLE dbo.charity_cases ADD documents_verified BIT NOT NULL CONSTRAINT df_p3_cases_docs_verified DEFAULT 0;
GO

UPDATE dbo.charity_cases
SET is_public = 1,
    donation_enabled = CASE WHEN collected_amount >= required_amount THEN 0 ELSE 1 END,
    eligibility_status = CASE WHEN collected_amount >= required_amount THEN N'NOT_ELIGIBLE_THIS_MONTH' ELSE N'ELIGIBLE' END,
    published_at = COALESCE(published_at, created_at, SYSUTCDATETIME())
WHERE is_public IS NULL OR published_at IS NULL OR eligibility_status IS NULL;
GO

/* -----------------------------------------------------------------------------
   2) Tables used by donor/admin support workflow
----------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.donor_favorites', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.donor_favorites (
        favorite_id BIGINT IDENTITY(1,1) PRIMARY KEY,
        donor_user_id INT NULL,
        donor_phone NVARCHAR(30) NULL,
        case_id INT NOT NULL,
        created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        is_active BIT NOT NULL DEFAULT 1,
        CONSTRAINT fk_p3_donor_favorites_users FOREIGN KEY (donor_user_id) REFERENCES dbo.platform_users(user_id),
        CONSTRAINT fk_p3_donor_favorites_cases FOREIGN KEY (case_id) REFERENCES dbo.charity_cases(case_id)
    );
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_p3_donor_favorites_case_phone' AND object_id = OBJECT_ID('dbo.donor_favorites'))
    CREATE INDEX ix_p3_donor_favorites_case_phone ON dbo.donor_favorites(case_id, donor_phone, is_active);
GO

IF OBJECT_ID('dbo.case_priority_scores', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.case_priority_scores (
        score_id BIGINT IDENTITY(1,1) PRIMARY KEY,
        application_id INT NULL,
        case_id INT NULL,
        beneficiary_id INT NOT NULL,
        organization_id INT NOT NULL,
        priority_score INT NOT NULL,
        priority_level NVARCHAR(50) NOT NULL,
        scoring_details NVARCHAR(MAX) NULL,
        calculated_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        calculated_by NVARCHAR(100) NOT NULL DEFAULT N'PHASE_3_RULE_ENGINE',
        CONSTRAINT fk_p3_priority_app FOREIGN KEY (application_id) REFERENCES dbo.beneficiary_applications(application_id),
        CONSTRAINT fk_p3_priority_case FOREIGN KEY (case_id) REFERENCES dbo.charity_cases(case_id),
        CONSTRAINT fk_p3_priority_ben FOREIGN KEY (beneficiary_id) REFERENCES dbo.beneficiary_profiles(beneficiary_id),
        CONSTRAINT fk_p3_priority_org FOREIGN KEY (organization_id) REFERENCES dbo.organizations(organization_id)
    );
END;
GO

IF OBJECT_ID('dbo.eligibility_checks', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.eligibility_checks (
        eligibility_check_id BIGINT IDENTITY(1,1) PRIMARY KEY,
        beneficiary_id INT NOT NULL,
        application_id INT NULL,
        case_id INT NULL,
        organization_id INT NULL,
        check_month CHAR(7) NOT NULL,
        eligibility_status NVARCHAR(50) NOT NULL,
        amount_received_this_month DECIMAL(18,2) NOT NULL DEFAULT 0,
        support_count_this_month INT NOT NULL DEFAULT 0,
        reason NVARCHAR(1000) NULL,
        checked_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT fk_p3_elig_ben FOREIGN KEY (beneficiary_id) REFERENCES dbo.beneficiary_profiles(beneficiary_id),
        CONSTRAINT fk_p3_elig_app FOREIGN KEY (application_id) REFERENCES dbo.beneficiary_applications(application_id),
        CONSTRAINT fk_p3_elig_case FOREIGN KEY (case_id) REFERENCES dbo.charity_cases(case_id),
        CONSTRAINT fk_p3_elig_org FOREIGN KEY (organization_id) REFERENCES dbo.organizations(organization_id)
    );
END;
GO

IF OBJECT_ID('dbo.support_disbursements', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.support_disbursements (
        support_disbursement_id BIGINT IDENTITY(1,1) PRIMARY KEY,
        support_code NVARCHAR(50) NOT NULL UNIQUE,
        beneficiary_id INT NOT NULL,
        organization_id INT NOT NULL,
        branch_id INT NULL,
        application_id INT NULL,
        case_id INT NULL,
        support_type_id INT NOT NULL,
        support_month CHAR(7) NOT NULL,
        support_source NVARCHAR(50) NOT NULL,
        amount_value DECIMAL(18,2) NOT NULL DEFAULT 0,
        item_description NVARCHAR(300) NULL,
        quantity DECIMAL(18,2) NULL,
        disbursement_status NVARCHAR(50) NOT NULL DEFAULT N'COMPLETED',
        disbursed_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        notes NVARCHAR(1000) NULL,
        CONSTRAINT fk_p3_support_ben FOREIGN KEY (beneficiary_id) REFERENCES dbo.beneficiary_profiles(beneficiary_id),
        CONSTRAINT fk_p3_support_org FOREIGN KEY (organization_id) REFERENCES dbo.organizations(organization_id),
        CONSTRAINT fk_p3_support_branch FOREIGN KEY (branch_id) REFERENCES dbo.branches(branch_id),
        CONSTRAINT fk_p3_support_app FOREIGN KEY (application_id) REFERENCES dbo.beneficiary_applications(application_id),
        CONSTRAINT fk_p3_support_case FOREIGN KEY (case_id) REFERENCES dbo.charity_cases(case_id),
        CONSTRAINT fk_p3_support_type FOREIGN KEY (support_type_id) REFERENCES dbo.support_types(support_type_id)
    );
END;
GO

IF OBJECT_ID('dbo.application_status_history', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.application_status_history (
        status_history_id BIGINT IDENTITY(1,1) PRIMARY KEY,
        application_id INT NOT NULL,
        old_status NVARCHAR(50) NULL,
        new_status NVARCHAR(50) NOT NULL,
        changed_by_user_id INT NULL,
        change_reason NVARCHAR(1000) NULL,
        changed_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT fk_p3_status_app FOREIGN KEY (application_id) REFERENCES dbo.beneficiary_applications(application_id),
        CONSTRAINT fk_p3_status_user FOREIGN KEY (changed_by_user_id) REFERENCES dbo.platform_users(user_id)
    );
END;
GO

IF OBJECT_ID('dbo.admin_reviews', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.admin_reviews (
        review_id BIGINT IDENTITY(1,1) PRIMARY KEY,
        application_id INT NULL,
        case_id INT NULL,
        beneficiary_id INT NOT NULL,
        organization_id INT NOT NULL,
        reviewer_user_id INT NULL,
        review_action NVARCHAR(50) NOT NULL,
        review_notes NVARCHAR(1000) NULL,
        created_case_id INT NULL,
        reviewed_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT fk_p3_reviews_app FOREIGN KEY (application_id) REFERENCES dbo.beneficiary_applications(application_id),
        CONSTRAINT fk_p3_reviews_case FOREIGN KEY (case_id) REFERENCES dbo.charity_cases(case_id),
        CONSTRAINT fk_p3_reviews_ben FOREIGN KEY (beneficiary_id) REFERENCES dbo.beneficiary_profiles(beneficiary_id),
        CONSTRAINT fk_p3_reviews_org FOREIGN KEY (organization_id) REFERENCES dbo.organizations(organization_id),
        CONSTRAINT fk_p3_reviews_user FOREIGN KEY (reviewer_user_id) REFERENCES dbo.platform_users(user_id)
    );
END;
GO

/* -----------------------------------------------------------------------------
   3) Seed missing demo users for full presentation flow
----------------------------------------------------------------------------- */
DECLARE @roleCharity INT = (SELECT role_id FROM dbo.roles WHERE role_code = 'CHARITY_ADMIN');
DECLARE @roleDonor INT = (SELECT role_id FROM dbo.roles WHERE role_code = 'DONOR');
DECLARE @orgHaya INT = (SELECT organization_id FROM dbo.organizations WHERE organization_code IN ('ORG-HAYA', 'HAYA_KARIMA'));
DECLARE @brHaya INT = (SELECT TOP 1 branch_id FROM dbo.branches WHERE organization_id = @orgHaya ORDER BY branch_id);

IF @roleCharity IS NOT NULL AND @orgHaya IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.platform_users WHERE email = 'haya.admin@test.com')
BEGIN
    INSERT INTO dbo.platform_users (user_code, role_id, organization_id, branch_id, full_name, phone, email, password_hash)
    VALUES ('USR-HAYA-ADMIN', @roleCharity, @orgHaya, @brHaya, N'أدمن حياة كريمة', '01030000004', 'haya.admin@test.com', 'demo_hash');
END;

IF @roleDonor IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.platform_users WHERE email = 'donor@test.com')
BEGIN
    INSERT INTO dbo.platform_users (user_code, role_id, organization_id, branch_id, full_name, phone, email, password_hash)
    VALUES ('USR-DONOR-001', @roleDonor, NULL, NULL, N'متبرع تجريبي', '01077000001', 'donor@test.com', 'demo_hash');
END;
GO

/* -----------------------------------------------------------------------------
   4) Priority + eligibility stored procedures
----------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_phase3_recalculate_priority
    @application_id INT = NULL,
    @case_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @beneficiary_id INT,
        @organization_id INT,
        @family_size INT,
        @children_count INT,
        @monthly_income DECIMAL(18,2),
        @has_chronic_disease BIT,
        @has_disability BIT,
        @is_widow_or_single_mother BIT,
        @rent_amount DECIMAL(18,2),
        @emergency_level NVARCHAR(50),
        @support_count INT = 0,
        @high_fraud_count INT = 0,
        @score INT = 0,
        @level NVARCHAR(50),
        @details NVARCHAR(MAX);

    IF @application_id IS NOT NULL
    BEGIN
        SELECT TOP 1
            @beneficiary_id = ba.beneficiary_id,
            @organization_id = ba.organization_id,
            @family_size = bp.family_size,
            @children_count = ba.children_count,
            @monthly_income = bp.monthly_income,
            @has_chronic_disease = ba.has_chronic_disease,
            @has_disability = ba.has_disability,
            @is_widow_or_single_mother = ba.is_widow_or_single_mother,
            @rent_amount = ba.rent_amount,
            @emergency_level = ba.emergency_level
        FROM dbo.beneficiary_applications ba
        JOIN dbo.beneficiary_profiles bp ON bp.beneficiary_id = ba.beneficiary_id
        WHERE ba.application_id = @application_id;
    END
    ELSE IF @case_id IS NOT NULL
    BEGIN
        SELECT TOP 1
            @application_id = c.application_id,
            @beneficiary_id = c.beneficiary_id,
            @organization_id = c.organization_id,
            @family_size = bp.family_size,
            @children_count = ba.children_count,
            @monthly_income = bp.monthly_income,
            @has_chronic_disease = ba.has_chronic_disease,
            @has_disability = ba.has_disability,
            @is_widow_or_single_mother = ba.is_widow_or_single_mother,
            @rent_amount = ba.rent_amount,
            @emergency_level = ba.emergency_level
        FROM dbo.charity_cases c
        JOIN dbo.beneficiary_profiles bp ON bp.beneficiary_id = c.beneficiary_id
        LEFT JOIN dbo.beneficiary_applications ba ON ba.application_id = c.application_id
        WHERE c.case_id = @case_id;
    END

    IF @beneficiary_id IS NULL RETURN;

    SELECT @support_count = COUNT(*)
    FROM dbo.support_disbursements
    WHERE beneficiary_id = @beneficiary_id
      AND support_month = CONVERT(CHAR(7), SYSUTCDATETIME(), 120)
      AND disbursement_status = N'COMPLETED';

    SELECT @high_fraud_count = COUNT(*)
    FROM dbo.fraud_alerts
    WHERE beneficiary_id = @beneficiary_id
      AND severity IN (N'HIGH', N'CRITICAL')
      AND alert_status IN (N'OPEN', N'UNDER_REVIEW');

    IF ISNULL(@family_size, 0) >= 5 SET @score += 5;
    IF ISNULL(@children_count, 0) > 3 SET @score += 5;
    IF ISNULL(@monthly_income, 999999) <= 1500 SET @score += 8;
    IF ISNULL(@monthly_income, 999999) <= 800 SET @score += 5;
    IF ISNULL(@has_chronic_disease, 0) = 1 SET @score += 10;
    IF ISNULL(@has_disability, 0) = 1 SET @score += 10;
    IF ISNULL(@is_widow_or_single_mother, 0) = 1 SET @score += 8;
    IF ISNULL(@rent_amount, 0) >= 1500 SET @score += 5;
    IF UPPER(ISNULL(@emergency_level, N'')) IN (N'HIGH', N'CRITICAL') SET @score += 15;
    IF UPPER(ISNULL(@emergency_level, N'')) = N'MEDIUM' SET @score += 7;
    IF @support_count > 0 SET @score -= 10;
    IF @high_fraud_count > 0 SET @score -= 30;
    IF @score < 0 SET @score = 0;

    SET @level = CASE WHEN @score >= 61 THEN N'CRITICAL' WHEN @score >= 41 THEN N'HIGH' WHEN @score >= 21 THEN N'MEDIUM' ELSE N'LOW' END;
    SET @details = CONCAT(N'{"score":', @score, N',"level":"', @level, N'","support_count":', @support_count, N',"high_fraud_count":', @high_fraud_count, N'}');

    INSERT INTO dbo.case_priority_scores (application_id, case_id, beneficiary_id, organization_id, priority_score, priority_level, scoring_details)
    VALUES (@application_id, @case_id, @beneficiary_id, @organization_id, @score, @level, @details);

    IF @application_id IS NOT NULL
        UPDATE dbo.beneficiary_applications SET priority_level = @level WHERE application_id = @application_id;

    IF @case_id IS NOT NULL
        UPDATE dbo.charity_cases SET priority_level = @level WHERE case_id = @case_id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_phase3_record_eligibility
    @beneficiary_id INT,
    @application_id INT = NULL,
    @case_id INT = NULL,
    @organization_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @month CHAR(7) = CONVERT(CHAR(7), SYSUTCDATETIME(), 120);
    DECLARE @support_count INT = 0, @amount DECIMAL(18,2) = 0, @fraud_count INT = 0;
    DECLARE @status NVARCHAR(50), @reason NVARCHAR(1000);

    SELECT @support_count = COUNT(*), @amount = COALESCE(SUM(amount_value), 0)
    FROM dbo.support_disbursements
    WHERE beneficiary_id = @beneficiary_id AND support_month = @month AND disbursement_status = N'COMPLETED';

    SELECT @fraud_count = COUNT(*)
    FROM dbo.fraud_alerts
    WHERE beneficiary_id = @beneficiary_id
      AND severity IN (N'HIGH', N'CRITICAL')
      AND alert_status IN (N'OPEN', N'UNDER_REVIEW');

    IF @fraud_count > 0
    BEGIN
        SET @status = N'MANUAL_REVIEW';
        SET @reason = N'يوجد تنبيه احتيال عالي/حرج ويحتاج مراجعة يدوية.';
    END
    ELSE IF @support_count > 0
    BEGIN
        SET @status = N'NOT_ELIGIBLE_THIS_MONTH';
        SET @reason = N'حصل على دعم هذا الشهر.';
    END
    ELSE
    BEGIN
        SET @status = N'ELIGIBLE';
        SET @reason = N'لم يحصل على دعم هذا الشهر.';
    END

    INSERT INTO dbo.eligibility_checks (beneficiary_id, application_id, case_id, organization_id, check_month, eligibility_status, amount_received_this_month, support_count_this_month, reason)
    VALUES (@beneficiary_id, @application_id, @case_id, @organization_id, @month, @status, @amount, @support_count, @reason);
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_phase3_close_case_if_funded
    @case_id INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @beneficiary_id INT, @organization_id INT, @branch_id INT, @application_id INT, @support_type_id INT;
    DECLARE @required DECIMAL(18,2), @collected DECIMAL(18,2), @month CHAR(7), @support_code NVARCHAR(50);

    SELECT @beneficiary_id = beneficiary_id, @organization_id = organization_id, @branch_id = branch_id,
           @application_id = application_id, @support_type_id = support_type_id,
           @required = required_amount, @collected = collected_amount
    FROM dbo.charity_cases
    WHERE case_id = @case_id;

    IF @case_id IS NULL OR @required IS NULL OR @collected < @required RETURN;

    SET @month = CONVERT(CHAR(7), SYSUTCDATETIME(), 120);

    UPDATE dbo.charity_cases
    SET case_status = N'CLOSED',
        donation_enabled = 0,
        eligibility_status = N'NOT_ELIGIBLE_THIS_MONTH',
        closed_at = COALESCE(closed_at, SYSUTCDATETIME())
    WHERE case_id = @case_id;

    IF NOT EXISTS (SELECT 1 FROM dbo.support_disbursements WHERE case_id = @case_id AND support_month = @month AND support_source = N'DONATION')
    BEGIN
        SELECT @support_code = CONCAT('SUP-', RIGHT(CONCAT('00000', ISNULL(MAX(TRY_CONVERT(INT, RIGHT(support_code, 5))), 0) + 1), 5))
        FROM dbo.support_disbursements
        WHERE support_code LIKE 'SUP-%';

        INSERT INTO dbo.support_disbursements
        (support_code, beneficiary_id, organization_id, branch_id, application_id, case_id, support_type_id, support_month, support_source, amount_value, item_description, notes)
        VALUES (@support_code, @beneficiary_id, @organization_id, @branch_id, @application_id, @case_id, @support_type_id, @month, N'DONATION', @collected, N'دعم مالي مكتمل من المتبرعين', N'تم تسجيله تلقائياً عند اكتمال مبلغ الحالة.');
    END

    EXEC dbo.sp_phase3_record_eligibility @beneficiary_id = @beneficiary_id, @application_id = @application_id, @case_id = @case_id, @organization_id = @organization_id;
END;
GO

/* -----------------------------------------------------------------------------
   5) Correct donor-safe and support-profile views
----------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.v_public_donor_cases AS
SELECT
    c.case_id,
    c.case_code,
    c.organization_id,
    o.organization_name_ar,
    c.support_type_id,
    st.support_name_ar AS support_type_name_ar,
    c.case_title,
    c.case_description,
    COALESCE(c.public_display_name, CONCAT(N'مستفيد رقم ', bp.beneficiary_id)) AS public_display_name,
    g.governorate_name_ar,
    c.required_amount,
    c.collected_amount,
    CASE WHEN c.required_amount - c.collected_amount < 0 THEN 0 ELSE c.required_amount - c.collected_amount END AS remaining_amount,
    c.case_status,
    c.priority_level,
    COALESCE(ps.priority_score, 0) AS priority_score,
    c.is_monthly_case,
    c.documents_verified,
    CASE
        WHEN c.case_status IN (N'CLOSED', N'FUNDED') OR c.collected_amount >= c.required_amount THEN N'غير مستحق هذا الشهر'
        WHEN c.eligibility_status <> N'ELIGIBLE' THEN N'غير مستحق هذا الشهر'
        ELSE N'مستحق'
    END AS eligibility_label_ar,
    CASE
        WHEN c.donation_enabled = 1
         AND c.is_public = 1
         AND c.case_status IN (N'OPEN', N'PUBLISHED')
         AND c.collected_amount < c.required_amount
         AND c.eligibility_status = N'ELIGIBLE'
        THEN CAST(1 AS BIT)
        ELSE CAST(0 AS BIT)
    END AS can_donate,
    c.published_at,
    c.created_at
FROM dbo.charity_cases c
JOIN dbo.beneficiary_profiles bp ON bp.beneficiary_id = c.beneficiary_id
LEFT JOIN dbo.organizations o ON o.organization_id = c.organization_id
LEFT JOIN dbo.support_types st ON st.support_type_id = c.support_type_id
LEFT JOIN dbo.governorates g ON g.governorate_id = bp.governorate_id
OUTER APPLY (
    SELECT TOP 1 priority_score
    FROM dbo.case_priority_scores ps
    WHERE ps.case_id = c.case_id OR ps.application_id = c.application_id
    ORDER BY ps.calculated_at DESC
) ps
WHERE c.is_public = 1;
GO

CREATE OR ALTER VIEW dbo.v_beneficiary_support_profiles AS
WITH current_month AS (
    SELECT CONVERT(CHAR(7), SYSUTCDATETIME(), 120) AS support_month
), monthly_support AS (
    SELECT
        sd.beneficiary_id,
        sd.support_month,
        COUNT(*) AS support_count_this_month,
        SUM(sd.amount_value) AS amount_received_this_month,
        STRING_AGG(CONCAT(o.organization_name_ar, N': ', st.support_name_ar, N' - ', FORMAT(sd.amount_value, 'N0'), N' جنيه'), N' | ') AS support_summary_ar
    FROM dbo.support_disbursements sd
    JOIN dbo.organizations o ON o.organization_id = sd.organization_id
    LEFT JOIN dbo.support_types st ON st.support_type_id = sd.support_type_id
    GROUP BY sd.beneficiary_id, sd.support_month
), active_apps AS (
    SELECT beneficiary_id, COUNT(*) AS active_applications
    FROM dbo.beneficiary_applications
    WHERE application_status IN (N'SUBMITTED', N'ASSIGNED', N'UNDER_REVIEW', N'APPROVED', N'قيد المراجعة', N'مقبول')
    GROUP BY beneficiary_id
), active_cases AS (
    SELECT beneficiary_id, COUNT(*) AS active_cases
    FROM dbo.charity_cases
    WHERE case_status IN (N'OPEN', N'PUBLISHED', N'مفتوحة', N'منشورة')
    GROUP BY beneficiary_id
), fraud AS (
    SELECT
        beneficiary_id,
        COUNT(*) AS fraud_alert_count,
        MAX(CASE severity WHEN N'CRITICAL' THEN 4 WHEN N'HIGH' THEN 3 WHEN N'MEDIUM' THEN 2 WHEN N'LOW' THEN 1 ELSE 0 END) AS max_fraud_level_num
    FROM dbo.fraud_alerts
    WHERE alert_status IN (N'OPEN', N'UNDER_REVIEW', N'مفتوح', N'قيد المراجعة')
    GROUP BY beneficiary_id
)
SELECT
    bp.beneficiary_id,
    bp.beneficiary_code,
    bp.national_id,
    bp.full_name,
    bp.phone,
    bp.family_size,
    bp.monthly_income,
    g.governorate_name_ar,
    ci.city_name_ar,
    cm.support_month AS current_month,
    CASE WHEN COALESCE(ms.support_count_this_month, 0) > 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS received_support_this_month,
    COALESCE(ms.support_count_this_month, 0) AS support_count_this_month,
    COALESCE(ms.amount_received_this_month, 0) AS amount_received_this_month,
    COALESCE(ms.support_summary_ar, N'لم يحصل على دعم هذا الشهر') AS support_summary_ar,
    COALESCE(aa.active_applications, 0) AS active_applications,
    COALESCE(ac.active_cases, 0) AS active_cases,
    COALESCE(fr.fraud_alert_count, 0) AS fraud_alert_count,
    CASE fr.max_fraud_level_num WHEN 4 THEN N'CRITICAL' WHEN 3 THEN N'HIGH' WHEN 2 THEN N'MEDIUM' WHEN 1 THEN N'LOW' ELSE N'NONE' END AS fraud_level,
    CASE
        WHEN COALESCE(fr.max_fraud_level_num, 0) >= 3 THEN N'مراجعة يدوية بسبب تنبيهات احتيال'
        WHEN COALESCE(ms.support_count_this_month, 0) > 0 THEN N'غير مستحق هذا الشهر'
        ELSE N'مستحق هذا الشهر'
    END AS monthly_eligibility_label_ar,
    CASE
        WHEN COALESCE(fr.max_fraud_level_num, 0) >= 3 THEN N'MANUAL_REVIEW'
        WHEN COALESCE(ms.support_count_this_month, 0) > 0 THEN N'NOT_ELIGIBLE_THIS_MONTH'
        ELSE N'ELIGIBLE'
    END AS monthly_eligibility_status
FROM dbo.beneficiary_profiles bp
CROSS JOIN current_month cm
LEFT JOIN monthly_support ms ON ms.beneficiary_id = bp.beneficiary_id AND ms.support_month = cm.support_month
LEFT JOIN active_apps aa ON aa.beneficiary_id = bp.beneficiary_id
LEFT JOIN active_cases ac ON ac.beneficiary_id = bp.beneficiary_id
LEFT JOIN fraud fr ON fr.beneficiary_id = bp.beneficiary_id
LEFT JOIN dbo.governorates g ON g.governorate_id = bp.governorate_id
LEFT JOIN dbo.cities ci ON ci.city_id = bp.city_id;
GO

/* -----------------------------------------------------------------------------
   6) Initial recalculation for existing rows
----------------------------------------------------------------------------- */
DECLARE @app_id INT;
DECLARE app_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT application_id FROM dbo.beneficiary_applications;
OPEN app_cursor;
FETCH NEXT FROM app_cursor INTO @app_id;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC dbo.sp_phase3_recalculate_priority @application_id = @app_id;
    FETCH NEXT FROM app_cursor INTO @app_id;
END
CLOSE app_cursor;
DEALLOCATE app_cursor;
GO

DECLARE @case_id INT;
DECLARE case_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT case_id FROM dbo.charity_cases;
OPEN case_cursor;
FETCH NEXT FROM case_cursor INTO @case_id;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC dbo.sp_phase3_recalculate_priority @case_id = @case_id;
    EXEC dbo.sp_phase3_close_case_if_funded @case_id = @case_id;
    FETCH NEXT FROM case_cursor INTO @case_id;
END
CLOSE case_cursor;
DEALLOCATE case_cursor;
GO

PRINT N'PHASE 3 COMPLETE INTEGRATION is ready.';
GO
