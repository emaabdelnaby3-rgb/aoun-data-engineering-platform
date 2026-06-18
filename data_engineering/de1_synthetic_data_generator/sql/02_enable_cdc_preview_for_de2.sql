/*
DE-2 preview only — do NOT run until we start CDC/Debezium.
This shows what will be enabled later for SQL Server CDC.
*/
USE charity_food_bank_operational;
GO
-- EXEC sys.sp_cdc_enable_db;
-- EXEC sys.sp_cdc_enable_table @source_schema='dbo', @source_name='beneficiaries', @role_name=NULL, @supports_net_changes=1;
-- EXEC sys.sp_cdc_enable_table @source_schema='dbo', @source_name='applications', @role_name=NULL, @supports_net_changes=1;
-- EXEC sys.sp_cdc_enable_table @source_schema='dbo', @source_name='cases', @role_name=NULL, @supports_net_changes=1;
-- EXEC sys.sp_cdc_enable_table @source_schema='dbo', @source_name='donations', @role_name=NULL, @supports_net_changes=1;
-- EXEC sys.sp_cdc_enable_table @source_schema='dbo', @source_name='inventory_transactions', @role_name=NULL, @supports_net_changes=1;
-- EXEC sys.sp_cdc_enable_table @source_schema='dbo', @source_name='beneficiary_documents', @role_name=NULL, @supports_net_changes=1;
GO

USE charity_resala_operational;
GO
-- Same CDC commands will be enabled here in DE-2.
GO

USE charity_haya_karima_operational;
GO
-- Same CDC commands will be enabled here in DE-2.
GO
