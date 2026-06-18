param(
    [switch]$RunPipeline
)

$ErrorActionPreference = "Stop"

$BaseDir = ".\data_engineering\demo_operational_seed"
$SqlFile = "$BaseDir\sql\seed_operational_demo_story_pack.sql"
$ResultFile = "$BaseDir\results\demo_story_pack_latest.txt"

function New-DemoBlock {
    param(
        [string]$DbName,
        [string]$Prefix,
        [int]$OrgSk,
        [string]$OrgCode,
        [string]$OrgName
    )

@"
USE [$DbName];
GO

SET NOCOUNT ON;

DECLARE @Prefix NVARCHAR(20) = N'$Prefix';
DECLARE @OrgSk INT = $OrgSk;
DECLARE @OrgCode NVARCHAR(50) = N'$OrgCode';
DECLARE @OrgName NVARCHAR(100) = N'$OrgName';
DECLARE @DemoTag NVARCHAR(30) = N'DEMO2026';

PRINT 'Cleaning old demo story pack for $DbName';

DELETE FROM dbo.donations
WHERE donation_code LIKE @Prefix + N'-DEMO2026-%';

DELETE FROM dbo.inventory_transactions
WHERE transaction_code LIKE @Prefix + N'-DEMO2026-%';

DELETE FROM dbo.source_event_outbox
WHERE payload_json LIKE N'%DEMO2026%';

DELETE FROM dbo.beneficiary_documents
WHERE file_name LIKE LOWER(@Prefix) + N'_demo2026_%'
   OR object_store_key LIKE N'%DEMO2026%';

DELETE FROM dbo.cases
WHERE case_code LIKE @Prefix + N'-DEMO2026-%';

DELETE FROM dbo.applications
WHERE application_code LIKE @Prefix + N'-DEMO2026-%';

DELETE FROM dbo.donors
WHERE donor_code LIKE @Prefix + N'-DEMO2026-%';

DELETE FROM dbo.beneficiaries
WHERE full_name LIKE N'DEMO2026%'
   OR national_id IN
   (
       N'39999999990001',
       N'39999999990002',
       N'39999999990003',
       CONCAT(N'3', RIGHT(N'000' + CAST(@OrgSk AS NVARCHAR(3)), 3), N'0000000010'),
       CONCAT(N'3', RIGHT(N'000' + CAST(@OrgSk AS NVARCHAR(3)), 3), N'0000000011'),
       CONCAT(N'3', RIGHT(N'000' + CAST(@OrgSk AS NVARCHAR(3)), 3), N'0000000012'),
       CONCAT(N'3', RIGHT(N'000' + CAST(@OrgSk AS NVARCHAR(3)), 3), N'0000000013'),
       CONCAT(N'3', RIGHT(N'000' + CAST(@OrgSk AS NVARCHAR(3)), 3), N'0000000014'),
       CONCAT(N'3', RIGHT(N'000' + CAST(@OrgSk AS NVARCHAR(3)), 3), N'0000000015'),
       CONCAT(N'3', RIGHT(N'000' + CAST(@OrgSk AS NVARCHAR(3)), 3), N'0000000016'),
       CONCAT(N'3', RIGHT(N'000' + CAST(@OrgSk AS NVARCHAR(3)), 3), N'0000000017')
   );

PRINT 'Inserting demo story pack for $DbName';

DECLARE @DonorNormal INT;
DECLARE @DonorCorporate INT;
DECLARE @DonorMicro INT;
DECLARE @DonorRefund INT;
DECLARE @DonorAnonymous INT;

INSERT INTO dbo.donors
(
    donor_code, donor_name, phone, email, donor_category, created_at, updated_at
)
VALUES
(
    @Prefix + N'-DEMO2026-DONOR-NORMAL',
    N'DEMO2026 Regular Monthly Donor - ' + @OrgName,
    N'01066000001',
    N'demo.normal.' + LOWER(@Prefix) + N'@example.com',
    N'Monthly Donor',
    DATEADD(DAY, -180, GETDATE()),
    NULL
);
SET @DonorNormal = SCOPE_IDENTITY();

INSERT INTO dbo.donors
(
    donor_code, donor_name, phone, email, donor_category, created_at, updated_at
)
VALUES
(
    @Prefix + N'-DEMO2026-DONOR-CORPORATE',
    N'DEMO2026 Corporate Donor - ' + @OrgName,
    N'01066000002',
    N'demo.corporate.' + LOWER(@Prefix) + N'@example.com',
    N'Corporate',
    DATEADD(DAY, -160, GETDATE()),
    NULL
);
SET @DonorCorporate = SCOPE_IDENTITY();

INSERT INTO dbo.donors
(
    donor_code, donor_name, phone, email, donor_category, created_at, updated_at
)
VALUES
(
    @Prefix + N'-DEMO2026-DONOR-MICRO-BURST',
    N'DEMO2026 Suspicious Micro Donation Donor - ' + @OrgName,
    N'01066000003',
    N'demo.micro.' + LOWER(@Prefix) + N'@example.com',
    N'Individual',
    DATEADD(DAY, -90, GETDATE()),
    NULL
);
SET @DonorMicro = SCOPE_IDENTITY();

INSERT INTO dbo.donors
(
    donor_code, donor_name, phone, email, donor_category, created_at, updated_at
)
VALUES
(
    @Prefix + N'-DEMO2026-DONOR-REFUND',
    N'DEMO2026 Refund Pattern Donor - ' + @OrgName,
    N'01066000004',
    N'demo.refund.' + LOWER(@Prefix) + N'@example.com',
    N'Individual',
    DATEADD(DAY, -70, GETDATE()),
    NULL
);
SET @DonorRefund = SCOPE_IDENTITY();

INSERT INTO dbo.donors
(
    donor_code, donor_name, phone, email, donor_category, created_at, updated_at
)
VALUES
(
    @Prefix + N'-DEMO2026-DONOR-ANON',
    N'DEMO2026 Anonymous Donor - ' + @OrgName,
    N'01066000005',
    NULL,
    N'Anonymous',
    DATEADD(DAY, -30, GETDATE()),
    NULL
);
SET @DonorAnonymous = SCOPE_IDENTITY();

DECLARE @Demo TABLE
(
    scenario_order INT,
    scenario_key NVARCHAR(80),
    national_id NVARCHAR(14),
    full_name NVARCHAR(200),
    gender NVARCHAR(20),
    birth_date DATE,
    phone NVARCHAR(30),
    email NVARCHAR(200),
    governorate_name NVARCHAR(100),
    city_name NVARCHAR(100),
    address NVARCHAR(300),
    family_size INT,
    monthly_income DECIMAL(18,2),
    employment_status NVARCHAR(100),
    support_type_name NVARCHAR(100),
    requested_amount DECIMAL(18,2),
    application_status NVARCHAR(50),
    priority_level NVARCHAR(50),
    doc_status_1 NVARCHAR(50),
    doc_status_2 NVARCHAR(50),
    case_status NVARCHAR(50),
    collected_ratio DECIMAL(10,2),
    donation_pattern NVARCHAR(50),
    inventory_pattern NVARCHAR(50),
    risk_label NVARCHAR(200)
);

INSERT INTO @Demo VALUES
(1,  N'NORMAL_FOOD_APPROVED',       CONCAT(N'3', RIGHT(N'000' + CAST(@OrgSk AS NVARCHAR(3)), 3), N'0000000010'), N'DEMO2026 Normal Food Support Family - ' + @OrgName, N'Female', CAST(DATEADD(YEAR, -34, GETDATE()) AS DATE), N'01177000010', N'demo.normal.family.' + LOWER(@Prefix) + N'@example.com', N'Cairo',      N'Nasr City', N'10 Main Street', 5, 1800, N'Housewife',       N'Food Support',          1800,  N'APPROVED',     N'MEDIUM',   N'VERIFIED', N'VERIFIED', N'FUNDED',    1.00, N'NORMAL',      N'NORMAL_OUT', N'Normal approved and fully funded case'),
(2,  N'MEDICAL_PENDING_DOCS',       CONCAT(N'3', RIGHT(N'000' + CAST(@OrgSk AS NVARCHAR(3)), 3), N'0000000011'), N'DEMO2026 Medical Pending Documents - ' + @OrgName,  N'Male',   CAST(DATEADD(YEAR, -61, GETDATE()) AS DATE), N'01177000011', NULL,                                               N'Giza',       N'Dokki',     N'11 Health Street', 2, 900,  N'Retired',         N'Medical Support',       12000, N'UNDER_REVIEW', N'HIGH',     N'VERIFIED', N'PENDING',  N'OPEN',      0.00, N'NONE',        N'NONE',       N'Pending documents requiring manual review'),
(3,  N'CROSS_ORG_DUPLICATE_NID',    N'39999999990001',                                                      N'DEMO2026 Cross Organization Duplicate Beneficiary - ' + @OrgName, N'Female', CAST(DATEADD(YEAR, -42, GETDATE()) AS DATE), N'01199000001', N'demo.duplicate.cross.org@example.com',                  N'Alexandria', N'Mandara',   N'12 Sea Street', 4, 1200, N'Daily Worker',    N'Monthly Cash Support',  4500,  N'APPROVED',     N'HIGH',     N'VERIFIED', N'VERIFIED', N'OPEN',      0.25, N'MIXED',       N'NORMAL_OUT', N'Same national ID appears across multiple charities'),
(4,  N'SAME_PHONE_DIFFERENT_NID_A', CONCAT(N'3', RIGHT(N'000' + CAST(@OrgSk AS NVARCHAR(3)), 3), N'0000000012'), N'DEMO2026 Same Phone Identity A - ' + @OrgName,       N'Male',   CAST(DATEADD(YEAR, -39, GETDATE()) AS DATE), N'01199000002', NULL,                                               N'Dakahlia',   N'Mansoura',  N'13 River Street', 6, 700,  N'Unemployed',     N'Food Support',          2200,  N'APPROVED',     N'MEDIUM',   N'VERIFIED', N'VERIFIED', N'PUBLISHED', 0.50, N'MIXED',       N'NORMAL_OUT', N'Same phone used by multiple national IDs'),
(5,  N'SAME_PHONE_DIFFERENT_NID_B', CONCAT(N'3', RIGHT(N'000' + CAST(@OrgSk AS NVARCHAR(3)), 3), N'0000000013'), N'DEMO2026 Same Phone Identity B - ' + @OrgName,       N'Female', CAST(DATEADD(YEAR, -28, GETDATE()) AS DATE), N'01199000002', NULL,                                               N'Dakahlia',   N'Mansoura',  N'14 River Street', 3, 950,  N'Part Time',      N'Ramadan Box',           1500,  N'SUBMITTED',    N'LOW',      N'PENDING',  N'PENDING',  N'OPEN',      0.00, N'NONE',        N'NONE',       N'Same phone used by multiple national IDs'),
(6,  N'HIGH_AMOUNT_CRITICAL',       CONCAT(N'3', RIGHT(N'000' + CAST(@OrgSk AS NVARCHAR(3)), 3), N'0000000014'), N'DEMO2026 Critical Housing Case - ' + @OrgName,       N'Male',   CAST(DATEADD(YEAR, -46, GETDATE()) AS DATE), N'01177000014', N'demo.critical.' + LOWER(@Prefix) + N'@example.com', N'Minya',      N'Minya',     N'15 Housing Street', 7, 500,  N'Daily Worker',    N'Housing Support',       35000, N'APPROVED',     N'CRITICAL', N'VERIFIED', N'VERIFIED', N'OPEN',      0.10, N'MIXED',       N'HIGH_OUT',    N'Critical high requested amount with low collection'),
(7,  N'MICRO_DONATION_BURST',       CONCAT(N'3', RIGHT(N'000' + CAST(@OrgSk AS NVARCHAR(3)), 3), N'0000000015'), N'DEMO2026 Micro Donation Burst Case - ' + @OrgName,   N'Female', CAST(DATEADD(YEAR, -51, GETDATE()) AS DATE), N'01177000015', NULL,                                               N'Assiut',     N'Assiut',    N'16 Donation Street', 5, 1100, N'Unable to Work', N'Medical Support',       9000,  N'APPROVED',     N'HIGH',     N'VERIFIED', N'VERIFIED', N'PUBLISHED', 0.60, N'MICRO_BURST', N'NONE',       N'Many small donations from same donor to same case'),
(8,  N'REFUNDED_DONATION_PATTERN',  CONCAT(N'3', RIGHT(N'000' + CAST(@OrgSk AS NVARCHAR(3)), 3), N'0000000016'), N'DEMO2026 Refunded Donation Case - ' + @OrgName,      N'Male',   CAST(DATEADD(YEAR, -37, GETDATE()) AS DATE), N'01177000016', NULL,                                               N'Sohag',      N'Sohag',     N'17 Refund Street', 4, 1600, N'Daily Worker',    N'Emergency Aid',         6500,  N'APPROVED',     N'HIGH',     N'VERIFIED', N'VERIFIED', N'OPEN',      0.40, N'REFUND',      N'NONE',       N'Refunded donation pattern'),
(9,  N'REJECTED_FAKE_DOCS',         CONCAT(N'3', RIGHT(N'000' + CAST(@OrgSk AS NVARCHAR(3)), 3), N'0000000017'), N'DEMO2026 Rejected Fake Documents - ' + @OrgName,     N'Female', CAST(DATEADD(YEAR, -30, GETDATE()) AS DATE), N'01177000017', NULL,                                               N'Aswan',      N'Aswan',     N'18 Document Street', 2, 3000, N'Part Time',      N'Education Support',     8000,  N'REJECTED',    N'MEDIUM',   N'PENDING',  N'PENDING',  N'OPEN',      0.00, N'NONE',        N'NONE',       N'Rejected application due to suspicious or incomplete documents');

DECLARE demo_cursor CURSOR FOR
SELECT
    scenario_order,
    scenario_key,
    national_id,
    full_name,
    gender,
    birth_date,
    phone,
    email,
    governorate_name,
    city_name,
    address,
    family_size,
    monthly_income,
    employment_status,
    support_type_name,
    requested_amount,
    application_status,
    priority_level,
    doc_status_1,
    doc_status_2,
    case_status,
    collected_ratio,
    donation_pattern,
    inventory_pattern,
    risk_label
FROM @Demo
ORDER BY scenario_order;

DECLARE
    @ScenarioOrder INT,
    @ScenarioKey NVARCHAR(80),
    @NationalId NVARCHAR(14),
    @FullName NVARCHAR(200),
    @Gender NVARCHAR(20),
    @BirthDate DATE,
    @Phone NVARCHAR(30),
    @Email NVARCHAR(200),
    @Governorate NVARCHAR(100),
    @City NVARCHAR(100),
    @Address NVARCHAR(300),
    @FamilySize INT,
    @MonthlyIncome DECIMAL(18,2),
    @EmploymentStatus NVARCHAR(100),
    @SupportType NVARCHAR(100),
    @RequestedAmount DECIMAL(18,2),
    @AppStatus NVARCHAR(50),
    @Priority NVARCHAR(50),
    @Doc1 NVARCHAR(50),
    @Doc2 NVARCHAR(50),
    @CaseStatus NVARCHAR(50),
    @CollectedRatio DECIMAL(10,2),
    @DonationPattern NVARCHAR(50),
    @InventoryPattern NVARCHAR(50),
    @RiskLabel NVARCHAR(200);

OPEN demo_cursor;

FETCH NEXT FROM demo_cursor INTO
    @ScenarioOrder, @ScenarioKey, @NationalId, @FullName, @Gender, @BirthDate, @Phone, @Email,
    @Governorate, @City, @Address, @FamilySize, @MonthlyIncome, @EmploymentStatus,
    @SupportType, @RequestedAmount, @AppStatus, @Priority, @Doc1, @Doc2, @CaseStatus,
    @CollectedRatio, @DonationPattern, @InventoryPattern, @RiskLabel;

WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @BenId INT;
    DECLARE @AppId INT;
    DECLARE @CaseId INT;
    DECLARE @BranchId INT = 1 + (@ScenarioOrder % 6);
    DECLARE @CollectedAmount DECIMAL(18,2) = @RequestedAmount * @CollectedRatio;

    INSERT INTO dbo.beneficiaries
    (
        national_id,
        full_name,
        gender,
        birth_date,
        phone,
        email,
        governorate_name,
        city_name,
        address,
        family_size,
        monthly_income,
        employment_status,
        created_at,
        updated_at
    )
    VALUES
    (
        @NationalId,
        @FullName,
        @Gender,
        @BirthDate,
        @Phone,
        @Email,
        @Governorate,
        @City,
        @Address,
        @FamilySize,
        @MonthlyIncome,
        @EmploymentStatus,
        DATEADD(DAY, -@ScenarioOrder * 5, GETDATE()),
        NULL
    );

    SET @BenId = SCOPE_IDENTITY();

    INSERT INTO dbo.applications
    (
        application_code,
        source_beneficiary_id,
        source_branch_id,
        support_type_name,
        requested_amount,
        application_status,
        priority_level,
        submitted_at,
        reviewed_at,
        staff_notes,
        updated_at
    )
    VALUES
    (
        @Prefix + N'-DEMO2026-APP-' + RIGHT(N'00' + CAST(@ScenarioOrder AS NVARCHAR(10)), 2),
        @BenId,
        @BranchId,
        @SupportType,
        @RequestedAmount,
        @AppStatus,
        @Priority,
        DATEADD(DAY, -@ScenarioOrder * 4, GETDATE()),
        CASE WHEN @AppStatus IN (N'APPROVED', N'REJECTED') THEN DATEADD(DAY, -@ScenarioOrder * 3, GETDATE()) ELSE NULL END,
        N'DEMO2026 scenario: ' + @RiskLabel,
        NULL
    );

    SET @AppId = SCOPE_IDENTITY();

    INSERT INTO dbo.beneficiary_documents
    (
        source_beneficiary_id,
        source_application_id,
        document_type_name,
        file_name,
        object_store_key,
        file_url,
        verification_status,
        uploaded_at,
        updated_at
    )
    VALUES
    (
        @BenId,
        @AppId,
        N'National ID',
        LOWER(@Prefix) + N'_demo2026_' + @ScenarioKey + N'_national_id.pdf',
        N'DEMO2026/' + @Prefix + N'/' + @ScenarioKey + N'/national_id.pdf',
        N'minio://charity-documents/DEMO2026/' + @Prefix + N'/' + @ScenarioKey + N'/national_id.pdf',
        @Doc1,
        DATEADD(DAY, -@ScenarioOrder * 4, GETDATE()),
        NULL
    );

    INSERT INTO dbo.beneficiary_documents
    (
        source_beneficiary_id,
        source_application_id,
        document_type_name,
        file_name,
        object_store_key,
        file_url,
        verification_status,
        uploaded_at,
        updated_at
    )
    VALUES
    (
        @BenId,
        @AppId,
        CASE WHEN @ScenarioOrder % 2 = 0 THEN N'Income Proof' ELSE N'Family Certificate' END,
        LOWER(@Prefix) + N'_demo2026_' + @ScenarioKey + N'_support.pdf',
        N'DEMO2026/' + @Prefix + N'/' + @ScenarioKey + N'/support.pdf',
        N'minio://charity-documents/DEMO2026/' + @Prefix + N'/' + @ScenarioKey + N'/support.pdf',
        @Doc2,
        DATEADD(DAY, -@ScenarioOrder * 4, GETDATE()),
        NULL
    );

    IF @AppStatus = N'APPROVED'
    BEGIN
        INSERT INTO dbo.cases
        (
            case_code,
            source_application_id,
            source_beneficiary_id,
            source_branch_id,
            case_title,
            support_type_name,
            case_status,
            target_amount,
            collected_amount,
            opened_at,
            closed_at,
            updated_at
        )
        VALUES
        (
            @Prefix + N'-DEMO2026-CASE-' + RIGHT(N'00' + CAST(@ScenarioOrder AS NVARCHAR(10)), 2),
            @AppId,
            @BenId,
            @BranchId,
            N'DEMO2026 ' + @SupportType + N' - ' + @ScenarioKey,
            @SupportType,
            @CaseStatus,
            @RequestedAmount,
            @CollectedAmount,
            DATEADD(DAY, -@ScenarioOrder * 3, GETDATE()),
            CASE WHEN @CaseStatus = N'FUNDED' THEN DATEADD(DAY, -@ScenarioOrder * 2, GETDATE()) ELSE NULL END,
            NULL
        );

        SET @CaseId = SCOPE_IDENTITY();

        IF @DonationPattern = N'NORMAL'
        BEGIN
            INSERT INTO dbo.donations
            (
                donation_code,
                source_donor_id,
                source_case_id,
                source_branch_id,
                amount,
                payment_method_name,
                donation_status,
                donated_at,
                notes,
                updated_at
            )
            VALUES
            (
                @Prefix + N'-DEMO2026-DON-NORMAL-' + CAST(@ScenarioOrder AS NVARCHAR(10)),
                @DonorNormal,
                @CaseId,
                @BranchId,
                CASE WHEN @CollectedAmount > 0 THEN @CollectedAmount ELSE 500 END,
                N'Visa',
                N'COMPLETED',
                DATEADD(DAY, -@ScenarioOrder * 2, GETDATE()),
                N'DEMO2026 normal completed donation',
                NULL
            );
        END

        IF @DonationPattern = N'MIXED'
        BEGIN
            INSERT INTO dbo.donations
            (
                donation_code, source_donor_id, source_case_id, source_branch_id, amount,
                payment_method_name, donation_status, donated_at, notes, updated_at
            )
            VALUES
            (@Prefix + N'-DEMO2026-DON-MIXED-A-' + CAST(@ScenarioOrder AS NVARCHAR(10)), @DonorNormal,    @CaseId, @BranchId, 250,  N'Cash',          N'COMPLETED', DATEADD(DAY, -@ScenarioOrder * 2, GETDATE()), N'DEMO2026 mixed donation', NULL),
            (@Prefix + N'-DEMO2026-DON-MIXED-B-' + CAST(@ScenarioOrder AS NVARCHAR(10)), @DonorCorporate, @CaseId, @BranchId, 1000, N'Bank Transfer', N'COMPLETED', DATEADD(DAY, -@ScenarioOrder * 2, GETDATE()), N'DEMO2026 mixed donation', NULL),
            (@Prefix + N'-DEMO2026-DON-MIXED-C-' + CAST(@ScenarioOrder AS NVARCHAR(10)), @DonorAnonymous, @CaseId, @BranchId, 500,  N'Vodafone Cash', N'COMPLETED', DATEADD(DAY, -@ScenarioOrder * 2, GETDATE()), N'DEMO2026 mixed donation', NULL);
        END

        IF @DonationPattern = N'MICRO_BURST'
        BEGIN
            DECLARE @d INT = 1;
            WHILE @d <= 8
            BEGIN
                INSERT INTO dbo.donations
                (
                    donation_code,
                    source_donor_id,
                    source_case_id,
                    source_branch_id,
                    amount,
                    payment_method_name,
                    donation_status,
                    donated_at,
                    notes,
                    updated_at
                )
                VALUES
                (
                    @Prefix + N'-DEMO2026-DON-MICRO-' + CAST(@ScenarioOrder AS NVARCHAR(10)) + N'-' + CAST(@d AS NVARCHAR(10)),
                    @DonorMicro,
                    @CaseId,
                    @BranchId,
                    CASE @d WHEN 1 THEN 50 WHEN 2 THEN 75 WHEN 3 THEN 100 WHEN 4 THEN 125 WHEN 5 THEN 150 WHEN 6 THEN 175 WHEN 7 THEN 200 ELSE 225 END,
                    N'Vodafone Cash',
                    N'COMPLETED',
                    DATEADD(MINUTE, @d * 5, DATEADD(DAY, -2, CAST(GETDATE() AS DATETIME))),
                    N'DEMO2026 suspicious micro-donation burst',
                    NULL
                );

                SET @d += 1;
            END
        END

        IF @DonationPattern = N'REFUND'
        BEGIN
            INSERT INTO dbo.donations
            (
                donation_code, source_donor_id, source_case_id, source_branch_id, amount,
                payment_method_name, donation_status, donated_at, notes, updated_at
            )
            VALUES
            (@Prefix + N'-DEMO2026-DON-REFUND-A-' + CAST(@ScenarioOrder AS NVARCHAR(10)), @DonorRefund, @CaseId, @BranchId, 1500, N'Visa',  N'COMPLETED', DATEADD(DAY, -4, GETDATE()), N'DEMO2026 completed before refund', NULL),
            (@Prefix + N'-DEMO2026-DON-REFUND-B-' + CAST(@ScenarioOrder AS NVARCHAR(10)), @DonorRefund, @CaseId, @BranchId, 1500, N'Visa',  N'REFUNDED',  DATEADD(DAY, -3, GETDATE()), N'DEMO2026 refunded donation pattern', NULL);
        END

        IF @InventoryPattern IN (N'NORMAL_OUT', N'HIGH_OUT')
        BEGIN
            INSERT INTO dbo.inventory_transactions
            (
                transaction_code,
                source_branch_id,
                source_item_id,
                source_case_id,
                transaction_type,
                quantity,
                unit_cost,
                transaction_date,
                notes,
                updated_at
            )
            VALUES
            (
                @Prefix + N'-DEMO2026-INV-' + CAST(@ScenarioOrder AS NVARCHAR(10)),
                @BranchId,
                1 + (@ScenarioOrder % 6),
                @CaseId,
                N'OUT',
                CASE WHEN @InventoryPattern = N'HIGH_OUT' THEN 25 ELSE 3 END,
                CASE WHEN @InventoryPattern = N'HIGH_OUT' THEN 450 ELSE 90 END,
                DATEADD(DAY, -@ScenarioOrder, GETDATE()),
                N'DEMO2026 inventory movement: ' + @InventoryPattern,
                NULL
            );
        END
    END

    INSERT INTO dbo.source_event_outbox
    (
        event_uuid,
        event_type,
        entity_name,
        entity_id,
        payload_json,
        event_status,
        created_at,
        published_at
    )
    VALUES
    (
        NEWID(),
        N'DEMO_FRAUD_SIGNAL',
        N'applications',
        CAST(@AppId AS NVARCHAR(50)),
        CONCAT(
            N'{"demo_tag":"DEMO2026","organization":"', @OrgCode,
            N'","scenario":"', @ScenarioKey,
            N'","risk_label":"', @RiskLabel,
            N'","application_id":"', @AppId,
            N'"}'
        ),
        N'PENDING',
        GETDATE(),
        NULL
    );

    FETCH NEXT FROM demo_cursor INTO
        @ScenarioOrder, @ScenarioKey, @NationalId, @FullName, @Gender, @BirthDate, @Phone, @Email,
        @Governorate, @City, @Address, @FamilySize, @MonthlyIncome, @EmploymentStatus,
        @SupportType, @RequestedAmount, @AppStatus, @Priority, @Doc1, @Doc2, @CaseStatus,
        @CollectedRatio, @DonationPattern, @InventoryPattern, @RiskLabel;
END

CLOSE demo_cursor;
DEALLOCATE demo_cursor;

SELECT DB_NAME() AS source_db, 'beneficiaries' AS table_name, COUNT(*) AS demo_rows
FROM dbo.beneficiaries
WHERE full_name LIKE N'DEMO2026%'
UNION ALL
SELECT DB_NAME(), 'applications', COUNT(*)
FROM dbo.applications
WHERE application_code LIKE @Prefix + N'-DEMO2026-%'
UNION ALL
SELECT DB_NAME(), 'cases', COUNT(*)
FROM dbo.cases
WHERE case_code LIKE @Prefix + N'-DEMO2026-%'
UNION ALL
SELECT DB_NAME(), 'donors', COUNT(*)
FROM dbo.donors
WHERE donor_code LIKE @Prefix + N'-DEMO2026-%'
UNION ALL
SELECT DB_NAME(), 'donations', COUNT(*)
FROM dbo.donations
WHERE donation_code LIKE @Prefix + N'-DEMO2026-%'
UNION ALL
SELECT DB_NAME(), 'inventory_transactions', COUNT(*)
FROM dbo.inventory_transactions
WHERE transaction_code LIKE @Prefix + N'-DEMO2026-%'
UNION ALL
SELECT DB_NAME(), 'beneficiary_documents', COUNT(*)
FROM dbo.beneficiary_documents
WHERE file_name LIKE LOWER(@Prefix) + N'_demo2026_%'
UNION ALL
SELECT DB_NAME(), 'source_event_outbox', COUNT(*)
FROM dbo.source_event_outbox
WHERE payload_json LIKE N'%DEMO2026%';
GO

"@
}

$sql = @()
$sql += New-DemoBlock -DbName "charity_food_bank_operational" -Prefix "FB" -OrgSk 1 -OrgCode "food_bank" -OrgName "Food Bank"
$sql += New-DemoBlock -DbName "charity_resala_operational" -Prefix "RES" -OrgSk 2 -OrgCode "resala" -OrgName "Resala"
$sql += New-DemoBlock -DbName "charity_haya_karima_operational" -Prefix "HK" -OrgSk 3 -OrgCode "haya_karima" -OrgName "Haya Karima"

$sql += @"
USE charity_dwh;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'analytics_real')
BEGIN
    EXEC('CREATE SCHEMA analytics_real');
END
GO

CREATE OR ALTER VIEW analytics_real.v_demo_fraud_alerts AS
WITH all_beneficiaries AS
(
    SELECT 'food_bank' AS organization_code, source_beneficiary_id AS beneficiary_id, national_id, full_name, phone, governorate_name, city_name, monthly_income
    FROM charity_food_bank_operational.dbo.beneficiaries
    WHERE full_name LIKE N'DEMO2026%'
    UNION ALL
    SELECT 'resala', source_beneficiary_id, national_id, full_name, phone, governorate_name, city_name, monthly_income
    FROM charity_resala_operational.dbo.beneficiaries
    WHERE full_name LIKE N'DEMO2026%'
    UNION ALL
    SELECT 'haya_karima', source_beneficiary_id, national_id, full_name, phone, governorate_name, city_name, monthly_income
    FROM charity_haya_karima_operational.dbo.beneficiaries
    WHERE full_name LIKE N'DEMO2026%'
),
all_applications AS
(
    SELECT 'food_bank' AS organization_code, source_application_id AS application_id, source_beneficiary_id AS beneficiary_id, application_code, support_type_name, requested_amount, application_status, priority_level, submitted_at
    FROM charity_food_bank_operational.dbo.applications
    WHERE application_code LIKE N'FB-DEMO2026-%'
    UNION ALL
    SELECT 'resala', source_application_id, source_beneficiary_id, application_code, support_type_name, requested_amount, application_status, priority_level, submitted_at
    FROM charity_resala_operational.dbo.applications
    WHERE application_code LIKE N'RES-DEMO2026-%'
    UNION ALL
    SELECT 'haya_karima', source_application_id, source_beneficiary_id, application_code, support_type_name, requested_amount, application_status, priority_level, submitted_at
    FROM charity_haya_karima_operational.dbo.applications
    WHERE application_code LIKE N'HK-DEMO2026-%'
),
all_documents AS
(
    SELECT 'food_bank' AS organization_code, source_application_id AS application_id, document_type_name, verification_status
    FROM charity_food_bank_operational.dbo.beneficiary_documents
    WHERE file_name LIKE N'fb_demo2026_%'
    UNION ALL
    SELECT 'resala', source_application_id, document_type_name, verification_status
    FROM charity_resala_operational.dbo.beneficiary_documents
    WHERE file_name LIKE N'res_demo2026_%'
    UNION ALL
    SELECT 'haya_karima', source_application_id, document_type_name, verification_status
    FROM charity_haya_karima_operational.dbo.beneficiary_documents
    WHERE file_name LIKE N'hk_demo2026_%'
),
all_cases AS
(
    SELECT 'food_bank' AS organization_code, source_case_id AS case_id, source_application_id AS application_id, source_beneficiary_id AS beneficiary_id, case_code, support_type_name, case_status, target_amount, collected_amount
    FROM charity_food_bank_operational.dbo.cases
    WHERE case_code LIKE N'FB-DEMO2026-%'
    UNION ALL
    SELECT 'resala', source_case_id, source_application_id, source_beneficiary_id, case_code, support_type_name, case_status, target_amount, collected_amount
    FROM charity_resala_operational.dbo.cases
    WHERE case_code LIKE N'RES-DEMO2026-%'
    UNION ALL
    SELECT 'haya_karima', source_case_id, source_application_id, source_beneficiary_id, case_code, support_type_name, case_status, target_amount, collected_amount
    FROM charity_haya_karima_operational.dbo.cases
    WHERE case_code LIKE N'HK-DEMO2026-%'
),
all_donations AS
(
    SELECT 'food_bank' AS organization_code, source_donation_id AS donation_id, source_donor_id AS donor_id, source_case_id AS case_id, donation_code, amount, payment_method_name, donation_status, donated_at
    FROM charity_food_bank_operational.dbo.donations
    WHERE donation_code LIKE N'FB-DEMO2026-%'
    UNION ALL
    SELECT 'resala', source_donation_id, source_donor_id, source_case_id, donation_code, amount, payment_method_name, donation_status, donated_at
    FROM charity_resala_operational.dbo.donations
    WHERE donation_code LIKE N'RES-DEMO2026-%'
    UNION ALL
    SELECT 'haya_karima', source_donation_id, source_donor_id, source_case_id, donation_code, amount, payment_method_name, donation_status, donated_at
    FROM charity_haya_karima_operational.dbo.donations
    WHERE donation_code LIKE N'HK-DEMO2026-%'
),
all_inventory AS
(
    SELECT 'food_bank' AS organization_code, source_inventory_transaction_id AS inventory_transaction_id, source_case_id AS case_id, transaction_code, transaction_type, quantity, unit_cost, quantity * unit_cost AS inventory_value
    FROM charity_food_bank_operational.dbo.inventory_transactions
    WHERE transaction_code LIKE N'FB-DEMO2026-%'
    UNION ALL
    SELECT 'resala', source_inventory_transaction_id, source_case_id, transaction_code, transaction_type, quantity, unit_cost, quantity * unit_cost
    FROM charity_resala_operational.dbo.inventory_transactions
    WHERE transaction_code LIKE N'RES-DEMO2026-%'
    UNION ALL
    SELECT 'haya_karima', source_inventory_transaction_id, source_case_id, transaction_code, transaction_type, quantity, unit_cost, quantity * unit_cost
    FROM charity_haya_karima_operational.dbo.inventory_transactions
    WHERE transaction_code LIKE N'HK-DEMO2026-%'
)

SELECT
    CONCAT('DUP_NID_', national_id) AS alert_id,
    'Duplicate Beneficiary Across Organizations' AS alert_type,
    'CRITICAL' AS severity,
    'MULTI_ORG' AS organization_code,
    'beneficiary' AS entity_type,
    CAST(NULL AS NVARCHAR(50)) AS entity_id,
    'Same national ID appears in more than one charity' AS alert_title,
    CONCAT('National ID ', national_id, ' appears in ', COUNT(DISTINCT organization_code), ' organizations') AS alert_details,
    SYSUTCDATETIME() AS detected_at
FROM all_beneficiaries
GROUP BY national_id
HAVING COUNT(DISTINCT organization_code) > 1

UNION ALL

SELECT
    CONCAT('SAME_PHONE_', organization_code, '_', phone),
    'Same Phone Different National IDs',
    'HIGH',
    organization_code,
    'beneficiary',
    CAST(NULL AS NVARCHAR(50)),
    'Same phone number is linked to multiple national IDs',
    CONCAT('Phone ', phone, ' is linked to ', COUNT(DISTINCT national_id), ' national IDs'),
    SYSUTCDATETIME()
FROM all_beneficiaries
GROUP BY organization_code, phone
HAVING COUNT(DISTINCT national_id) > 1

UNION ALL

SELECT
    CONCAT('PENDING_DOC_', d.organization_code, '_', d.application_id, '_', d.document_type_name),
    'Pending or Unverified Documents',
    'MEDIUM',
    d.organization_code,
    'application',
    CAST(d.application_id AS NVARCHAR(50)),
    'Application has pending documents',
    CONCAT('Document type ', d.document_type_name, ' has status ', d.verification_status),
    SYSUTCDATETIME()
FROM all_documents d
WHERE d.verification_status = 'PENDING'

UNION ALL

SELECT
    CONCAT('HIGH_AMOUNT_', organization_code, '_', application_id),
    'High Requested Amount',
    'HIGH',
    organization_code,
    'application',
    CAST(application_id AS NVARCHAR(50)),
    'High requested aid amount',
    CONCAT('Application ', application_code, ' requested ', requested_amount, ' with priority ', priority_level),
    SYSUTCDATETIME()
FROM all_applications
WHERE requested_amount >= 12000 OR priority_level = 'CRITICAL'

UNION ALL

SELECT
    CONCAT('MICRO_BURST_', organization_code, '_', donor_id, '_', case_id),
    'Micro Donation Burst',
    'HIGH',
    organization_code,
    'donation',
    CAST(case_id AS NVARCHAR(50)),
    'Multiple small donations from the same donor to the same case',
    CONCAT('Donor ', donor_id, ' made ', COUNT(*), ' donations to case ', case_id, ' on the same day'),
    SYSUTCDATETIME()
FROM all_donations
WHERE amount <= 250
GROUP BY organization_code, donor_id, case_id, CAST(donated_at AS DATE)
HAVING COUNT(*) >= 5

UNION ALL

SELECT
    CONCAT('REFUND_', organization_code, '_', donation_id),
    'Refunded Donation',
    'MEDIUM',
    organization_code,
    'donation',
    CAST(donation_id AS NVARCHAR(50)),
    'Donation was refunded',
    CONCAT('Donation ', donation_code, ' amount ', amount, ' has status ', donation_status),
    SYSUTCDATETIME()
FROM all_donations
WHERE donation_status = 'REFUNDED'

UNION ALL

SELECT
    CONCAT('LOW_COLLECTION_', organization_code, '_', case_id),
    'High Target Low Collection',
    'MEDIUM',
    organization_code,
    'case',
    CAST(case_id AS NVARCHAR(50)),
    'Case has high target amount with low collected amount',
    CONCAT('Target ', target_amount, ', collected ', collected_amount, ', status ', case_status),
    SYSUTCDATETIME()
FROM all_cases
WHERE target_amount >= 9000
  AND collected_amount < target_amount * 0.30
  AND case_status IN ('OPEN', 'PUBLISHED')

UNION ALL

SELECT
    CONCAT('INV_HIGH_OUT_', organization_code, '_', inventory_transaction_id),
    'High Value Inventory OUT',
    'HIGH',
    organization_code,
    'inventory_transaction',
    CAST(inventory_transaction_id AS NVARCHAR(50)),
    'High value inventory was moved out',
    CONCAT('Transaction ', transaction_code, ' value ', inventory_value, ', quantity ', quantity, ', unit cost ', unit_cost),
    SYSUTCDATETIME()
FROM all_inventory
WHERE transaction_type = 'OUT'
  AND inventory_value >= 5000;
GO

CREATE OR ALTER VIEW analytics_real.v_demo_fraud_summary AS
SELECT
    alert_type,
    severity,
    COUNT_BIG(*) AS alert_count
FROM analytics_real.v_demo_fraud_alerts
GROUP BY alert_type, severity;
GO

GRANT SELECT ON SCHEMA::analytics_real TO powerbi_reader;
GRANT VIEW DEFINITION ON SCHEMA::analytics_real TO powerbi_reader;

USE charity_food_bank_operational;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'powerbi_reader')
    CREATE USER powerbi_reader FOR LOGIN powerbi_reader;
GRANT SELECT ON SCHEMA::dbo TO powerbi_reader;

USE charity_resala_operational;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'powerbi_reader')
    CREATE USER powerbi_reader FOR LOGIN powerbi_reader;
GRANT SELECT ON SCHEMA::dbo TO powerbi_reader;

USE charity_haya_karima_operational;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'powerbi_reader')
    CREATE USER powerbi_reader FOR LOGIN powerbi_reader;
GRANT SELECT ON SCHEMA::dbo TO powerbi_reader;
GO

PRINT 'DEMO2026 operational demo data and fraud analytics views created successfully.';
GO
"@

$sql -join "`r`n" | Set-Content $SqlFile -Encoding UTF8

Write-Host "Demo SQL created:"
Write-Host $SqlFile

docker cp $SqlFile "ucp_sqlserver:/tmp/seed_operational_demo_story_pack.sql"

Write-Host "Running operational demo seed..."
$output = docker exec ucp_sqlserver /opt/mssql-tools18/bin/sqlcmd `
  -C `
  -S localhost `
  -U sa `
  -P "ChangeMe_StrongPassword_2026!" `
  -i /tmp/seed_operational_demo_story_pack.sql

$output | Tee-Object -FilePath $ResultFile

if ($output -match "Msg ") {
    Write-Host ""
    Write-Host "SQL error detected. Send me the output."
    exit 1
}

Write-Host ""
Write-Host "Validating demo fraud views..."

docker exec ucp_sqlserver /opt/mssql-tools18/bin/sqlcmd `
  -C `
  -S localhost `
  -U sa `
  -P "ChangeMe_StrongPassword_2026!" `
  -Q "USE charity_dwh; SELECT * FROM analytics_real.v_demo_fraud_summary ORDER BY severity, alert_type; SELECT TOP 50 * FROM analytics_real.v_demo_fraud_alerts ORDER BY severity, alert_type;"

if ($RunPipeline) {
    Write-Host ""
    Write-Host "RunPipeline enabled. Waiting for CDC/Debezium/Kafka..."
    Start-Sleep -Seconds 60

    powershell -ExecutionPolicy Bypass -File .\data_engineering\de8_spark_bronze\run_de8_spark_bronze.ps1
    powershell -ExecutionPolicy Bypass -File .\data_engineering\de8_spark_bronze\validate_de8_bronze.ps1

    powershell -ExecutionPolicy Bypass -File .\data_engineering\de9_spark_silver\run_de9_spark_silver.ps1
    powershell -ExecutionPolicy Bypass -File .\data_engineering\de9_spark_silver\validate_de9_silver.ps1

    powershell -ExecutionPolicy Bypass -File .\data_engineering\de10_spark_gold\run_de10_spark_gold.ps1
    powershell -ExecutionPolicy Bypass -File .\data_engineering\de10_spark_gold\validate_de10_gold.ps1

    powershell -ExecutionPolicy Bypass -File .\data_engineering\de11_gold_to_dwh\run_de11_gold_to_dwh.ps1
    powershell -ExecutionPolicy Bypass -File .\data_engineering\de11_gold_to_dwh\validate_de11_gold_to_dwh.ps1

    powershell -ExecutionPolicy Bypass -File .\data_engineering\de13_data_quality\run_de13_data_quality.ps1
    powershell -ExecutionPolicy Bypass -File .\data_engineering\de13_data_quality\validate_de13_data_quality.ps1

    powershell -ExecutionPolicy Bypass -File .\data_engineering\de17_powerbi_analytics\run_de17_powerbi_analytics.ps1
    powershell -ExecutionPolicy Bypass -File .\data_engineering\de17_powerbi_analytics\validate_de17_powerbi_analytics.ps1
}

Write-Host ""
Write-Host "DEMO2026 operational demo story pack completed."
Write-Host "Power BI: refresh analytics_real views."
Write-Host "Recommended extra views:"
Write-Host "analytics_real.v_demo_fraud_alerts"
Write-Host "analytics_real.v_demo_fraud_summary"

