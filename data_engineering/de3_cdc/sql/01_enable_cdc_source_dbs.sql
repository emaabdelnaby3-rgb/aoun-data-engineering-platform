USE master;
GO

DECLARE @dbs TABLE (db_name SYSNAME);
INSERT INTO @dbs VALUES
('charity_food_bank_operational'),
('charity_resala_operational'),
('charity_haya_karima_operational');

DECLARE @db SYSNAME;
DECLARE db_cursor CURSOR FOR SELECT db_name FROM @dbs;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @sql NVARCHAR(MAX);

    SET @sql = N'
    USE ' + QUOTENAME(@db) + N';

    IF (SELECT is_cdc_enabled FROM sys.databases WHERE name = DB_NAME()) = 0
    BEGIN
        EXEC sys.sp_cdc_enable_db;
    END;

    DECLARE @tables TABLE (table_name SYSNAME);
    INSERT INTO @tables VALUES
    (''beneficiaries''),
    (''applications''),
    (''cases''),
    (''donors''),
    (''donations''),
    (''inventory_items''),
    (''inventory_transactions''),
    (''beneficiary_documents''),
    (''source_event_outbox'');

    DECLARE @table SYSNAME;
    DECLARE table_cursor CURSOR FOR SELECT table_name FROM @tables;

    OPEN table_cursor;
    FETCH NEXT FROM table_cursor INTO @table;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF EXISTS (
            SELECT 1
            FROM sys.tables
            WHERE name = @table
              AND schema_id = SCHEMA_ID(''dbo'')
        )
        AND NOT EXISTS (
            SELECT 1
            FROM cdc.change_tables
            WHERE source_object_id = OBJECT_ID(''dbo.'' + @table)
        )
        BEGIN
            EXEC sys.sp_cdc_enable_table
                @source_schema = N''dbo'',
                @source_name = @table,
                @role_name = NULL,
                @supports_net_changes = 0;
        END;

        FETCH NEXT FROM table_cursor INTO @table;
    END;

    CLOSE table_cursor;
    DEALLOCATE table_cursor;
    ';

    EXEC sp_executesql @sql;
    FETCH NEXT FROM db_cursor INTO @db;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;
GO

PRINT 'CDC enabled for the three charity operational databases.';
GO
