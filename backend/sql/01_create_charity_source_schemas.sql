/*
================================================================================
Unified Charity Platform - Step 1
Create Three Independent Charity Source Schemas
================================================================================
Purpose:
    This script creates three simulated source systems inside the same SQL Server
    database. Each schema represents an independent charity operational system.

    1) src_food_bank      -> Food Bank source system
    2) src_resala         -> Resala source system
    3) src_haya_karima    -> Haya Karima source system

Why this step exists:
    The main data engineering pipeline must prove that data is integrated from
    multiple independent sources. These schemas intentionally use different table
    and column names so the Bronze -> Silver pipeline has a real standardization
    job to do.

Target database:
    unified_charity_platform_clean

Important:
    - This script DOES NOT touch or delete the platform dbo tables.
    - It only creates source schemas and source tables.
    - It is safe to run more than once because it checks whether objects exist.
================================================================================
*/

USE unified_charity_platform_clean;
GO

/*===============================================================================
0) CREATE SOURCE SCHEMAS
===============================================================================*/

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'src_food_bank')
    EXEC('CREATE SCHEMA src_food_bank');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'src_resala')
    EXEC('CREATE SCHEMA src_resala');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'src_haya_karima')
    EXEC('CREATE SCHEMA src_haya_karima');
GO

/*===============================================================================
1) FOOD BANK SOURCE SYSTEM
   Column style example:
   beneficiary_name, national_id, mobile, governorate, support_category
===============================================================================*/

IF OBJECT_ID('src_food_bank.beneficiaries', 'U') IS NULL
BEGIN
    CREATE TABLE src_food_bank.beneficiaries (
        fb_beneficiary_id INT IDENTITY(1,1) PRIMARY KEY,
        beneficiary_name NVARCHAR(200) NOT NULL,
        national_id NVARCHAR(20) NOT NULL,
        mobile NVARCHAR(30),
        city NVARCHAR(100),
        governorate NVARCHAR(100),
        family_members INT,
        monthly_income DECIMAL(12,2),
        created_at DATETIME2 DEFAULT SYSDATETIME()
    );
END;
GO

IF OBJECT_ID('src_food_bank.applications', 'U') IS NULL
BEGIN
    CREATE TABLE src_food_bank.applications (
        fb_application_id INT IDENTITY(1,1) PRIMARY KEY,
        national_id NVARCHAR(20) NOT NULL,
        application_date DATETIME2,
        support_category NVARCHAR(100),
        requested_amount DECIMAL(12,2),
        application_status NVARCHAR(50),
        notes NVARCHAR(500)
    );
END;
GO

IF OBJECT_ID('src_food_bank.cases', 'U') IS NULL
BEGIN
    CREATE TABLE src_food_bank.cases (
        fb_case_id INT IDENTITY(1,1) PRIMARY KEY,
        national_id NVARCHAR(20) NOT NULL,
        case_title NVARCHAR(200),
        support_category NVARCHAR(100),
        target_amount DECIMAL(12,2),
        collected_amount DECIMAL(12,2),
        case_status NVARCHAR(50),
        created_at DATETIME2
    );
END;
GO

IF OBJECT_ID('src_food_bank.donations', 'U') IS NULL
BEGIN
    CREATE TABLE src_food_bank.donations (
        fb_donation_id INT IDENTITY(1,1) PRIMARY KEY,
        national_id NVARCHAR(20) NULL,
        donor_name NVARCHAR(200),
        donor_mobile NVARCHAR(30),
        amount DECIMAL(12,2),
        payment_method NVARCHAR(100),
        donation_date DATETIME2
    );
END;
GO

IF OBJECT_ID('src_food_bank.inventory_transactions', 'U') IS NULL
BEGIN
    CREATE TABLE src_food_bank.inventory_transactions (
        fb_inventory_txn_id INT IDENTITY(1,1) PRIMARY KEY,
        national_id NVARCHAR(20) NULL,
        item_name NVARCHAR(200),
        quantity DECIMAL(12,2),
        transaction_type NVARCHAR(50),
        transaction_date DATETIME2
    );
END;
GO

/*===============================================================================
2) RESALA SOURCE SYSTEM
   Column style example:
   full_name, nid, phone_number, governorate_name, support_type
===============================================================================*/

IF OBJECT_ID('src_resala.beneficiary_records', 'U') IS NULL
BEGIN
    CREATE TABLE src_resala.beneficiary_records (
        resala_person_id INT IDENTITY(1,1) PRIMARY KEY,
        full_name NVARCHAR(200) NOT NULL,
        nid NVARCHAR(20) NOT NULL,
        phone_number NVARCHAR(30),
        area NVARCHAR(100),
        governorate_name NVARCHAR(100),
        household_size INT,
        income_value DECIMAL(12,2),
        inserted_on DATETIME2 DEFAULT SYSDATETIME()
    );
END;
GO

IF OBJECT_ID('src_resala.support_requests', 'U') IS NULL
BEGIN
    CREATE TABLE src_resala.support_requests (
        resala_request_id INT IDENTITY(1,1) PRIMARY KEY,
        nid NVARCHAR(20) NOT NULL,
        request_date DATETIME2,
        support_type NVARCHAR(100),
        amount_needed DECIMAL(12,2),
        request_status NVARCHAR(50),
        request_reason NVARCHAR(500)
    );
END;
GO

IF OBJECT_ID('src_resala.charity_cases', 'U') IS NULL
BEGIN
    CREATE TABLE src_resala.charity_cases (
        resala_case_id INT IDENTITY(1,1) PRIMARY KEY,
        nid NVARCHAR(20) NOT NULL,
        title NVARCHAR(200),
        support_type NVARCHAR(100),
        required_money DECIMAL(12,2),
        raised_money DECIMAL(12,2),
        status NVARCHAR(50),
        opened_at DATETIME2
    );
END;
GO

IF OBJECT_ID('src_resala.donation_payments', 'U') IS NULL
BEGIN
    CREATE TABLE src_resala.donation_payments (
        resala_donation_id INT IDENTITY(1,1) PRIMARY KEY,
        nid NVARCHAR(20) NULL,
        giver_name NVARCHAR(200),
        giver_phone NVARCHAR(30),
        paid_amount DECIMAL(12,2),
        pay_type NVARCHAR(100),
        paid_at DATETIME2
    );
END;
GO

IF OBJECT_ID('src_resala.stock_movements', 'U') IS NULL
BEGIN
    CREATE TABLE src_resala.stock_movements (
        resala_stock_id INT IDENTITY(1,1) PRIMARY KEY,
        nid NVARCHAR(20) NULL,
        product_name NVARCHAR(200),
        qty DECIMAL(12,2),
        movement_type NVARCHAR(50),
        movement_date DATETIME2
    );
END;
GO

/*===============================================================================
3) HAYA KARIMA SOURCE SYSTEM
   Column style example:
   person_name, national_code, contact_phone, gov, aid_type
===============================================================================*/

IF OBJECT_ID('src_haya_karima.people', 'U') IS NULL
BEGIN
    CREATE TABLE src_haya_karima.people (
        haya_person_id INT IDENTITY(1,1) PRIMARY KEY,
        person_name NVARCHAR(200) NOT NULL,
        national_code NVARCHAR(20) NOT NULL,
        contact_phone NVARCHAR(30),
        district NVARCHAR(100),
        gov NVARCHAR(100),
        family_count INT,
        income_monthly DECIMAL(12,2),
        registration_date DATETIME2 DEFAULT SYSDATETIME()
    );
END;
GO

IF OBJECT_ID('src_haya_karima.aid_applications', 'U') IS NULL
BEGIN
    CREATE TABLE src_haya_karima.aid_applications (
        haya_application_id INT IDENTITY(1,1) PRIMARY KEY,
        national_code NVARCHAR(20) NOT NULL,
        submitted_at DATETIME2,
        aid_type NVARCHAR(100),
        estimated_cost DECIMAL(12,2),
        current_status NVARCHAR(50),
        description NVARCHAR(500)
    );
END;
GO

IF OBJECT_ID('src_haya_karima.public_cases', 'U') IS NULL
BEGIN
    CREATE TABLE src_haya_karima.public_cases (
        haya_case_id INT IDENTITY(1,1) PRIMARY KEY,
        national_code NVARCHAR(20) NOT NULL,
        headline NVARCHAR(200),
        aid_type NVARCHAR(100),
        needed_amount DECIMAL(12,2),
        received_amount DECIMAL(12,2),
        case_state NVARCHAR(50),
        publish_date DATETIME2
    );
END;
GO

IF OBJECT_ID('src_haya_karima.donor_transactions', 'U') IS NULL
BEGIN
    CREATE TABLE src_haya_karima.donor_transactions (
        haya_donation_id INT IDENTITY(1,1) PRIMARY KEY,
        national_code NVARCHAR(20) NULL,
        donor_full_name NVARCHAR(200),
        donor_contact NVARCHAR(30),
        donation_value DECIMAL(12,2),
        payment_channel NVARCHAR(100),
        transaction_time DATETIME2
    );
END;
GO

IF OBJECT_ID('src_haya_karima.aid_stock_logs', 'U') IS NULL
BEGIN
    CREATE TABLE src_haya_karima.aid_stock_logs (
        haya_stock_log_id INT IDENTITY(1,1) PRIMARY KEY,
        national_code NVARCHAR(20) NULL,
        aid_item NVARCHAR(200),
        item_count DECIMAL(12,2),
        log_type NVARCHAR(50),
        log_date DATETIME2
    );
END;
GO

/*===============================================================================
4) VERIFICATION QUERIES
===============================================================================*/

PRINT 'Step 1 completed: source schemas and source tables are ready.';

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    SUM(p.rows) AS approx_rows
FROM sys.tables t
JOIN sys.schemas s
    ON t.schema_id = s.schema_id
JOIN sys.partitions p
    ON t.object_id = p.object_id
WHERE s.name IN ('src_food_bank', 'src_resala', 'src_haya_karima')
  AND p.index_id IN (0, 1)
GROUP BY s.name, t.name
ORDER BY s.name, t.name;
GO

/*
Expected result:
    You should see 15 tables total:
        5 tables in src_food_bank
        5 tables in src_resala
        5 tables in src_haya_karima

Next step:
    Step 2 will insert smart seed data into these three source systems.
================================================================================
*/
