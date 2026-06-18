USE charity_dwh;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'analytics_clean')
BEGIN
    EXEC('CREATE SCHEMA analytics_clean');
END
GO

IF OBJECT_ID('analytics_clean.null_profile_snapshot', 'U') IS NOT NULL
    DROP TABLE analytics_clean.null_profile_snapshot;
GO

CREATE TABLE analytics_clean.null_profile_snapshot
(
    profile_id INT IDENTITY(1,1) PRIMARY KEY,
    source_table SYSNAME NOT NULL,
    column_name SYSNAME NOT NULL,
    data_type SYSNAME NOT NULL,
    total_rows BIGINT NOT NULL,
    non_null_rows BIGINT NOT NULL,
    null_rows BIGINT NOT NULL,
    null_percentage DECIMAL(6,2) NOT NULL,
    included_in_clean_view BIT NOT NULL,
    action_taken NVARCHAR(200) NOT NULL,
    profiled_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

DECLARE @Tables TABLE
(
    source_schema SYSNAME,
    source_table SYSNAME,
    clean_view SYSNAME
);

INSERT INTO @Tables VALUES
('gold', 'dim_organization', 'v_dim_organization'),
('gold', 'dim_beneficiary', 'v_dim_beneficiary'),
('gold', 'dim_donor', 'v_dim_donor'),
('gold', 'fact_applications', 'v_fact_applications'),
('gold', 'fact_cases', 'v_fact_cases'),
('gold', 'fact_donations', 'v_fact_donations'),
('gold', 'fact_inventory_transactions', 'v_fact_inventory_transactions');

DECLARE
    @SourceSchema SYSNAME,
    @SourceTable SYSNAME,
    @CleanView SYSNAME,
    @TotalRows BIGINT,
    @ColumnName SYSNAME,
    @DataType SYSNAME,
    @NonNullRows BIGINT,
    @NullRows BIGINT,
    @NullPct DECIMAL(6,2),
    @SelectList NVARCHAR(MAX),
    @Expr NVARCHAR(MAX),
    @Sql NVARCHAR(MAX),
    @Action NVARCHAR(200),
    @Included BIT;

DECLARE table_cursor CURSOR FOR
SELECT source_schema, source_table, clean_view
FROM @Tables;

OPEN table_cursor;

FETCH NEXT FROM table_cursor INTO @SourceSchema, @SourceTable, @CleanView;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @TotalRows = 0;
    SET @SelectList = N'';

    SET @Sql = N'SELECT @cnt = COUNT_BIG(*) FROM '
        + QUOTENAME(@SourceSchema) + N'.' + QUOTENAME(@SourceTable);

    EXEC sp_executesql @Sql, N'@cnt BIGINT OUTPUT', @cnt = @TotalRows OUTPUT;

    DECLARE column_cursor CURSOR FOR
    SELECT
        c.name AS column_name,
        t.name AS data_type
    FROM sys.columns c
    JOIN sys.types t ON c.user_type_id = t.user_type_id
    WHERE c.object_id = OBJECT_ID(QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable))
    ORDER BY c.column_id;

    OPEN column_cursor;

    FETCH NEXT FROM column_cursor INTO @ColumnName, @DataType;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @NonNullRows = 0;

        SET @Sql = N'SELECT @cnt = SUM(CASE WHEN ' + QUOTENAME(@ColumnName) + N' IS NULL THEN 0 ELSE 1 END) FROM '
            + QUOTENAME(@SourceSchema) + N'.' + QUOTENAME(@SourceTable);

        EXEC sp_executesql @Sql, N'@cnt BIGINT OUTPUT', @cnt = @NonNullRows OUTPUT;

        SET @NonNullRows = COALESCE(@NonNullRows, 0);
        SET @NullRows = @TotalRows - @NonNullRows;
        SET @NullPct = CASE WHEN @TotalRows = 0 THEN 0 ELSE CAST((@NullRows * 100.0 / @TotalRows) AS DECIMAL(6,2)) END;

        IF @NonNullRows = 0
        BEGIN
            SET @Included = 0;
            SET @Action = N'Dropped from clean Power BI view because column is 100% NULL';
        END
        ELSE
        BEGIN
            SET @Included = 1;

            IF @DataType IN ('varchar', 'nvarchar', 'char', 'nchar', 'text', 'ntext')
            BEGIN
                SET @Expr =
                    N'COALESCE(NULLIF(LTRIM(RTRIM(CAST(' + QUOTENAME(@ColumnName) + N' AS NVARCHAR(4000)))), N''''), N''Unknown'') AS '
                    + QUOTENAME(@ColumnName);

                SET @Action = N'Kept and replaced NULL/blank text values with Unknown';
            END
            ELSE IF @DataType IN ('int', 'bigint', 'smallint', 'tinyint', 'decimal', 'numeric', 'float', 'real', 'money', 'smallmoney')
                AND @ColumnName NOT LIKE '%[_]sk'
                AND @ColumnName NOT LIKE '%[_]key'
                AND @ColumnName NOT LIKE '%[_]id'
                AND @ColumnName NOT LIKE 'source%id'
            BEGIN
                SET @Expr = N'COALESCE(' + QUOTENAME(@ColumnName) + N', 0) AS ' + QUOTENAME(@ColumnName);
                SET @Action = N'Kept and replaced numeric NULL values with 0';
            END
            ELSE IF @DataType = 'bit'
            BEGIN
                SET @Expr = N'COALESCE(' + QUOTENAME(@ColumnName) + N', CONVERT(bit, 0)) AS ' + QUOTENAME(@ColumnName);
                SET @Action = N'Kept and replaced BIT NULL values with 0';
            END
            ELSE
            BEGIN
                SET @Expr = QUOTENAME(@ColumnName);
                SET @Action = N'Kept as-is because it is a key, date, ID, or technical column';
            END

            SET @SelectList =
                CASE
                    WHEN LEN(@SelectList) = 0 THEN @Expr
                    ELSE @SelectList + N',' + CHAR(13) + CHAR(10) + N'    ' + @Expr
                END;
        END

        INSERT INTO analytics_clean.null_profile_snapshot
        (
            source_table,
            column_name,
            data_type,
            total_rows,
            non_null_rows,
            null_rows,
            null_percentage,
            included_in_clean_view,
            action_taken
        )
        VALUES
        (
            @SourceSchema + N'.' + @SourceTable,
            @ColumnName,
            @DataType,
            @TotalRows,
            @NonNullRows,
            @NullRows,
            @NullPct,
            @Included,
            @Action
        );

        FETCH NEXT FROM column_cursor INTO @ColumnName, @DataType;
    END

    CLOSE column_cursor;
    DEALLOCATE column_cursor;

    SET @Sql =
        N'CREATE OR ALTER VIEW analytics_clean.' + QUOTENAME(@CleanView) + N' AS ' + CHAR(13) + CHAR(10) +
        N'SELECT ' + CHAR(13) + CHAR(10) +
        N'    ' + @SelectList + CHAR(13) + CHAR(10) +
        N'FROM ' + QUOTENAME(@SourceSchema) + N'.' + QUOTENAME(@SourceTable) + N';';

    EXEC sp_executesql @Sql;

    FETCH NEXT FROM table_cursor INTO @SourceSchema, @SourceTable, @CleanView;
END

CLOSE table_cursor;
DEALLOCATE table_cursor;
GO

CREATE OR ALTER VIEW analytics_clean.v_null_columns_dropped AS
SELECT
    source_table,
    column_name,
    data_type,
    total_rows,
    null_rows,
    null_percentage,
    action_taken
FROM analytics_clean.null_profile_snapshot
WHERE included_in_clean_view = 0;
GO

CREATE OR ALTER VIEW analytics_clean.v_null_profile AS
SELECT
    source_table,
    column_name,
    data_type,
    total_rows,
    non_null_rows,
    null_rows,
    null_percentage,
    included_in_clean_view,
    action_taken
FROM analytics_clean.null_profile_snapshot;
GO

CREATE OR ALTER VIEW analytics_clean.v_kpi_overview AS
SELECT
    COALESCE(total_organizations, 0) AS total_organizations,
    COALESCE(total_beneficiaries, 0) AS total_beneficiaries,
    COALESCE(total_donors, 0) AS total_donors,
    COALESCE(total_applications, 0) AS total_applications,
    COALESCE(total_cases, 0) AS total_cases,
    COALESCE(total_donations, 0) AS total_donations,
    COALESCE(total_inventory_transactions, 0) AS total_inventory_transactions,
    COALESCE(total_donation_amount, 0) AS total_donation_amount
FROM analytics.v_kpi_overview;
GO

CREATE OR ALTER VIEW analytics_clean.v_donation_summary_by_organization AS
SELECT
    organization_sk,
    COALESCE(donation_count, 0) AS donation_count,
    COALESCE(total_donation_amount, 0) AS total_donation_amount
FROM analytics.v_donation_summary_by_organization;
GO

CREATE OR ALTER VIEW analytics_clean.v_application_summary_by_organization AS
SELECT
    organization_sk,
    COALESCE(application_count, 0) AS application_count,
    COALESCE(avg_priority_score, 0) AS avg_priority_score
FROM analytics.v_application_summary_by_organization;
GO

CREATE OR ALTER VIEW analytics_clean.v_case_summary_by_organization AS
SELECT
    organization_sk,
    COALESCE(case_count, 0) AS case_count,
    COALESCE(total_target_amount, 0) AS total_target_amount,
    COALESCE(total_collected_amount, 0) AS total_collected_amount,
    COALESCE(avg_case_priority_score, 0) AS avg_case_priority_score
FROM analytics.v_case_summary_by_organization;
GO

CREATE OR ALTER VIEW analytics_clean.v_inventory_summary_by_organization AS
SELECT
    organization_sk,
    COALESCE(inventory_transaction_count, 0) AS inventory_transaction_count,
    COALESCE(total_quantity, 0) AS total_quantity
FROM analytics.v_inventory_summary_by_organization;
GO

PRINT 'analytics_clean semantic layer created successfully.';
GO
