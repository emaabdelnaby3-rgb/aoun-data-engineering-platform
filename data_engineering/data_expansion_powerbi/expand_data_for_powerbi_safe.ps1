param(
    [int]$NewBeneficiariesPerOrg = 3000,
    [switch]$SkipPipeline
)

$ErrorActionPreference = "Stop"

$BaseDir = ".\data_engineering\data_expansion_powerbi"
$SqlFile = "$BaseDir\sql\expand_source_data_for_powerbi_safe.sql"
$ResultFile = "$BaseDir\results\safe_expansion_latest.txt"

function New-SafeExpansionBlock {
    param(
        [string]$DbName,
        [string]$Prefix,
        [string]$OrgCode
    )

@"
USE [$DbName];
GO

SET NOCOUNT ON;

DECLARE @Rows INT = $NewBeneficiariesPerOrg;
DECLARE @Prefix NVARCHAR(20) = N'$Prefix';
DECLARE @OrgCode NVARCHAR(3) = N'$OrgCode';
DECLARE @RunTag NVARCHAR(30) = FORMAT(GETDATE(), 'yyyyMMddHHmmss');

PRINT 'SAFE expanding source data for $DbName';

DECLARE @i INT = 1;

WHILE @i <= @Rows
BEGIN
    DECLARE @DonorId INT;
    DECLARE @BenId INT;
    DECLARE @AppId INT;
    DECLARE @CaseId INT;
    DECLARE @DocId INT;
    DECLARE @DonationId INT;
    DECLARE @InvId INT;
    DECLARE @OutboxId INT;

    DECLARE @BranchId INT = 1 + (@i % 6);

    DECLARE @NationalId NVARCHAR(14) =
        CONCAT('3', @OrgCode, RIGHT('0000000000' + CAST(@i AS VARCHAR(10)), 10));

    DECLARE @SupportType NVARCHAR(100) =
        CASE @i % 10
            WHEN 0 THEN N'Food Support'
            WHEN 1 THEN N'Medical Support'
            WHEN 2 THEN N'Monthly Cash Support'
            WHEN 3 THEN N'Education Support'
            WHEN 4 THEN N'Housing Support'
            WHEN 5 THEN N'Debt Relief'
            WHEN 6 THEN N'Winter Blanket'
            WHEN 7 THEN N'Ramadan Box'
            WHEN 8 THEN N'Orphan Support'
            ELSE N'Emergency Aid'
        END;

    DECLARE @RequestedAmount DECIMAL(18,2) =
        CASE @i % 8
            WHEN 0 THEN 700
            WHEN 1 THEN 1200
            WHEN 2 THEN 2000
            WHEN 3 THEN 3500
            WHEN 4 THEN 5000
            WHEN 5 THEN 7500
            WHEN 6 THEN 10000
            ELSE 15000
        END;

    DECLARE @ApplicationStatus NVARCHAR(50) =
        CASE
            WHEN @i % 10 IN (0,1,2,3,4,5,6) THEN N'APPROVED'
            WHEN @i % 10 IN (7,8) THEN N'UNDER_REVIEW'
            ELSE N'REJECTED'
        END;

    ------------------------------------------------------------
    -- Donor: one donor per beneficiary every loop
    ------------------------------------------------------------
    INSERT INTO dbo.donors
    (
        donor_code,
        donor_name,
        phone,
        email,
        donor_category,
        created_at,
        updated_at
    )
    VALUES
    (
        CONCAT(@Prefix, N'-SAFE-DONOR-', @RunTag, N'-', @i),
        CONCAT(N'Donor ', @Prefix, N' ', @RunTag, N' ', @i),
        CONCAT('010', RIGHT('00000000' + CAST((10000000 + @i) AS VARCHAR(8)), 8)),
        CONCAT('safe_donor_', LOWER(@Prefix), '_', @RunTag, '_', @i, '@example.com'),
        CASE @i % 4
            WHEN 0 THEN N'Individual'
            WHEN 1 THEN N'Corporate'
            WHEN 2 THEN N'Monthly Donor'
            ELSE N'Anonymous'
        END,
        DATEADD(DAY, -(@i % 720), GETDATE()),
        NULL
    );

    SET @DonorId = SCOPE_IDENTITY();

    ------------------------------------------------------------
    -- Beneficiary
    ------------------------------------------------------------
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
        CONCAT(N'Beneficiary ', @Prefix, N' ', @RunTag, N' ', @i),
        CASE WHEN @i % 2 = 0 THEN N'Female' ELSE N'Male' END,
        CAST(DATEADD(DAY, -((@i % 16000) + 7000), GETDATE()) AS DATE),
        CONCAT('011', RIGHT('00000000' + CAST((20000000 + @i) AS VARCHAR(8)), 8)),
        CASE WHEN @i % 5 = 0 THEN CONCAT('safe_beneficiary_', LOWER(@Prefix), '_', @RunTag, '_', @i, '@example.com') ELSE NULL END,
        CASE @i % 12
            WHEN 0 THEN N'Cairo'
            WHEN 1 THEN N'Giza'
            WHEN 2 THEN N'Alexandria'
            WHEN 3 THEN N'Dakahlia'
            WHEN 4 THEN N'Sharqia'
            WHEN 5 THEN N'Qalyubia'
            WHEN 6 THEN N'Gharbia'
            WHEN 7 THEN N'Monufia'
            WHEN 8 THEN N'Minya'
            WHEN 9 THEN N'Assiut'
            WHEN 10 THEN N'Sohag'
            ELSE N'Aswan'
        END,
        CASE @i % 8
            WHEN 0 THEN N'Nasr City'
            WHEN 1 THEN N'Dokki'
            WHEN 2 THEN N'Mansoura'
            WHEN 3 THEN N'Zagazig'
            WHEN 4 THEN N'Tanta'
            WHEN 5 THEN N'Minya'
            WHEN 6 THEN N'Assiut'
            ELSE N'Aswan'
        END,
        CONCAT(1 + (@i % 120), N' Main Street'),
        1 + (@i % 8),
        CASE @i % 8
            WHEN 0 THEN 0
            WHEN 1 THEN 500
            WHEN 2 THEN 900
            WHEN 3 THEN 1400
            WHEN 4 THEN 2000
            WHEN 5 THEN 2800
            WHEN 6 THEN 3700
            ELSE 4800
        END,
        CASE @i % 6
            WHEN 0 THEN N'Unemployed'
            WHEN 1 THEN N'Daily Worker'
            WHEN 2 THEN N'Part Time'
            WHEN 3 THEN N'Retired'
            WHEN 4 THEN N'Housewife'
            ELSE N'Unable to Work'
        END,
        DATEADD(DAY, -(@i % 720), GETDATE()),
        NULL
    );

    SET @BenId = SCOPE_IDENTITY();

    ------------------------------------------------------------
    -- Application
    ------------------------------------------------------------
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
        CONCAT(@Prefix, N'-SAFE-APP-', @RunTag, N'-', @i),
        @BenId,
        @BranchId,
        @SupportType,
        @RequestedAmount,
        @ApplicationStatus,
        CASE
            WHEN @RequestedAmount >= 10000 THEN N'CRITICAL'
            WHEN @i % 4 = 0 THEN N'HIGH'
            WHEN @i % 4 = 1 THEN N'MEDIUM'
            ELSE N'LOW'
        END,
        DATEADD(DAY, -(@i % 700), GETDATE()),
        CASE WHEN @ApplicationStatus IN (N'APPROVED', N'REJECTED') THEN DATEADD(DAY, -(@i % 680), GETDATE()) ELSE NULL END,
        CASE @i % 4
            WHEN 0 THEN N'Needs home visit'
            WHEN 1 THEN N'Documents verified'
            WHEN 2 THEN N'Urgent family support'
            ELSE N'Branch review completed'
        END,
        NULL
    );

    SET @AppId = SCOPE_IDENTITY();

    ------------------------------------------------------------
    -- Documents: 2 docs per beneficiary
    ------------------------------------------------------------
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
        CONCAT(LOWER(@Prefix), '_safe_', @RunTag, '_', @i, '_national_id.pdf'),
        CONCAT('source-documents/', @Prefix, '/', @RunTag, '/', @i, '/national_id.pdf'),
        CONCAT('minio://charity-documents/source-documents/', @Prefix, '/', @RunTag, '/', @i, '/national_id.pdf'),
        CASE WHEN @i % 7 = 0 THEN N'PENDING' ELSE N'VERIFIED' END,
        DATEADD(DAY, -(@i % 690), GETDATE()),
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
        CASE WHEN @i % 2 = 0 THEN N'Income Proof' ELSE N'Family Certificate' END,
        CONCAT(LOWER(@Prefix), '_safe_', @RunTag, '_', @i, '_support.pdf'),
        CONCAT('source-documents/', @Prefix, '/', @RunTag, '/', @i, '/support.pdf'),
        CONCAT('minio://charity-documents/source-documents/', @Prefix, '/', @RunTag, '/', @i, '/support.pdf'),
        CASE WHEN @i % 11 = 0 THEN N'PENDING' ELSE N'VERIFIED' END,
        DATEADD(DAY, -(@i % 690), GETDATE()),
        NULL
    );

    ------------------------------------------------------------
    -- Case + donations + inventory only for approved applications
    ------------------------------------------------------------
    IF @ApplicationStatus = N'APPROVED'
    BEGIN
        DECLARE @CollectedAmount DECIMAL(18,2) =
            CASE
                WHEN @i % 5 = 0 THEN @RequestedAmount
                WHEN @i % 5 = 1 THEN @RequestedAmount * 0.75
                WHEN @i % 5 = 2 THEN @RequestedAmount * 0.50
                WHEN @i % 5 = 3 THEN @RequestedAmount * 0.25
                ELSE 0
            END;

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
            CONCAT(@Prefix, N'-SAFE-CASE-', @RunTag, N'-', @i),
            @AppId,
            @BenId,
            @BranchId,
            CONCAT(@SupportType, N' case ', @RunTag, N' ', @i),
            @SupportType,
            CASE
                WHEN @CollectedAmount >= @RequestedAmount THEN N'FUNDED'
                WHEN @i % 3 = 0 THEN N'PUBLISHED'
                ELSE N'OPEN'
            END,
            @RequestedAmount,
            @CollectedAmount,
            DATEADD(DAY, -(@i % 650), GETDATE()),
            CASE WHEN @CollectedAmount >= @RequestedAmount THEN DATEADD(DAY, -(@i % 620), GETDATE()) ELSE NULL END,
            NULL
        );

        SET @CaseId = SCOPE_IDENTITY();

        DECLARE @d INT = 1;
        DECLARE @DonationLoops INT = CASE WHEN @i % 3 = 0 THEN 3 ELSE 2 END;

        WHILE @d <= @DonationLoops
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
                CONCAT(@Prefix, N'-SAFE-DON-', @RunTag, N'-', @i, N'-', @d),
                @DonorId,
                @CaseId,
                @BranchId,
                CASE (@i + @d) % 7
                    WHEN 0 THEN 100
                    WHEN 1 THEN 150
                    WHEN 2 THEN 250
                    WHEN 3 THEN 500
                    WHEN 4 THEN 750
                    WHEN 5 THEN 1000
                    ELSE 2000
                END,
                CASE (@i + @d) % 5
                    WHEN 0 THEN N'Cash'
                    WHEN 1 THEN N'Visa'
                    WHEN 2 THEN N'Bank Transfer'
                    WHEN 3 THEN N'Fawry'
                    ELSE N'Vodafone Cash'
                END,
                CASE WHEN (@i + @d) % 30 = 0 THEN N'REFUNDED' ELSE N'COMPLETED' END,
                DATEADD(DAY, -((@i + @d) % 640), GETDATE()),
                NULL,
                NULL
            );

            SET @d += 1;
        END;

        IF @i % 2 = 0
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
                CONCAT(@Prefix, N'-SAFE-INV-', @RunTag, N'-', @i),
                @BranchId,
                1 + (@i % 6),
                @CaseId,
                CASE WHEN @i % 8 = 0 THEN N'IN' ELSE N'OUT' END,
                1 + (@i % 5),
                CASE @i % 6
                    WHEN 0 THEN 35
                    WHEN 1 THEN 70
                    WHEN 2 THEN 32
                    WHEN 3 THEN 180
                    WHEN 4 THEN 250
                    ELSE 300
                END,
                DATEADD(DAY, -(@i % 620), GETDATE()),
                NULL,
                NULL
            );
        END;
    END;

    ------------------------------------------------------------
    -- Outbox event
    ------------------------------------------------------------
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
        N'APPLICATION_CREATED',
        N'applications',
        CAST(@AppId AS NVARCHAR(50)),
        CONCAT('{"source":"', @Prefix, '","entity":"applications","id":"', @AppId, '","run":"', @RunTag, '"}'),
        N'PENDING',
        DATEADD(DAY, -(@i % 610), GETDATE()),
        NULL
    );

    SET @i += 1;
END;

SELECT DB_NAME() AS source_db, 'beneficiaries' AS table_name, COUNT(*) AS rows_count FROM dbo.beneficiaries
UNION ALL SELECT DB_NAME(), 'applications', COUNT(*) FROM dbo.applications
UNION ALL SELECT DB_NAME(), 'cases', COUNT(*) FROM dbo.cases
UNION ALL SELECT DB_NAME(), 'donors', COUNT(*) FROM dbo.donors
UNION ALL SELECT DB_NAME(), 'donations', COUNT(*) FROM dbo.donations
UNION ALL SELECT DB_NAME(), 'inventory_transactions', COUNT(*) FROM dbo.inventory_transactions
UNION ALL SELECT DB_NAME(), 'beneficiary_documents', COUNT(*) FROM dbo.beneficiary_documents
UNION ALL SELECT DB_NAME(), 'source_event_outbox', COUNT(*) FROM dbo.source_event_outbox;
GO

"@
}

$sql = @()
$sql += New-SafeExpansionBlock -DbName "charity_food_bank_operational" -Prefix "FB" -OrgCode "101"
$sql += New-SafeExpansionBlock -DbName "charity_resala_operational" -Prefix "RES" -OrgCode "102"
$sql += New-SafeExpansionBlock -DbName "charity_haya_karima_operational" -Prefix "HK" -OrgCode "103"

$sql -join "`r`n" | Set-Content $SqlFile -Encoding UTF8

Write-Host "Safe expansion SQL created:"
Write-Host $SqlFile

docker cp $SqlFile "ucp_sqlserver:/tmp/expand_source_data_for_powerbi_safe.sql"

Write-Host "Running safe source data expansion..."
$output = docker exec ucp_sqlserver /opt/mssql-tools18/bin/sqlcmd `
  -C `
  -S localhost `
  -U sa `
  -P "ChangeMe_StrongPassword_2026!" `
  -i /tmp/expand_source_data_for_powerbi_safe.sql

$output | Tee-Object -FilePath $ResultFile

if ($output -match "Msg ") {
    Write-Host ""
    Write-Host "ERROR detected in SQL output. Stop here and send me the output."
    exit 1
}

Write-Host ""
Write-Host "Safe source operational databases expanded successfully."
Write-Host "New beneficiaries per organization: $NewBeneficiariesPerOrg"

if ($SkipPipeline) {
    Write-Host "SkipPipeline is enabled. Data was inserted into source DBs only."
    exit 0
}

Write-Host ""
Write-Host "Waiting for CDC/Debezium/Kafka to capture new changes..."
Start-Sleep -Seconds 60

Write-Host "Re-running DE pipeline from Bronze to Power BI..."

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

Write-Host ""
Write-Host "SAFE Power BI data expansion completed successfully."
Write-Host "Now refresh Power BI Desktop."

