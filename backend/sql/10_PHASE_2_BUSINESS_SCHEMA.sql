/* ============================================================
   PHASE 2 - Arabic Charity Platform Business Schema
   Run after: 00_ALL_IN_ONE_unified_charity_platform_clean.sql

   Adds real DB support for:
   - Beneficiary application business fields
   - Case priority scoring
   - Monthly eligibility tracking
   - Support received this month profiles
   - Donor favorites
   - Admin reviews + status history
   - Public donor case view
   - Charity/Government support profile views
   ============================================================ */

USE unified_charity_platform_clean;
GO

/* ------------------------------------------------------------
   1) Add Phase 2 business columns to beneficiary_applications
   ------------------------------------------------------------ */
IF COL_LENGTH('dbo.beneficiary_applications', 'children_count') IS NULL
    ALTER TABLE dbo.beneficiary_applications ADD children_count INT NULL;
GO
IF COL_LENGTH('dbo.beneficiary_applications', 'has_chronic_disease') IS NULL
    ALTER TABLE dbo.beneficiary_applications ADD has_chronic_disease BIT NOT NULL CONSTRAINT df_app_has_chronic_disease DEFAULT 0;
GO
IF COL_LENGTH('dbo.beneficiary_applications', 'has_disability') IS NULL
    ALTER TABLE dbo.beneficiary_applications ADD has_disability BIT NOT NULL CONSTRAINT df_app_has_disability DEFAULT 0;
GO
IF COL_LENGTH('dbo.beneficiary_applications', 'is_widow_or_single_mother') IS NULL
    ALTER TABLE dbo.beneficiary_applications ADD is_widow_or_single_mother BIT NOT NULL CONSTRAINT df_app_is_widow_or_single_mother DEFAULT 0;
GO
IF COL_LENGTH('dbo.beneficiary_applications', 'rent_amount') IS NULL
    ALTER TABLE dbo.beneficiary_applications ADD rent_amount DECIMAL(18,2) NULL;
GO
IF COL_LENGTH('dbo.beneficiary_applications', 'emergency_level') IS NULL
    ALTER TABLE dbo.beneficiary_applications ADD emergency_level NVARCHAR(30) NULL;
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

/* ------------------------------------------------------------
   2) Add public donor-safe fields to charity_cases
   ------------------------------------------------------------ */
IF COL_LENGTH('dbo.charity_cases', 'is_public') IS NULL
    ALTER TABLE dbo.charity_cases ADD is_public BIT NOT NULL CONSTRAINT df_cases_is_public DEFAULT 1;
GO
IF COL_LENGTH('dbo.charity_cases', 'is_monthly_case') IS NULL
    ALTER TABLE dbo.charity_cases ADD is_monthly_case BIT NOT NULL CONSTRAINT df_cases_is_monthly_case DEFAULT 0;
GO
IF COL_LENGTH('dbo.charity_cases', 'eligibility_status') IS NULL
    ALTER TABLE dbo.charity_cases ADD eligibility_status NVARCHAR(50) NOT NULL CONSTRAINT df_cases_eligibility_status DEFAULT N'ELIGIBLE';
GO
IF COL_LENGTH('dbo.charity_cases', 'donation_enabled') IS NULL
    ALTER TABLE dbo.charity_cases ADD donation_enabled BIT NOT NULL CONSTRAINT df_cases_donation_enabled DEFAULT 1;
GO
IF COL_LENGTH('dbo.charity_cases', 'public_display_name') IS NULL
    ALTER TABLE dbo.charity_cases ADD public_display_name NVARCHAR(200) NULL;
GO
IF COL_LENGTH('dbo.charity_cases', 'documents_verified') IS NULL
    ALTER TABLE dbo.charity_cases ADD documents_verified BIT NOT NULL CONSTRAINT df_cases_documents_verified DEFAULT 0;
GO

/* ------------------------------------------------------------
   3) Donor profile + favorites
   ------------------------------------------------------------ */
IF OBJECT_ID('dbo.donor_profiles', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.donor_profiles (
        donor_id INT IDENTITY(1,1) PRIMARY KEY,
        user_id INT NULL UNIQUE,
        donor_code NVARCHAR(50) NOT NULL UNIQUE,
        full_name NVARCHAR(200) NOT NULL,
        phone NVARCHAR(30) NULL,
        email NVARCHAR(150) NULL,
        preferred_governorate_id INT NULL,
        is_active BIT NOT NULL DEFAULT 1,
        created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT fk_donor_profiles_users
            FOREIGN KEY (user_id) REFERENCES dbo.platform_users(user_id),
        CONSTRAINT fk_donor_profiles_governorates
            FOREIGN KEY (preferred_governorate_id) REFERENCES dbo.governorates(governorate_id)
    );
END;
GO

IF OBJECT_ID('dbo.donor_favorites', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.donor_favorites (
        favorite_id BIGINT IDENTITY(1,1) PRIMARY KEY,
        donor_user_id INT NULL,
        donor_phone NVARCHAR(30) NULL,
        case_id INT NOT NULL,
        created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        is_active BIT NOT NULL DEFAULT 1,
        CONSTRAINT fk_donor_favorites_users
            FOREIGN KEY (donor_user_id) REFERENCES dbo.platform_users(user_id),
        CONSTRAINT fk_donor_favorites_cases
            FOREIGN KEY (case_id) REFERENCES dbo.charity_cases(case_id)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_donor_favorites_case' AND object_id = OBJECT_ID('dbo.donor_favorites'))
    CREATE INDEX ix_donor_favorites_case ON dbo.donor_favorites(case_id, is_active);
GO

/* ------------------------------------------------------------
   4) Priority scoring + eligibility + support received
   ------------------------------------------------------------ */
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
        calculated_by NVARCHAR(100) NOT NULL DEFAULT N'PHASE_2_RULE_ENGINE',
        CONSTRAINT fk_priority_applications
            FOREIGN KEY (application_id) REFERENCES dbo.beneficiary_applications(application_id),
        CONSTRAINT fk_priority_cases
            FOREIGN KEY (case_id) REFERENCES dbo.charity_cases(case_id),
        CONSTRAINT fk_priority_beneficiaries
            FOREIGN KEY (beneficiary_id) REFERENCES dbo.beneficiary_profiles(beneficiary_id),
        CONSTRAINT fk_priority_organizations
            FOREIGN KEY (organization_id) REFERENCES dbo.organizations(organization_id)
    );
END;
GO

IF OBJECT_ID('dbo.monthly_support_limits', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.monthly_support_limits (
        limit_id INT IDENTITY(1,1) PRIMARY KEY,
        support_type_id INT NOT NULL,
        governorate_id INT NULL,
        max_monthly_amount DECIMAL(18,2) NOT NULL,
        max_monthly_times INT NOT NULL DEFAULT 1,
        is_active BIT NOT NULL DEFAULT 1,
        created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT fk_monthly_limits_support_types
            FOREIGN KEY (support_type_id) REFERENCES dbo.support_types(support_type_id),
        CONSTRAINT fk_monthly_limits_governorates
            FOREIGN KEY (governorate_id) REFERENCES dbo.governorates(governorate_id)
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
        check_month CHAR(7) NOT NULL, -- YYYY-MM
        eligibility_status NVARCHAR(50) NOT NULL, -- ELIGIBLE / NOT_ELIGIBLE_THIS_MONTH / MANUAL_REVIEW
        amount_received_this_month DECIMAL(18,2) NOT NULL DEFAULT 0,
        support_count_this_month INT NOT NULL DEFAULT 0,
        reason NVARCHAR(1000) NULL,
        checked_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT fk_eligibility_beneficiaries
            FOREIGN KEY (beneficiary_id) REFERENCES dbo.beneficiary_profiles(beneficiary_id),
        CONSTRAINT fk_eligibility_applications
            FOREIGN KEY (application_id) REFERENCES dbo.beneficiary_applications(application_id),
        CONSTRAINT fk_eligibility_cases
            FOREIGN KEY (case_id) REFERENCES dbo.charity_cases(case_id),
        CONSTRAINT fk_eligibility_organizations
            FOREIGN KEY (organization_id) REFERENCES dbo.organizations(organization_id)
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
        support_month CHAR(7) NOT NULL, -- YYYY-MM
        support_source NVARCHAR(50) NOT NULL, -- DONATION / INVENTORY / MANUAL
        amount_value DECIMAL(18,2) NOT NULL DEFAULT 0,
        item_description NVARCHAR(300) NULL,
        quantity DECIMAL(18,2) NULL,
        disbursement_status NVARCHAR(50) NOT NULL DEFAULT N'COMPLETED',
        disbursed_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        notes NVARCHAR(1000) NULL,
        CONSTRAINT fk_support_disbursements_beneficiaries
            FOREIGN KEY (beneficiary_id) REFERENCES dbo.beneficiary_profiles(beneficiary_id),
        CONSTRAINT fk_support_disbursements_organizations
            FOREIGN KEY (organization_id) REFERENCES dbo.organizations(organization_id),
        CONSTRAINT fk_support_disbursements_branches
            FOREIGN KEY (branch_id) REFERENCES dbo.branches(branch_id),
        CONSTRAINT fk_support_disbursements_applications
            FOREIGN KEY (application_id) REFERENCES dbo.beneficiary_applications(application_id),
        CONSTRAINT fk_support_disbursements_cases
            FOREIGN KEY (case_id) REFERENCES dbo.charity_cases(case_id),
        CONSTRAINT fk_support_disbursements_support_types
            FOREIGN KEY (support_type_id) REFERENCES dbo.support_types(support_type_id)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_support_disbursements_month_ben' AND object_id = OBJECT_ID('dbo.support_disbursements'))
    CREATE INDEX ix_support_disbursements_month_ben ON dbo.support_disbursements(support_month, beneficiary_id, organization_id);
GO

/* ------------------------------------------------------------
   5) Admin workflow history
   ------------------------------------------------------------ */
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
        CONSTRAINT fk_status_history_applications
            FOREIGN KEY (application_id) REFERENCES dbo.beneficiary_applications(application_id),
        CONSTRAINT fk_status_history_users
            FOREIGN KEY (changed_by_user_id) REFERENCES dbo.platform_users(user_id)
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
        review_notes NVARCHAR(2000) NULL,
        created_case_id INT NULL,
        reviewed_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT fk_admin_reviews_applications
            FOREIGN KEY (application_id) REFERENCES dbo.beneficiary_applications(application_id),
        CONSTRAINT fk_admin_reviews_cases
            FOREIGN KEY (case_id) REFERENCES dbo.charity_cases(case_id),
        CONSTRAINT fk_admin_reviews_created_cases
            FOREIGN KEY (created_case_id) REFERENCES dbo.charity_cases(case_id),
        CONSTRAINT fk_admin_reviews_beneficiaries
            FOREIGN KEY (beneficiary_id) REFERENCES dbo.beneficiary_profiles(beneficiary_id),
        CONSTRAINT fk_admin_reviews_organizations
            FOREIGN KEY (organization_id) REFERENCES dbo.organizations(organization_id),
        CONSTRAINT fk_admin_reviews_users
            FOREIGN KEY (reviewer_user_id) REFERENCES dbo.platform_users(user_id)
    );
END;
GO

/* ------------------------------------------------------------
   6) Priority scoring function
   ------------------------------------------------------------ */
CREATE OR ALTER FUNCTION dbo.fn_phase2_priority_level (@score INT)
RETURNS NVARCHAR(50)
AS
BEGIN
    RETURN (
        CASE
            WHEN @score >= 61 THEN N'CRITICAL'
            WHEN @score >= 41 THEN N'HIGH'
            WHEN @score >= 21 THEN N'MEDIUM'
            ELSE N'LOW'
        END
    );
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_phase2_calculate_priority_score
(
    @family_size INT,
    @children_count INT,
    @monthly_income DECIMAL(18,2),
    @has_chronic_disease BIT,
    @has_disability BIT,
    @is_widow_or_single_mother BIT,
    @rent_amount DECIMAL(18,2),
    @emergency_level NVARCHAR(30),
    @support_count_this_month INT,
    @fraud_high_or_critical_count INT
)
RETURNS INT
AS
BEGIN
    DECLARE @score INT = 0;

    IF ISNULL(@family_size, 0) >= 5 SET @score += 5;
    IF ISNULL(@children_count, 0) > 3 SET @score += 5;
    IF ISNULL(@monthly_income, 999999) <= 1500 SET @score += 8;
    IF ISNULL(@monthly_income, 999999) <= 800 SET @score += 5;
    IF ISNULL(@has_chronic_disease, 0) = 1 SET @score += 10;
    IF ISNULL(@has_disability, 0) = 1 SET @score += 10;
    IF ISNULL(@is_widow_or_single_mother, 0) = 1 SET @score += 8;
    IF ISNULL(@rent_amount, 0) >= 1500 SET @score += 5;
    IF UPPER(ISNULL(@emergency_level, '')) IN ('HIGH', 'CRITICAL', N'عالي', N'حرج') SET @score += 15;
    IF UPPER(ISNULL(@emergency_level, '')) IN ('MEDIUM', N'متوسط') SET @score += 7;
    IF ISNULL(@support_count_this_month, 0) > 0 SET @score -= 10;
    IF ISNULL(@fraud_high_or_critical_count, 0) > 0 SET @score -= 30;

    IF @score < 0 SET @score = 0;
    RETURN @score;
END;
GO

/* ------------------------------------------------------------
   7) Donor-safe public cases view
   ------------------------------------------------------------ */
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
    COALESCE(ps.priority_score,
        dbo.fn_phase2_calculate_priority_score(
            bp.family_size,
            ba.children_count,
            bp.monthly_income,
            ba.has_chronic_disease,
            ba.has_disability,
            ba.is_widow_or_single_mother,
            ba.rent_amount,
            ba.emergency_level,
            0,
            0
        )
    ) AS priority_score,
    c.is_monthly_case,
    c.documents_verified,
    CASE
        WHEN c.case_status IN (N'CLOSED', N'FUNDED') OR c.collected_amount >= c.required_amount
            THEN N'غير مستحق هذا الشهر'
        WHEN c.eligibility_status <> N'ELIGIBLE'
            THEN N'غير مستحق هذا الشهر'
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
LEFT JOIN dbo.beneficiary_applications ba ON ba.application_id = c.application_id
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

/* ------------------------------------------------------------
   8) Admin/Government support profiles view
   ------------------------------------------------------------ */
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
    JOIN dbo.support_types st ON st.support_type_id = sd.support_type_id
    GROUP BY sd.beneficiary_id, sd.support_month
), active_apps AS (
    SELECT beneficiary_id, COUNT(*) AS active_applications
    FROM dbo.beneficiary_applications
    WHERE application_status IN (N'SUBMITTED', N'ASSIGNED', N'UNDER_REVIEW', N'APPROVED')
    GROUP BY beneficiary_id
), active_cases AS (
    SELECT beneficiary_id, COUNT(*) AS active_cases
    FROM dbo.charity_cases
    WHERE case_status IN (N'OPEN', N'PUBLISHED')
    GROUP BY beneficiary_id
), fraud AS (
    SELECT
        beneficiary_id,
        COUNT(*) AS fraud_alert_count,
        MAX(CASE severity WHEN N'CRITICAL' THEN 4 WHEN N'HIGH' THEN 3 WHEN N'MEDIUM' THEN 2 ELSE 1 END) AS max_fraud_level_num
    FROM dbo.fraud_alerts
    WHERE alert_status IN (N'OPEN', N'UNDER_REVIEW')
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
    c.city_name_ar,
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
LEFT JOIN dbo.cities c ON c.city_id = bp.city_id;
GO

/* ------------------------------------------------------------
   9) Recommended default monthly limits
   ------------------------------------------------------------ */
INSERT INTO dbo.monthly_support_limits (support_type_id, governorate_id, max_monthly_amount, max_monthly_times)
SELECT st.support_type_id, NULL, 3000, 1
FROM dbo.support_types st
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.monthly_support_limits l
    WHERE l.support_type_id = st.support_type_id AND l.governorate_id IS NULL
);
GO

PRINT 'PHASE 2 business schema installed successfully.';
GO
