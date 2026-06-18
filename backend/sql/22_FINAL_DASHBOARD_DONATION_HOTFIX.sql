USE unified_charity_platform_clean;
GO

/* Final hotfix: document review columns used by admin UI */
IF COL_LENGTH('dbo.beneficiary_documents', 'verified_at') IS NULL
    ALTER TABLE dbo.beneficiary_documents ADD verified_at DATETIME2(0) NULL;
GO
IF COL_LENGTH('dbo.beneficiary_documents', 'verification_status') IS NULL
    ALTER TABLE dbo.beneficiary_documents ADD verification_status NVARCHAR(50) NOT NULL DEFAULT N'PENDING';
GO
IF COL_LENGTH('dbo.beneficiary_documents', 'verification_notes') IS NULL
    ALTER TABLE dbo.beneficiary_documents ADD verification_notes NVARCHAR(500) NULL;
GO

/* Final hotfix: SQL Server allows only one NULL in a normal UNIQUE constraint.
   Make donation_code/idempotency_key unique only when not null. */
UPDATE dbo.donations
SET donation_code = CONCAT(N'DON-', RIGHT(CONCAT('000000', donation_id), 6))
WHERE donation_code IS NULL;
GO

DECLARE @sql_drop_uq NVARCHAR(MAX) = N'';
SELECT @sql_drop_uq = @sql_drop_uq + N'ALTER TABLE dbo.donations DROP CONSTRAINT ' + QUOTENAME(kc.name) + N';' + CHAR(10)
FROM sys.key_constraints kc
WHERE kc.parent_object_id = OBJECT_ID('dbo.donations')
  AND kc.type = 'UQ'
  AND EXISTS (
      SELECT 1
      FROM sys.index_columns ic
      JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
      WHERE ic.object_id = kc.parent_object_id
        AND ic.index_id = kc.unique_index_id
        AND c.name IN (N'donation_code', N'idempotency_key')
  );
IF LEN(@sql_drop_uq) > 0 EXEC sp_executesql @sql_drop_uq;
GO

DECLARE @sql_drop_ix NVARCHAR(MAX) = N'';
SELECT @sql_drop_ix = @sql_drop_ix + N'DROP INDEX ' + QUOTENAME(i.name) + N' ON dbo.donations;' + CHAR(10)
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID('dbo.donations')
  AND i.is_unique = 1
  AND i.is_primary_key = 0
  AND i.name NOT IN (N'ux_donations_donation_code_not_null', N'ux_donations_idempotency_key_not_null')
  AND EXISTS (
      SELECT 1
      FROM sys.index_columns ic
      JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
      WHERE ic.object_id = i.object_id
        AND ic.index_id = i.index_id
        AND c.name IN (N'donation_code', N'idempotency_key')
  );
IF LEN(@sql_drop_ix) > 0 EXEC sp_executesql @sql_drop_ix;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.donations') AND name = N'ux_donations_donation_code_not_null')
    CREATE UNIQUE INDEX ux_donations_donation_code_not_null ON dbo.donations(donation_code) WHERE donation_code IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.donations') AND name = N'ux_donations_idempotency_key_not_null')
    CREATE UNIQUE INDEX ux_donations_idempotency_key_not_null ON dbo.donations(idempotency_key) WHERE idempotency_key IS NOT NULL;
GO

CREATE OR ALTER TRIGGER dbo.trg_donations_generate_code
ON dbo.donations
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE d
    SET donation_code = CONCAT(N'DON-', RIGHT(CONCAT('000000', d.donation_id), 6))
    FROM dbo.donations d
    JOIN inserted i ON i.donation_id = d.donation_id
    WHERE d.donation_code IS NULL;
END;
GO

SELECT 'final_hotfix_ok' AS status;
GO
