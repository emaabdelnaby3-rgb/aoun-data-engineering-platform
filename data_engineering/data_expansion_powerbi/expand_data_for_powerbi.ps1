param(
    [int]$NewBeneficiariesPerOrg = 5000,
    [switch]$SkipPipeline
)

$ErrorActionPreference = "Stop"

$BaseDir = ".\data_engineering\data_expansion_powerbi"
$SqlFile = "$BaseDir\sql\expand_source_data_for_powerbi.sql"

New-Item -ItemType Directory -Force -Path "$BaseDir\sql" | Out-Null
New-Item -ItemType Directory -Force -Path "$BaseDir\results" | Out-Null

function New-ExpansionBlock {
    param(
        [string]$DbName,
        [string]$Prefix
    )

@"
USE [$DbName];
GO

SET NOCOUNT ON;

DECLARE @Rows INT = $NewBeneficiariesPerOrg;
DECLARE @Prefix NVARCHAR(20) = N'$Prefix';

DECLARE @BenStart INT = ISNULL((SELECT MAX(source_beneficiary_id) FROM dbo.beneficiaries), 0) + 1;
DECLARE @AppStart INT = ISNULL((SELECT MAX(source_application_id) FROM dbo.applications), 0) + 1;
DECLARE @CaseStart INT = ISNULL((SELECT MAX(source_case_id) FROM dbo.cases), 0) + 1;
DECLARE @DonorStart INT = ISNULL((SELECT MAX(source_donor_id) FROM dbo.donors), 0) + 1;
DECLARE @DonationStart INT = ISNULL((SELECT MAX(source_donation_id) FROM dbo.donations), 0) + 1;
DECLARE @DocStart INT = ISNULL((SELECT MAX(source_document_id) FROM dbo.beneficiary_documents), 0) + 1;
DECLARE @InvStart INT = ISNULL((SELECT MAX(source_inventory_transaction_id) FROM dbo.inventory_transactions), 0) + 1;
DECLARE @OutboxStart INT = ISNULL((SELECT MAX(source_event_id) FROM dbo.source_event_outbox), 0) + 1;

DECLARE @NewDonors INT = CASE WHEN @Rows / 2 < 100 THEN 100 ELSE @Rows / 2 END;

PRINT 'Expanding source data for $DbName';

------------------------------------------------------------
-- Donors
------------------------------------------------------------
SET IDENTITY_INSERT dbo.donors ON;

DECLARE @i INT = 1;
WHILE @i <= @NewDonors
BEGIN
    DECLARE @DonorId INT = @DonorStart + @i - 1;

    INSERT INTO dbo.donors
    (
        source_donor_id,
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
        @DonorId,
        CONCAT(@Prefix, N'-DONOR-EXP-', RIGHT('000000' + CAST(@DonorId AS VARCHAR(20)), 6)),
        CONCAT(N'Donor ', @Prefix, N' ', @DonorId),
        CONCAT('010', RIGHT('00000000' + CAST(ABS(CHECKSUM(NEWID())) % 100000000 AS VARCHAR(8)), 8)),
        CONCAT('donor', @DonorId, '.', LOWER(@Prefix), '@example.com'),
        CASE @DonorId % 4
            WHEN 0 THEN N'Individual'
            WHEN 1 THEN N'Corporate'
            WHEN 2 THEN N'Monthly Donor'
            ELSE N'Anonymous'
        END,
        DATEADD(DAY, -(@DonorId % 720), GETDATE()),
        NULL
    );

    SET @i += 1;
END

SET IDENTITY_INSERT dbo.donors OFF;
GO

------------------------------------------------------------
-- Beneficiaries
------------------------------------------------------------
SET IDENTITY_INSERT dbo.beneficiaries ON;

DECLARE @Rows INT = $NewBeneficiariesPerOrg;
DECLARE @Prefix NVARCHAR(20) = N'$Prefix';
DECLARE @BenStart INT = ISNULL((SELECT MAX(source_beneficiary_id) FROM dbo.beneficiaries), 0) + 1 - @Rows;
DECLARE @i INT = 1;

WHILE @i <= @Rows
BEGIN
    DECLARE @BenId INT = @BenStart + @i - 1;

    INSERT INTO dbo.beneficiaries
    (
        source_beneficiary_id,
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
        @BenId,
        CONCAT('3', RIGHT('0000000000000' + CAST(ABS(CHECKSUM(NEWID())) AS VARCHAR(20)), 13)),
        CONCAT(N'Beneficiary ', @Prefix, N' ', @BenId),
        CASE WHEN @BenId % 2 = 0 THEN N'Female' ELSE N'Male' END,
        DATEFROMPARTS(1960 + (@BenId % 45), 1 + (@BenId % 12), 1 + (@BenId % 28)),
        CONCAT('011', RIGHT('00000000' + CAST(ABS(CHECKSUM(NEWID())) % 100000000 AS VARCHAR(8)), 8)),
        CASE WHEN @BenId % 5 = 0 THEN CONCAT('beneficiary', @BenId, '.', LOWER(@Prefix), '@example.com') ELSE NULL END,
        CASE @BenId % 12
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
        CASE @BenId % 8
            WHEN 0 THEN N'Nasr City'
            WHEN 1 THEN N'Dokki'
            WHEN 2 THEN N'Mansoura'
            WHEN 3 THEN N'Zagazig'
            WHEN 4 THEN N'Tanta'
            WHEN 5 THEN N'Minya'
            WHEN 6 THEN N'Assiut'
            ELSE N'Aswan'
        END,
        CONCAT(@BenId % 120 + 1, N' Main Street'),
        1 + (@BenId % 8),
        CASE @BenId % 8
            WHEN 0 THEN 0
            WHEN 1 THEN 500
            WHEN 2 THEN 800
            WHEN 3 THEN 1200
            WHEN 4 THEN 1800
            WHEN 5 THEN 2500
            WHEN 6 THEN 3500
            ELSE 4500
        END,
        CASE @BenId % 6
            WHEN 0 THEN N'Unemployed'
            WHEN 1 THEN N'Daily Worker'
            WHEN 2 THEN N'Part Time'
            WHEN 3 THEN N'Retired'
            WHEN 4 THEN N'Housewife'
            ELSE N'Unable to Work'
        END,
        DATEADD(DAY, -(@BenId % 720), GETDATE()),
        NULL
    );

    SET @i += 1;
END

SET IDENTITY_INSERT dbo.beneficiaries OFF;
GO

------------------------------------------------------------
-- Applications, cases, donations, documents, inventory, outbox
------------------------------------------------------------
SET IDENTITY_INSERT dbo.applications ON;
SET IDENTITY_INSERT dbo.applications OFF;
GO

DECLARE @Rows INT = $NewBeneficiariesPerOrg;
DECLARE @Prefix NVARCHAR(20) = N'$Prefix';

DECLARE @BenStart INT = ISNULL((SELECT MAX(source_beneficiary_id) FROM dbo.beneficiaries), 0) - @Rows + 1;
DECLARE @AppId INT = ISNULL((SELECT MAX(source_application_id) FROM dbo.applications), 0) + 1;
DECLARE @CaseId INT = ISNULL((SELECT MAX(source_case_id) FROM dbo.cases), 0) + 1;
DECLARE @DonationId INT = ISNULL((SELECT MAX(source_donation_id) FROM dbo.donations), 0) + 1;
DECLARE @DocId INT = ISNULL((SELECT MAX(source_document_id) FROM dbo.beneficiary_documents), 0) + 1;
DECLARE @InvId INT = ISNULL((SELECT MAX(source_inventory_transaction_id) FROM dbo.inventory_transactions), 0) + 1;
DECLARE @OutboxId INT = ISNULL((SELECT MAX(source_event_id) FROM dbo.source_event_outbox), 0) + 1;
DECLARE @DonorMin INT = ISNULL((SELECT MIN(source_donor_id) FROM dbo.donors), 1);
DECLARE @DonorMax INT = ISNULL((SELECT MAX(source_donor_id) FROM dbo.donors), 1);

DECLARE @i INT = 1;

WHILE @i <= @Rows
BEGIN
    DECLARE @BenId INT = @BenStart + @i - 1;
    DECLARE @BranchId INT = 1 + (@BenId % 6);
    DECLARE @RequestedAmount DECIMAL(18,2) =
        CASE @BenId % 7
            WHEN 0 THEN 800
            WHEN 1 THEN 1200
            WHEN 2 THEN 2000
            WHEN 3 THEN 3500
            WHEN 4 THEN 5000
            WHEN 5 THEN 8000
            ELSE 12000
        END;

    DECLARE @SupportType NVARCHAR(100) =
        CASE @BenId % 10
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

    DECLARE @ApplicationStatus NVARCHAR(50) =
        CASE
            WHEN @BenId % 10 IN (0,1,2,3,4,5) THEN N'APPROVED'
            WHEN @BenId % 10 IN (6,7) THEN N'UNDER_REVIEW'
            WHEN @BenId % 10 = 8 THEN N'SUBMITTED'
            ELSE N'REJECTED'
        END;

    SET IDENTITY_INSERT dbo.applications ON;

    INSERT INTO dbo.applications
    (
        source_application_id,
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
        @AppId,
        CONCAT(@Prefix, N'-APP-EXP-', RIGHT('000000' + CAST(@AppId AS VARCHAR(20)), 6)),
        @BenId,
        @BranchId,
        @SupportType,
        @RequestedAmount,
        @ApplicationStatus,
        CASE
            WHEN @RequestedAmount >= 8000 THEN N'CRITICAL'
            WHEN @BenId % 4 = 0 THEN N'HIGH'
            WHEN @BenId % 4 = 1 THEN N'MEDIUM'
            ELSE N'LOW'
        END,
        DATEADD(DAY, -(@BenId % 720), GETDATE()),
        CASE WHEN @ApplicationStatus IN (N'APPROVED', N'REJECTED') THEN DATEADD(DAY, -(@BenId % 700), GETDATE()) ELSE NULL END,
        CASE @BenId % 4
            WHEN 0 THEN N'Needs home visit'
            WHEN 1 THEN N'Documents verified'
            WHEN 2 THEN N'Urgent family support'
            ELSE N'Branch review completed'
        END,
        NULL
    );

    SET IDENTITY_INSERT dbo.applications OFF;

    SET IDENTITY_INSERT dbo.beneficiary_documents ON;

    INSERT INTO dbo.beneficiary_documents
    (
        source_document_id,
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
        @DocId,
        @BenId,
        @AppId,
        N'National ID',
        CONCAT(LOWER(@Prefix), '_exp_', @BenId, '_national_id.pdf'),
        CONCAT('source-documents/', @Prefix, '/', @BenId, '/', @DocId, '.pdf'),
        CONCAT('minio://charity-documents/source-documents/', @Prefix, '/', @BenId, '/', @DocId, '.pdf'),
        CASE WHEN @BenId % 7 = 0 THEN N'PENDING' ELSE N'VERIFIED' END,
        DATEADD(DAY, -(@BenId % 710), GETDATE()),
        NULL
    );

    SET @DocId += 1;

    INSERT INTO dbo.beneficiary_documents
    (
        source_document_id,
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
        @DocId,
        @BenId,
        @AppId,
        CASE WHEN @BenId % 2 = 0 THEN N'Income Proof' ELSE N'Family Certificate' END,
        CONCAT(LOWER(@Prefix), '_exp_', @BenId, '_support.pdf'),
        CONCAT('source-documents/', @Prefix, '/', @BenId, '/', @DocId, '.pdf'),
        CONCAT('minio://charity-documents/source-documents/', @Prefix, '/', @BenId, '/', @DocId, '.pdf'),
        CASE WHEN @BenId % 11 = 0 THEN N'PENDING' ELSE N'VERIFIED' END,
        DATEADD(DAY, -(@BenId % 710), GETDATE()),
        NULL
    );

    SET @DocId += 1;

    SET IDENTITY_INSERT dbo.beneficiary_documents OFF;

    IF @ApplicationStatus = N'APPROVED'
    BEGIN
        DECLARE @CollectedAmount DECIMAL(18,2) =
            CASE
                WHEN @BenId % 5 = 0 THEN @RequestedAmount
                WHEN @BenId % 5 = 1 THEN @RequestedAmount * 0.75
                WHEN @BenId % 5 = 2 THEN @RequestedAmount * 0.50
                WHEN @BenId % 5 = 3 THEN @RequestedAmount * 0.25
                ELSE 0
            END;

        SET IDENTITY_INSERT dbo.cases ON;

        INSERT INTO dbo.cases
        (
            source_case_id,
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
            @CaseId,
            CONCAT(@Prefix, N'-CASE-EXP-', RIGHT('000000' + CAST(@CaseId AS VARCHAR(20)), 6)),
            @AppId,
            @BenId,
            @BranchId,
            CONCAT(@SupportType, N' case for beneficiary ', @BenId),
            @SupportType,
            CASE
                WHEN @CollectedAmount >= @RequestedAmount THEN N'FUNDED'
                WHEN @BenId % 3 = 0 THEN N'PUBLISHED'
                ELSE N'OPEN'
            END,
            @RequestedAmount,
            @CollectedAmount,
            DATEADD(DAY, -(@BenId % 690), GETDATE()),
            CASE WHEN @CollectedAmount >= @RequestedAmount THEN DATEADD(DAY, -(@BenId % 650), GETDATE()) ELSE NULL END,
            NULL
        );

        SET IDENTITY_INSERT dbo.cases OFF;

        DECLARE @DonationLoops INT = CASE WHEN @BenId % 3 = 0 THEN 3 ELSE 2 END;
        DECLARE @d INT = 1;

        WHILE @d <= @DonationLoops
        BEGIN
            SET IDENTITY_INSERT dbo.donations ON;

            INSERT INTO dbo.donations
            (
                source_donation_id,
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
                @DonationId,
                CONCAT(@Prefix, N'-DON-EXP-', RIGHT('00000000' + CAST(@DonationId AS VARCHAR(20)), 8)),
                @DonorMin + ((@DonationId - @DonorMin) % NULLIF(@DonorMax - @DonorMin + 1, 0)),
                @CaseId,
                @BranchId,
                CASE @DonationId % 7
                    WHEN 0 THEN 100
                    WHEN 1 THEN 150
                    WHEN 2 THEN 250
                    WHEN 3 THEN 500
                    WHEN 4 THEN 750
                    WHEN 5 THEN 1000
                    ELSE 2000
                END,
                CASE @DonationId % 5
                    WHEN 0 THEN N'Cash'
                    WHEN 1 THEN N'Visa'
                    WHEN 2 THEN N'Bank Transfer'
                    WHEN 3 THEN N'Fawry'
                    ELSE N'Vodafone Cash'
                END,
                CASE WHEN @DonationId % 20 = 0 THEN N'REFUNDED' ELSE N'COMPLETED' END,
                DATEADD(DAY, -(@DonationId % 680), GETDATE()),
                NULL,
                NULL
            );

            SET IDENTITY_INSERT dbo.donations OFF;

            SET @DonationId += 1;
            SET @d += 1;
        END

        IF @BenId % 2 = 0
        BEGIN
            SET IDENTITY_INSERT dbo.inventory_transactions ON;

            INSERT INTO dbo.inventory_transactions
            (
                source_inventory_transaction_id,
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
                @InvId,
                CONCAT(@Prefix, N'-INV-EXP-', RIGHT('00000000' + CAST(@InvId AS VARCHAR(20)), 8)),
                @BranchId,
                1 + (@BenId % 6),
                @CaseId,
                CASE WHEN @BenId % 8 = 0 THEN N'IN' ELSE N'OUT' END,
                1 + (@BenId % 5),
                CASE @BenId % 6
                    WHEN 0 THEN 35
                    WHEN 1 THEN 70
                    WHEN 2 THEN 32
                    WHEN 3 THEN 180
                    WHEN 4 THEN 250
                    ELSE 300
                END,
                DATEADD(DAY, -(@BenId % 670), GETDATE()),
                NULL,
                NULL
            );

            SET IDENTITY_INSERT dbo.inventory_transactions OFF;

            SET @InvId += 1;
        END

        SET @CaseId += 1;
    END

    SET IDENTITY_INSERT dbo.source_event_outbox ON;

    INSERT INTO dbo.source_event_outbox
    (
        source_event_id,
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
        @OutboxId,
        NEWID(),
        N'APPLICATION_CREATED',
        N'applications',
        CAST(@AppId AS NVARCHAR(50)),
        CONCAT('{"source":"', @Prefix, '","entity":"applications","id":"', @AppId, '"}'),
        N'PENDING',
        DATEADD(DAY, -(@AppId % 720), GETDATE()),
        NULL
    );

    SET IDENTITY_INSERT dbo.source_event_outbox OFF;

    SET @OutboxId += 1;
    SET @AppId += 1;
    SET @i += 1;
END
GO

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
$sql += "SET NOCOUNT ON;"
$sql += "GO"
$sql += New-ExpansionBlock -DbName "charity_food_bank_operational" -Prefix "FB"
$sql += New-ExpansionBlock -DbName "charity_resala_operational" -Prefix "RES"
$sql += New-ExpansionBlock -DbName "charity_haya_karima_operational" -Prefix "HK"

$sql -join "`r`n" | Set-Content $SqlFile -Encoding UTF8

Write-Host "Expansion SQL created:"
Write-Host $SqlFile

Write-Host "Copying SQL expansion script to SQL Server container..."
docker cp $SqlFile "ucp_sqlserver:/tmp/expand_source_data_for_powerbi.sql"

Write-Host "Running source data expansion..."
docker exec ucp_sqlserver /opt/mssql-tools18/bin/sqlcmd `
  -C `
  -S localhost `
  -U sa `
  -P "ChangeMe_StrongPassword_2026!" `
  -i /tmp/expand_source_data_for_powerbi.sql

Write-Host ""
Write-Host "Source operational databases expanded successfully."
Write-Host "New beneficiaries per organization: $NewBeneficiariesPerOrg"
Write-Host ""

if ($SkipPipeline) {
    Write-Host "SkipPipeline is enabled. Data was inserted into source DBs only."
    exit 0
}

Write-Host "Waiting for CDC/Debezium/Kafka to capture new changes..."
Start-Sleep -Seconds 45

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

powershell -ExecutionPolicy Bypass -File .\data_engineering\de15_observability_monitoring\collect_de15_observability.ps1
powershell -ExecutionPolicy Bypass -File .\data_engineering\de15_observability_monitoring\validate_de15_observability.ps1

powershell -ExecutionPolicy Bypass -File .\data_engineering\de16_data_governance\generate_de16_data_governance.ps1
powershell -ExecutionPolicy Bypass -File .\data_engineering\de16_data_governance\validate_de16_data_governance.ps1

powershell -ExecutionPolicy Bypass -File .\data_engineering\de17_powerbi_analytics\run_de17_powerbi_analytics.ps1
powershell -ExecutionPolicy Bypass -File .\data_engineering\de17_powerbi_analytics\validate_de17_powerbi_analytics.ps1

Write-Host ""
Write-Host "Power BI data expansion completed successfully."
Write-Host "Now refresh Power BI Desktop."

