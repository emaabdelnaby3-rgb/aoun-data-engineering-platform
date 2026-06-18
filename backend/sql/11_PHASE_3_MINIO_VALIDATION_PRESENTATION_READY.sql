/* ============================================================
   PHASE 3 - Presentation Ready Additions
   Run after:
     00_ALL_IN_ONE_unified_charity_platform_clean.sql
     10_PHASE_2_BUSINESS_SCHEMA.sql

   Adds:
   - Extra document types used by the Arabic UI
   - Safer document upload constraints/indexes
   - Presentation-friendly storage metadata checks
   ============================================================ */

USE unified_charity_platform_clean;
GO

/* Extra document types used in the beneficiary upload page */
MERGE dbo.document_types AS t
USING (VALUES
    (N'NATIONAL_ID', N'صورة البطاقة', N'National ID', 1),
    (N'INCOME_PROOF', N'إثبات دخل', N'Income Proof', 1),
    (N'MEDICAL_REPORT', N'تقرير طبي', N'Medical Report', 0),
    (N'RENT_RECEIPT', N'إيصال إيجار', N'Rent Receipt', 0),
    (N'CHILD_BIRTH_CERT', N'شهادة ميلاد الأطفال', N'Children Birth Certificate', 0)
) AS s(document_type_code, document_type_name_ar, document_type_name_en, is_required_by_default)
ON t.document_type_code = s.document_type_code
WHEN MATCHED THEN UPDATE SET
    document_type_name_ar = s.document_type_name_ar,
    document_type_name_en = s.document_type_name_en,
    is_required_by_default = s.is_required_by_default
WHEN NOT MATCHED THEN
    INSERT (document_type_code, document_type_name_ar, document_type_name_en, is_required_by_default)
    VALUES (s.document_type_code, s.document_type_name_ar, s.document_type_name_en, s.is_required_by_default);
GO

/* Make sure document storage columns are available even if an older DB was used */
IF COL_LENGTH('dbo.beneficiary_documents', 'bucket_name') IS NULL
    ALTER TABLE dbo.beneficiary_documents ADD bucket_name NVARCHAR(200) NULL;
GO
IF COL_LENGTH('dbo.beneficiary_documents', 'object_key') IS NULL
    ALTER TABLE dbo.beneficiary_documents ADD object_key NVARCHAR(1000) NULL;
GO
IF COL_LENGTH('dbo.beneficiary_documents', 'storage_path') IS NULL
    ALTER TABLE dbo.beneficiary_documents ADD storage_path NVARCHAR(1000) NULL;
GO
IF COL_LENGTH('dbo.beneficiary_documents', 'file_url') IS NULL
    ALTER TABLE dbo.beneficiary_documents ADD file_url NVARCHAR(1000) NULL;
GO
IF COL_LENGTH('dbo.beneficiary_documents', 'content_type') IS NULL
    ALTER TABLE dbo.beneficiary_documents ADD content_type NVARCHAR(200) NULL;
GO
IF COL_LENGTH('dbo.beneficiary_documents', 'file_size_kb') IS NULL
    ALTER TABLE dbo.beneficiary_documents ADD file_size_kb DECIMAL(18,2) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_documents_application_status' AND object_id = OBJECT_ID('dbo.beneficiary_documents'))
    CREATE INDEX ix_documents_application_status ON dbo.beneficiary_documents(application_id, document_status, uploaded_at DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_documents_object_key' AND object_id = OBJECT_ID('dbo.beneficiary_documents'))
    CREATE INDEX ix_documents_object_key ON dbo.beneficiary_documents(object_key) WHERE object_key IS NOT NULL;
GO

/* Helpful view for admin document review */
CREATE OR ALTER VIEW dbo.v_admin_document_review AS
SELECT
    d.document_id,
    d.document_code,
    d.application_id,
    ba.application_code,
    d.case_id,
    d.beneficiary_id,
    bp.full_name,
    bp.national_id,
    o.organization_id,
    o.organization_name_ar,
    dt.document_type_code,
    dt.document_type_name_ar,
    d.original_file_name,
    d.stored_file_name,
    d.content_type,
    d.file_size_kb,
    d.bucket_name,
    d.object_key,
    d.storage_path,
    d.file_url,
    d.document_status,
    d.uploaded_at,
    d.verified_at
FROM dbo.beneficiary_documents d
JOIN dbo.beneficiary_profiles bp ON bp.beneficiary_id = d.beneficiary_id
LEFT JOIN dbo.beneficiary_applications ba ON ba.application_id = d.application_id
LEFT JOIN dbo.organizations o ON o.organization_id = COALESCE(ba.organization_id, (SELECT TOP 1 organization_id FROM dbo.charity_cases c WHERE c.case_id = d.case_id))
LEFT JOIN dbo.document_types dt ON dt.document_type_id = d.document_type_id;
GO

PRINT 'PHASE 3 MinIO + validation presentation additions installed successfully.';
GO
