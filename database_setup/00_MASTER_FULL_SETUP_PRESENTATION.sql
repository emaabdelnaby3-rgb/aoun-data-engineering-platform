/* ==============================================================================
   Unified Charity Platform - MASTER FULL DATABASE SETUP FOR PRESENTATION
   Creates/updates the professional architecture:
     1) charity_food_bank_operational
     2) charity_resala_operational
     3) charity_haya_karima_operational
     4) unified_charity_platform_clean
     5) charity_dwh

   Run this single file in SSMS as admin.
   IMPORTANT: the included clean platform script rebuilds unified_charity_platform_clean.
   ============================================================================== */



/* ==============================================================================
   START INCLUDED FILE: 00_create_architecture_databases.sql
   ============================================================================== */

/*
================================================================================
Unified Charity Platform - Architecture Database Setup
================================================================================
This script creates the physical databases that match the end-to-end architecture:

1) charity_food_bank_operational      -> Food Bank independent OLTP source DB
2) charity_resala_operational         -> Resala independent OLTP source DB
3) charity_haya_karima_operational    -> Haya Karima independent OLTP source DB
4) unified_charity_platform_clean     -> Existing platform serving/operational DB
5) charity_dwh                        -> Analytical Data Warehouse star schema

Run this script as a SQL Server admin user.
================================================================================
*/

USE master;
GO

IF DB_ID(N'charity_food_bank_operational') IS NULL
    CREATE DATABASE charity_food_bank_operational;
GO

IF DB_ID(N'charity_resala_operational') IS NULL
    CREATE DATABASE charity_resala_operational;
GO

IF DB_ID(N'charity_haya_karima_operational') IS NULL
    CREATE DATABASE charity_haya_karima_operational;
GO

IF DB_ID(N'unified_charity_platform_clean') IS NULL
    CREATE DATABASE unified_charity_platform_clean;
GO

IF DB_ID(N'charity_dwh') IS NULL
    CREATE DATABASE charity_dwh;
GO

SELECT name AS database_name
FROM sys.databases
WHERE name IN (
    N'charity_food_bank_operational',
    N'charity_resala_operational',
    N'charity_haya_karima_operational',
    N'unified_charity_platform_clean',
    N'charity_dwh'
)
ORDER BY name;
GO


/* =============================== END INCLUDED FILE ============================== */


/* ==============================================================================
   START INCLUDED FILE: 00_ALL_IN_ONE_unified_charity_platform_clean.sql
   ============================================================================== */

USE master;
GO

IF DB_ID(N'unified_charity_platform_clean') IS NOT NULL
BEGIN
    ALTER DATABASE unified_charity_platform_clean
    SET SINGLE_USER
    WITH ROLLBACK IMMEDIATE;

    DROP DATABASE unified_charity_platform_clean;
END;
GO
/* ============================================================
   ALL-IN-ONE SQL FILE — NO ERROR VERSION
   Unified Charity Platform Clean Database

   Database:
   unified_charity_platform_clean

   Includes:
   1) Clean schema
   2) Reference + demo seed data
   3) Dashboard and Beneficiary 360 views
   4) Advanced views, functions, procedures, fraud detection, data quality
   5) Automation triggers and indexes
   6) Final fixed Beneficiary 360 procedure

   IMPORTANT:
   - Run this full file in SSMS.
   - It creates/rebuilds unified_charity_platform_clean.
   - It does NOT delete your old unified_charity_platform database.
   ============================================================ */



/* ============================================================
   START FILE: 01_create_clean_schema.sql
   ============================================================ */



/* ============================================================
   CLEAN DATABASE V1 — Unified Charity Platform
   هدف التصميم:
   - ERD نظيف وواضح
   - Relationships حقيقية بـ Foreign Keys
   - Beneficiary 360 قوي
   - كشف duplicate / fraud بدون ما نكسر الـ operational clean data
   - جاهز للـ Dashboard + Kafka/Outbox + Data Warehouse
   ============================================================ */

IF DB_ID(N'unified_charity_platform_clean') IS NULL
BEGIN
    CREATE DATABASE unified_charity_platform_clean;
END;
GO

USE unified_charity_platform_clean;
GO

/* ============================================================
   Clean rebuild section
   بما إنها DB جديدة، السكريبت بيحذف الجداول لو موجودة عشان يبدأ نضيف.
   ============================================================ */

DROP TABLE IF EXISTS dbo.platform_event_outbox;
DROP TABLE IF EXISTS dbo.audit_logs;
DROP TABLE IF EXISTS dbo.fraud_alerts;
DROP TABLE IF EXISTS dbo.duplicate_candidates;
DROP TABLE IF EXISTS dbo.inventory_stock_balances;
DROP TABLE IF EXISTS dbo.inventory_transactions;
DROP TABLE IF EXISTS dbo.donations;
DROP TABLE IF EXISTS dbo.beneficiary_documents;
DROP TABLE IF EXISTS dbo.charity_cases;
DROP TABLE IF EXISTS dbo.beneficiary_applications;
DROP TABLE IF EXISTS dbo.beneficiary_identity_records;
DROP TABLE IF EXISTS dbo.beneficiary_org_registrations;
DROP TABLE IF EXISTS dbo.beneficiary_profiles;
DROP TABLE IF EXISTS dbo.platform_users;
DROP TABLE IF EXISTS dbo.inventory_items;
DROP TABLE IF EXISTS dbo.document_types;
DROP TABLE IF EXISTS dbo.payment_methods;
DROP TABLE IF EXISTS dbo.support_types;
DROP TABLE IF EXISTS dbo.branches;
DROP TABLE IF EXISTS dbo.organizations;
DROP TABLE IF EXISTS dbo.cities;
DROP TABLE IF EXISTS dbo.governorates;
DROP TABLE IF EXISTS dbo.roles;
GO

/* ============================================================
   1) Reference / Lookup Tables
   ============================================================ */

CREATE TABLE dbo.roles (
    role_id INT IDENTITY(1,1) PRIMARY KEY,
    role_code NVARCHAR(50) NOT NULL UNIQUE,
    role_name_ar NVARCHAR(100) NOT NULL,
    role_name_en NVARCHAR(100) NULL,
    is_active BIT NOT NULL DEFAULT 1,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE dbo.governorates (
    governorate_id INT IDENTITY(1,1) PRIMARY KEY,
    governorate_code NVARCHAR(30) NOT NULL UNIQUE,
    governorate_name_ar NVARCHAR(100) NOT NULL UNIQUE,
    governorate_name_en NVARCHAR(100) NULL,
    is_active BIT NOT NULL DEFAULT 1
);

CREATE TABLE dbo.cities (
    city_id INT IDENTITY(1,1) PRIMARY KEY,
    governorate_id INT NOT NULL,
    city_code NVARCHAR(30) NOT NULL UNIQUE,
    city_name_ar NVARCHAR(100) NOT NULL,
    city_name_en NVARCHAR(100) NULL,
    is_active BIT NOT NULL DEFAULT 1,
    CONSTRAINT fk_cities_governorates
        FOREIGN KEY (governorate_id) REFERENCES dbo.governorates(governorate_id)
);

CREATE TABLE dbo.organizations (
    organization_id INT IDENTITY(1,1) PRIMARY KEY,
    organization_code NVARCHAR(50) NOT NULL UNIQUE,
    organization_name_ar NVARCHAR(200) NOT NULL,
    organization_name_en NVARCHAR(200) NULL,
    phone NVARCHAR(30) NULL,
    email NVARCHAR(150) NULL,
    address NVARCHAR(300) NULL,
    is_active BIT NOT NULL DEFAULT 1,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE dbo.branches (
    branch_id INT IDENTITY(1,1) PRIMARY KEY,
    branch_code NVARCHAR(50) NOT NULL UNIQUE,
    organization_id INT NOT NULL,
    branch_name_ar NVARCHAR(200) NOT NULL,
    branch_name_en NVARCHAR(200) NULL,
    governorate_id INT NOT NULL,
    city_id INT NOT NULL,
    address NVARCHAR(300) NULL,
    phone NVARCHAR(30) NULL,
    is_active BIT NOT NULL DEFAULT 1,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT fk_branches_organizations
        FOREIGN KEY (organization_id) REFERENCES dbo.organizations(organization_id),
    CONSTRAINT fk_branches_governorates
        FOREIGN KEY (governorate_id) REFERENCES dbo.governorates(governorate_id),
    CONSTRAINT fk_branches_cities
        FOREIGN KEY (city_id) REFERENCES dbo.cities(city_id)
);

CREATE TABLE dbo.support_types (
    support_type_id INT IDENTITY(1,1) PRIMARY KEY,
    support_code NVARCHAR(50) NOT NULL UNIQUE,
    support_name_ar NVARCHAR(150) NOT NULL,
    support_name_en NVARCHAR(150) NULL,
    is_cash_support BIT NOT NULL DEFAULT 0,
    is_inventory_support BIT NOT NULL DEFAULT 0,
    is_active BIT NOT NULL DEFAULT 1
);

CREATE TABLE dbo.payment_methods (
    payment_method_id INT IDENTITY(1,1) PRIMARY KEY,
    payment_method_code NVARCHAR(50) NOT NULL UNIQUE,
    method_name_ar NVARCHAR(100) NOT NULL,
    method_name_en NVARCHAR(100) NULL,
    is_active BIT NOT NULL DEFAULT 1
);

CREATE TABLE dbo.document_types (
    document_type_id INT IDENTITY(1,1) PRIMARY KEY,
    document_type_code NVARCHAR(50) NOT NULL UNIQUE,
    document_type_name_ar NVARCHAR(150) NOT NULL,
    document_type_name_en NVARCHAR(150) NULL,
    is_required_by_default BIT NOT NULL DEFAULT 0,
    is_active BIT NOT NULL DEFAULT 1
);

CREATE TABLE dbo.inventory_items (
    item_id INT IDENTITY(1,1) PRIMARY KEY,
    item_code NVARCHAR(50) NOT NULL UNIQUE,
    item_name_ar NVARCHAR(150) NOT NULL,
    item_name_en NVARCHAR(150) NULL,
    item_category NVARCHAR(100) NULL,
    unit NVARCHAR(50) NOT NULL,
    default_unit_cost DECIMAL(18,2) NOT NULL DEFAULT 0,
    is_active BIT NOT NULL DEFAULT 1
);
GO

/* ============================================================
   2) Users + Beneficiary Master
   ============================================================ */

CREATE TABLE dbo.platform_users (
    user_id INT IDENTITY(1,1) PRIMARY KEY,
    user_code NVARCHAR(50) NOT NULL UNIQUE,
    role_id INT NOT NULL,
    organization_id INT NULL,
    branch_id INT NULL,
    full_name NVARCHAR(200) NOT NULL,
    phone NVARCHAR(30) NULL,
    email NVARCHAR(150) NULL,
    password_hash NVARCHAR(300) NULL,
    is_active BIT NOT NULL DEFAULT 1,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at DATETIME2(0) NULL,
    CONSTRAINT fk_platform_users_roles
        FOREIGN KEY (role_id) REFERENCES dbo.roles(role_id),
    CONSTRAINT fk_platform_users_organizations
        FOREIGN KEY (organization_id) REFERENCES dbo.organizations(organization_id),
    CONSTRAINT fk_platform_users_branches
        FOREIGN KEY (branch_id) REFERENCES dbo.branches(branch_id)
);

CREATE UNIQUE INDEX ux_platform_users_email_not_null
ON dbo.platform_users(email)
WHERE email IS NOT NULL;

CREATE TABLE dbo.beneficiary_profiles (
    beneficiary_id INT IDENTITY(1,1) PRIMARY KEY,
    beneficiary_code NVARCHAR(50) NOT NULL UNIQUE,
    user_id INT NULL UNIQUE,
    national_id NVARCHAR(30) NOT NULL UNIQUE,
    full_name NVARCHAR(200) NOT NULL,
    gender NVARCHAR(20) NULL,
    birth_date DATE NULL,
    phone NVARCHAR(30) NULL,
    email NVARCHAR(150) NULL,
    governorate_id INT NOT NULL,
    city_id INT NOT NULL,
    address NVARCHAR(300) NULL,
    family_size INT NULL,
    monthly_income DECIMAL(18,2) NULL,
    employment_status NVARCHAR(100) NULL,
    is_active BIT NOT NULL DEFAULT 1,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at DATETIME2(0) NULL,
    CONSTRAINT fk_beneficiary_profiles_users
        FOREIGN KEY (user_id) REFERENCES dbo.platform_users(user_id),
    CONSTRAINT fk_beneficiary_profiles_governorates
        FOREIGN KEY (governorate_id) REFERENCES dbo.governorates(governorate_id),
    CONSTRAINT fk_beneficiary_profiles_cities
        FOREIGN KEY (city_id) REFERENCES dbo.cities(city_id),
    CONSTRAINT ck_beneficiary_profiles_family_size
        CHECK (family_size IS NULL OR family_size >= 1),
    CONSTRAINT ck_beneficiary_profiles_monthly_income
        CHECK (monthly_income IS NULL OR monthly_income >= 0)
);

CREATE TABLE dbo.beneficiary_org_registrations (
    registration_id INT IDENTITY(1,1) PRIMARY KEY,
    beneficiary_id INT NOT NULL,
    organization_id INT NOT NULL,
    branch_id INT NULL,
    registration_status NVARCHAR(50) NOT NULL DEFAULT N'ACTIVE',
    registration_channel NVARCHAR(50) NULL,
    registered_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    notes NVARCHAR(500) NULL,
    CONSTRAINT fk_beneficiary_org_registrations_beneficiaries
        FOREIGN KEY (beneficiary_id) REFERENCES dbo.beneficiary_profiles(beneficiary_id),
    CONSTRAINT fk_beneficiary_org_registrations_organizations
        FOREIGN KEY (organization_id) REFERENCES dbo.organizations(organization_id),
    CONSTRAINT fk_beneficiary_org_registrations_branches
        FOREIGN KEY (branch_id) REFERENCES dbo.branches(branch_id),
    CONSTRAINT uq_beneficiary_org_registration UNIQUE (beneficiary_id, organization_id)
);

/*
   جدول raw identity records:
   هنا بنسمح بالتكرار عمداً عشان نكشف duplicate/fraud.
   ده يمثل البيانات الخام اللي جاية من الجمعيات أو الفورم أو source systems.
*/
CREATE TABLE dbo.beneficiary_identity_records (
    identity_record_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    source_system NVARCHAR(100) NOT NULL DEFAULT N'unified_charity_platform',
    organization_id INT NULL,
    branch_id INT NULL,
    national_id NVARCHAR(30) NULL,
    full_name NVARCHAR(200) NULL,
    phone NVARCHAR(30) NULL,
    email NVARCHAR(150) NULL,
    governorate_id INT NULL,
    city_id INT NULL,
    matched_beneficiary_id INT NULL,
    match_status NVARCHAR(50) NOT NULL DEFAULT N'NEW', -- NEW / MATCHED / POSSIBLE_DUPLICATE / REJECTED
    raw_payload NVARCHAR(MAX) NULL,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT fk_identity_records_organizations
        FOREIGN KEY (organization_id) REFERENCES dbo.organizations(organization_id),
    CONSTRAINT fk_identity_records_branches
        FOREIGN KEY (branch_id) REFERENCES dbo.branches(branch_id),
    CONSTRAINT fk_identity_records_governorates
        FOREIGN KEY (governorate_id) REFERENCES dbo.governorates(governorate_id),
    CONSTRAINT fk_identity_records_cities
        FOREIGN KEY (city_id) REFERENCES dbo.cities(city_id),
    CONSTRAINT fk_identity_records_beneficiaries
        FOREIGN KEY (matched_beneficiary_id) REFERENCES dbo.beneficiary_profiles(beneficiary_id)
);
GO

/* ============================================================
   3) Applications + Cases + Documents
   ============================================================ */

CREATE TABLE dbo.beneficiary_applications (
    application_id INT IDENTITY(1,1) PRIMARY KEY,
    application_code NVARCHAR(50) NOT NULL UNIQUE,
    beneficiary_id INT NOT NULL,
    organization_id INT NOT NULL,
    branch_id INT NULL,
    support_type_id INT NOT NULL,
    requested_amount DECIMAL(18,2) NULL,
    application_status NVARCHAR(50) NOT NULL DEFAULT N'SUBMITTED',
    priority_level NVARCHAR(50) NOT NULL DEFAULT N'MEDIUM',
    submitted_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    reviewed_by INT NULL,
    reviewed_at DATETIME2(0) NULL,
    admin_notes NVARCHAR(1000) NULL,
    assignment_reason NVARCHAR(500) NULL,
    CONSTRAINT fk_applications_beneficiaries
        FOREIGN KEY (beneficiary_id) REFERENCES dbo.beneficiary_profiles(beneficiary_id),
    CONSTRAINT fk_applications_organizations
        FOREIGN KEY (organization_id) REFERENCES dbo.organizations(organization_id),
    CONSTRAINT fk_applications_branches
        FOREIGN KEY (branch_id) REFERENCES dbo.branches(branch_id),
    CONSTRAINT fk_applications_support_types
        FOREIGN KEY (support_type_id) REFERENCES dbo.support_types(support_type_id),
    CONSTRAINT fk_applications_reviewed_by
        FOREIGN KEY (reviewed_by) REFERENCES dbo.platform_users(user_id),
    CONSTRAINT ck_applications_requested_amount
        CHECK (requested_amount IS NULL OR requested_amount >= 0)
);

CREATE TABLE dbo.charity_cases (
    case_id INT IDENTITY(1,1) PRIMARY KEY,
    case_code NVARCHAR(50) NOT NULL UNIQUE,
    application_id INT NOT NULL,
    beneficiary_id INT NOT NULL,
    organization_id INT NOT NULL,
    branch_id INT NULL,
    support_type_id INT NOT NULL,
    case_title NVARCHAR(250) NOT NULL,
    case_description NVARCHAR(2000) NULL,
    required_amount DECIMAL(18,2) NOT NULL DEFAULT 0,
    collected_amount DECIMAL(18,2) NOT NULL DEFAULT 0,
    case_status NVARCHAR(50) NOT NULL DEFAULT N'OPEN',
    priority_level NVARCHAR(50) NOT NULL DEFAULT N'MEDIUM',
    published_at DATETIME2(0) NULL,
    closed_at DATETIME2(0) NULL,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT fk_cases_applications
        FOREIGN KEY (application_id) REFERENCES dbo.beneficiary_applications(application_id),
    CONSTRAINT fk_cases_beneficiaries
        FOREIGN KEY (beneficiary_id) REFERENCES dbo.beneficiary_profiles(beneficiary_id),
    CONSTRAINT fk_cases_organizations
        FOREIGN KEY (organization_id) REFERENCES dbo.organizations(organization_id),
    CONSTRAINT fk_cases_branches
        FOREIGN KEY (branch_id) REFERENCES dbo.branches(branch_id),
    CONSTRAINT fk_cases_support_types
        FOREIGN KEY (support_type_id) REFERENCES dbo.support_types(support_type_id),
    CONSTRAINT ck_cases_required_amount CHECK (required_amount >= 0),
    CONSTRAINT ck_cases_collected_amount CHECK (collected_amount >= 0)
);

CREATE TABLE dbo.beneficiary_documents (
    document_id INT IDENTITY(1,1) PRIMARY KEY,
    document_code NVARCHAR(50) NOT NULL UNIQUE,
    beneficiary_id INT NOT NULL,
    application_id INT NULL,
    case_id INT NULL,
    document_type_id INT NOT NULL,
    original_file_name NVARCHAR(300) NOT NULL,
    stored_file_name NVARCHAR(300) NULL,
    content_type NVARCHAR(100) NULL,
    file_size_kb DECIMAL(18,2) NULL,
    bucket_name NVARCHAR(100) NULL,
    object_key NVARCHAR(500) NULL,
    storage_path NVARCHAR(800) NULL,
    file_url NVARCHAR(1000) NULL,
    document_status NVARCHAR(50) NOT NULL DEFAULT N'PENDING_REVIEW',
    uploaded_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    reviewed_by INT NULL,
    reviewed_at DATETIME2(0) NULL,
    CONSTRAINT fk_documents_beneficiaries
        FOREIGN KEY (beneficiary_id) REFERENCES dbo.beneficiary_profiles(beneficiary_id),
    CONSTRAINT fk_documents_applications
        FOREIGN KEY (application_id) REFERENCES dbo.beneficiary_applications(application_id),
    CONSTRAINT fk_documents_cases
        FOREIGN KEY (case_id) REFERENCES dbo.charity_cases(case_id),
    CONSTRAINT fk_documents_document_types
        FOREIGN KEY (document_type_id) REFERENCES dbo.document_types(document_type_id),
    CONSTRAINT fk_documents_reviewed_by
        FOREIGN KEY (reviewed_by) REFERENCES dbo.platform_users(user_id)
);
GO

/* ============================================================
   4) Donations + Inventory
   ============================================================ */

CREATE TABLE dbo.donations (
    donation_id INT IDENTITY(1,1) PRIMARY KEY,
    donation_code NVARCHAR(50) NOT NULL UNIQUE,
    donor_user_id INT NULL,
    donor_name NVARCHAR(200) NULL,
    donor_phone NVARCHAR(30) NULL,
    donor_email NVARCHAR(150) NULL,
    organization_id INT NULL,
    case_id INT NULL,
    payment_method_id INT NOT NULL,
    amount DECIMAL(18,2) NOT NULL,
    currency NVARCHAR(10) NOT NULL DEFAULT N'EGP',
    donation_target_type NVARCHAR(50) NOT NULL, -- CASE / ORGANIZATION_GENERAL / PLATFORM_GENERAL
    donation_status NVARCHAR(50) NOT NULL DEFAULT N'COMPLETED',
    payment_status NVARCHAR(50) NOT NULL DEFAULT N'SUCCESS',
    campaign_name NVARCHAR(200) NULL,
    idempotency_key NVARCHAR(100) NULL UNIQUE,
    general_notes NVARCHAR(500) NULL,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT fk_donations_donor_users
        FOREIGN KEY (donor_user_id) REFERENCES dbo.platform_users(user_id),
    CONSTRAINT fk_donations_organizations
        FOREIGN KEY (organization_id) REFERENCES dbo.organizations(organization_id),
    CONSTRAINT fk_donations_cases
        FOREIGN KEY (case_id) REFERENCES dbo.charity_cases(case_id),
    CONSTRAINT fk_donations_payment_methods
        FOREIGN KEY (payment_method_id) REFERENCES dbo.payment_methods(payment_method_id),
    CONSTRAINT ck_donations_amount CHECK (amount > 0),
    CONSTRAINT ck_donations_target_logic CHECK (
        (donation_target_type = N'CASE' AND case_id IS NOT NULL)
        OR (donation_target_type = N'ORGANIZATION_GENERAL' AND organization_id IS NOT NULL AND case_id IS NULL)
        OR (donation_target_type = N'PLATFORM_GENERAL' AND case_id IS NULL)
    )
);

CREATE TABLE dbo.inventory_transactions (
    transaction_id INT IDENTITY(1,1) PRIMARY KEY,
    transaction_code NVARCHAR(50) NOT NULL UNIQUE,
    organization_id INT NOT NULL,
    branch_id INT NULL,
    item_id INT NOT NULL,
    transaction_type NVARCHAR(20) NOT NULL, -- IN / OUT / ADJUSTMENT / LOSS
    quantity DECIMAL(18,2) NOT NULL,
    unit_cost DECIMAL(18,2) NOT NULL,
    total_cost AS (quantity * unit_cost),
    case_id INT NULL,
    application_id INT NULL,
    donation_id INT NULL,
    reference_type NVARCHAR(50) NULL,
    reference_id NVARCHAR(100) NULL,
    notes NVARCHAR(500) NULL,
    transaction_date DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by INT NULL,
    CONSTRAINT fk_inventory_transactions_organizations
        FOREIGN KEY (organization_id) REFERENCES dbo.organizations(organization_id),
    CONSTRAINT fk_inventory_transactions_branches
        FOREIGN KEY (branch_id) REFERENCES dbo.branches(branch_id),
    CONSTRAINT fk_inventory_transactions_items
        FOREIGN KEY (item_id) REFERENCES dbo.inventory_items(item_id),
    CONSTRAINT fk_inventory_transactions_cases
        FOREIGN KEY (case_id) REFERENCES dbo.charity_cases(case_id),
    CONSTRAINT fk_inventory_transactions_applications
        FOREIGN KEY (application_id) REFERENCES dbo.beneficiary_applications(application_id),
    CONSTRAINT fk_inventory_transactions_donations
        FOREIGN KEY (donation_id) REFERENCES dbo.donations(donation_id),
    CONSTRAINT fk_inventory_transactions_created_by
        FOREIGN KEY (created_by) REFERENCES dbo.platform_users(user_id),
    CONSTRAINT ck_inventory_quantity CHECK (quantity > 0),
    CONSTRAINT ck_inventory_unit_cost CHECK (unit_cost >= 0),
    CONSTRAINT ck_inventory_out_logic CHECK (
        transaction_type <> N'OUT'
        OR case_id IS NOT NULL
        OR reference_type IN (N'LOSS', N'DAMAGE', N'MANUAL_ADJUSTMENT')
    )
);

CREATE TABLE dbo.inventory_stock_balances (
    stock_balance_id INT IDENTITY(1,1) PRIMARY KEY,
    organization_id INT NOT NULL,
    branch_id INT NULL,
    item_id INT NOT NULL,
    quantity_on_hand DECIMAL(18,2) NOT NULL DEFAULT 0,
    average_unit_cost DECIMAL(18,2) NOT NULL DEFAULT 0,
    updated_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT fk_stock_organizations
        FOREIGN KEY (organization_id) REFERENCES dbo.organizations(organization_id),
    CONSTRAINT fk_stock_branches
        FOREIGN KEY (branch_id) REFERENCES dbo.branches(branch_id),
    CONSTRAINT fk_stock_items
        FOREIGN KEY (item_id) REFERENCES dbo.inventory_items(item_id),
    CONSTRAINT uq_stock_balance UNIQUE (organization_id, branch_id, item_id),
    CONSTRAINT ck_stock_quantity CHECK (quantity_on_hand >= 0)
);
GO

/* ============================================================
   5) Fraud + Duplicate Monitoring
   ============================================================ */

CREATE TABLE dbo.duplicate_candidates (
    duplicate_candidate_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    rule_code NVARCHAR(100) NOT NULL,
    primary_beneficiary_id INT NULL,
    duplicate_beneficiary_id INT NULL,
    identity_record_id BIGINT NULL,
    organization_id INT NULL,
    national_id NVARCHAR(30) NULL,
    phone NVARCHAR(30) NULL,
    candidate_reason NVARCHAR(1000) NOT NULL,
    confidence_score DECIMAL(5,2) NOT NULL,
    candidate_status NVARCHAR(50) NOT NULL DEFAULT N'OPEN',
    detected_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    resolved_by INT NULL,
    resolved_at DATETIME2(0) NULL,
    resolution_notes NVARCHAR(1000) NULL,
    CONSTRAINT fk_duplicates_primary_beneficiary
        FOREIGN KEY (primary_beneficiary_id) REFERENCES dbo.beneficiary_profiles(beneficiary_id),
    CONSTRAINT fk_duplicates_duplicate_beneficiary
        FOREIGN KEY (duplicate_beneficiary_id) REFERENCES dbo.beneficiary_profiles(beneficiary_id),
    CONSTRAINT fk_duplicates_identity_records
        FOREIGN KEY (identity_record_id) REFERENCES dbo.beneficiary_identity_records(identity_record_id),
    CONSTRAINT fk_duplicates_organizations
        FOREIGN KEY (organization_id) REFERENCES dbo.organizations(organization_id),
    CONSTRAINT fk_duplicates_resolved_by
        FOREIGN KEY (resolved_by) REFERENCES dbo.platform_users(user_id),
    CONSTRAINT ck_duplicates_confidence CHECK (confidence_score BETWEEN 0 AND 100)
);

CREATE TABLE dbo.fraud_alerts (
    fraud_alert_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    alert_code NVARCHAR(50) NOT NULL UNIQUE,
    alert_type NVARCHAR(100) NOT NULL,
    severity NVARCHAR(20) NOT NULL, -- LOW / MEDIUM / HIGH / CRITICAL
    risk_score DECIMAL(5,2) NOT NULL,
    alert_status NVARCHAR(50) NOT NULL DEFAULT N'OPEN',
    beneficiary_id INT NULL,
    identity_record_id BIGINT NULL,
    application_id INT NULL,
    case_id INT NULL,
    document_id INT NULL,
    donation_id INT NULL,
    inventory_transaction_id INT NULL,
    organization_id INT NULL,
    description NVARCHAR(2000) NOT NULL,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    reviewed_by INT NULL,
    reviewed_at DATETIME2(0) NULL,
    review_notes NVARCHAR(1000) NULL,
    CONSTRAINT fk_fraud_beneficiaries
        FOREIGN KEY (beneficiary_id) REFERENCES dbo.beneficiary_profiles(beneficiary_id),
    CONSTRAINT fk_fraud_identity_records
        FOREIGN KEY (identity_record_id) REFERENCES dbo.beneficiary_identity_records(identity_record_id),
    CONSTRAINT fk_fraud_applications
        FOREIGN KEY (application_id) REFERENCES dbo.beneficiary_applications(application_id),
    CONSTRAINT fk_fraud_cases
        FOREIGN KEY (case_id) REFERENCES dbo.charity_cases(case_id),
    CONSTRAINT fk_fraud_documents
        FOREIGN KEY (document_id) REFERENCES dbo.beneficiary_documents(document_id),
    CONSTRAINT fk_fraud_donations
        FOREIGN KEY (donation_id) REFERENCES dbo.donations(donation_id),
    CONSTRAINT fk_fraud_inventory_transactions
        FOREIGN KEY (inventory_transaction_id) REFERENCES dbo.inventory_transactions(transaction_id),
    CONSTRAINT fk_fraud_organizations
        FOREIGN KEY (organization_id) REFERENCES dbo.organizations(organization_id),
    CONSTRAINT fk_fraud_reviewed_by
        FOREIGN KEY (reviewed_by) REFERENCES dbo.platform_users(user_id),
    CONSTRAINT ck_fraud_risk_score CHECK (risk_score BETWEEN 0 AND 100)
);
GO

/* ============================================================
   6) Audit + Outbox
   ============================================================ */

CREATE TABLE dbo.audit_logs (
    audit_log_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    actor_user_id INT NULL,
    action_type NVARCHAR(100) NOT NULL,
    entity_name NVARCHAR(100) NOT NULL,
    entity_id NVARCHAR(100) NULL,
    old_value NVARCHAR(MAX) NULL,
    new_value NVARCHAR(MAX) NULL,
    source_system NVARCHAR(100) NOT NULL DEFAULT N'unified_charity_platform',
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT fk_audit_logs_users
        FOREIGN KEY (actor_user_id) REFERENCES dbo.platform_users(user_id)
);

CREATE TABLE dbo.platform_event_outbox (
    event_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    event_uuid UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() UNIQUE,
    event_type NVARCHAR(100) NOT NULL,
    source_system NVARCHAR(100) NOT NULL DEFAULT N'unified_charity_platform',
    event_status NVARCHAR(50) NOT NULL DEFAULT N'PENDING',
    payload NVARCHAR(MAX) NULL,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    sent_to_kafka_at DATETIME2(0) NULL,

    user_id INT NULL,
    beneficiary_id INT NULL,
    organization_id INT NULL,
    branch_id INT NULL,
    application_id INT NULL,
    case_id INT NULL,
    donation_id INT NULL,
    document_id INT NULL,
    inventory_transaction_id INT NULL,
    fraud_alert_id BIGINT NULL,

    CONSTRAINT fk_outbox_users
        FOREIGN KEY (user_id) REFERENCES dbo.platform_users(user_id),
    CONSTRAINT fk_outbox_beneficiaries
        FOREIGN KEY (beneficiary_id) REFERENCES dbo.beneficiary_profiles(beneficiary_id),
    CONSTRAINT fk_outbox_organizations
        FOREIGN KEY (organization_id) REFERENCES dbo.organizations(organization_id),
    CONSTRAINT fk_outbox_branches
        FOREIGN KEY (branch_id) REFERENCES dbo.branches(branch_id),
    CONSTRAINT fk_outbox_applications
        FOREIGN KEY (application_id) REFERENCES dbo.beneficiary_applications(application_id),
    CONSTRAINT fk_outbox_cases
        FOREIGN KEY (case_id) REFERENCES dbo.charity_cases(case_id),
    CONSTRAINT fk_outbox_donations
        FOREIGN KEY (donation_id) REFERENCES dbo.donations(donation_id),
    CONSTRAINT fk_outbox_documents
        FOREIGN KEY (document_id) REFERENCES dbo.beneficiary_documents(document_id),
    CONSTRAINT fk_outbox_inventory
        FOREIGN KEY (inventory_transaction_id) REFERENCES dbo.inventory_transactions(transaction_id),
    CONSTRAINT fk_outbox_fraud_alerts
        FOREIGN KEY (fraud_alert_id) REFERENCES dbo.fraud_alerts(fraud_alert_id)
);
GO

/* ============================================================
   7) Business Consistency Triggers
   ============================================================ */

CREATE OR ALTER TRIGGER dbo.trg_cases_consistency
ON dbo.charity_cases
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.beneficiary_applications a
            ON i.application_id = a.application_id
        WHERE i.beneficiary_id <> a.beneficiary_id
           OR i.organization_id <> a.organization_id
           OR i.support_type_id <> a.support_type_id
    )
    BEGIN
        THROW 52001, 'Invalid charity case: beneficiary, organization, and support type must match the linked application.', 1;
    END;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_documents_consistency
ON dbo.beneficiary_documents
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.beneficiary_applications a
            ON i.application_id = a.application_id
        WHERE i.application_id IS NOT NULL
          AND i.beneficiary_id <> a.beneficiary_id
    )
    BEGIN
        THROW 52002, 'Invalid document: beneficiary_id must match linked application beneficiary_id.', 1;
    END;
END;
GO

/* Stock balance trigger:
   يحسب الرصيد تلقائياً من حركات المخزون.
*/
CREATE OR ALTER TRIGGER dbo.trg_inventory_update_stock_balance
ON dbo.inventory_transactions
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.inventory_stock_balances AS target
    USING (
        SELECT
            organization_id,
            branch_id,
            item_id,
            SUM(CASE
                    WHEN transaction_type = N'IN' THEN quantity
                    WHEN transaction_type IN (N'OUT', N'LOSS') THEN -quantity
                    WHEN transaction_type = N'ADJUSTMENT' THEN quantity
                    ELSE 0
                END) AS quantity_delta,
            AVG(unit_cost) AS avg_cost
        FROM inserted
        GROUP BY organization_id, branch_id, item_id
    ) AS source
    ON target.organization_id = source.organization_id
       AND ISNULL(target.branch_id, -1) = ISNULL(source.branch_id, -1)
       AND target.item_id = source.item_id
    WHEN MATCHED THEN
        UPDATE SET
            quantity_on_hand = target.quantity_on_hand + source.quantity_delta,
            average_unit_cost = CASE WHEN source.avg_cost IS NULL THEN target.average_unit_cost ELSE source.avg_cost END,
            updated_at = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (organization_id, branch_id, item_id, quantity_on_hand, average_unit_cost, updated_at)
        VALUES (source.organization_id, source.branch_id, source.item_id, source.quantity_delta, ISNULL(source.avg_cost, 0), SYSUTCDATETIME());

    IF EXISTS (SELECT 1 FROM dbo.inventory_stock_balances WHERE quantity_on_hand < 0)
    BEGIN
        THROW 52003, 'Inventory stock cannot become negative.', 1;
    END;
END;
GO

PRINT N'✅ Clean schema created successfully in unified_charity_platform_clean.';
GO



/* ============================================================
   END FILE: 01_create_clean_schema.sql
   ============================================================ */




/* ============================================================
   START FILE: 02_seed_reference_and_demo_data.sql
   ============================================================ */



USE unified_charity_platform_clean;
GO

/* ============================================================
   CLEAN DATABASE V1 — Reference + Demo Seed Data
   ============================================================ */

SET NOCOUNT ON;

------------------------------------------------------------
-- Roles
------------------------------------------------------------
INSERT INTO dbo.roles (role_code, role_name_ar, role_name_en)
VALUES
('GOV_ADMIN', N'ادمن حكومة', 'Government Admin'),
('CHARITY_ADMIN', N'ادمن جمعية', 'Charity Admin'),
('BENEFICIARY', N'مستفيد', 'Beneficiary'),
('DONOR', N'متبرع', 'Donor'),
('DATA_ENGINEER', N'مهندس بيانات', 'Data Engineer');

------------------------------------------------------------
-- Governorates / Cities
------------------------------------------------------------
INSERT INTO dbo.governorates (governorate_code, governorate_name_ar, governorate_name_en)
VALUES
('GOV-CAI', N'القاهرة', 'Cairo'),
('GOV-GIZ', N'الجيزة', 'Giza'),
('GOV-MNF', N'المنوفية', 'Menofia');

DECLARE @cairo INT = (SELECT governorate_id FROM dbo.governorates WHERE governorate_code = 'GOV-CAI');
DECLARE @giza INT  = (SELECT governorate_id FROM dbo.governorates WHERE governorate_code = 'GOV-GIZ');
DECLARE @mnf INT   = (SELECT governorate_id FROM dbo.governorates WHERE governorate_code = 'GOV-MNF');

INSERT INTO dbo.cities (governorate_id, city_code, city_name_ar, city_name_en)
VALUES
(@cairo, 'CITY-CAI-01', N'مدينة نصر', 'Nasr City'),
(@cairo, 'CITY-CAI-02', N'المعادي', 'Maadi'),
(@giza,  'CITY-GIZ-01', N'الدقي', 'Dokki'),
(@giza,  'CITY-GIZ-02', N'6 أكتوبر', '6th of October'),
(@mnf,   'CITY-MNF-01', N'شبين الكوم', 'Shebin El Kom'),
(@mnf,   'CITY-MNF-02', N'منوف', 'Menouf');

------------------------------------------------------------
-- Organizations / Branches
------------------------------------------------------------
INSERT INTO dbo.organizations (organization_code, organization_name_ar, organization_name_en, phone, email, address)
VALUES
('ORG-FOOD', N'بنك الطعام المصري', 'Egyptian Food Bank', '01010000001', 'food@test.com', N'القاهرة'),
('ORG-RESALA', N'جمعية رسالة', 'Resala Charity', '01010000002', 'resala@test.com', N'الجيزة'),
('ORG-HAYA', N'حياة كريمة', 'Haya Karima', '01010000003', 'haya@test.com', N'المنوفية');

DECLARE @orgFood INT = (SELECT organization_id FROM dbo.organizations WHERE organization_code = 'ORG-FOOD');
DECLARE @orgResala INT = (SELECT organization_id FROM dbo.organizations WHERE organization_code = 'ORG-RESALA');
DECLARE @orgHaya INT = (SELECT organization_id FROM dbo.organizations WHERE organization_code = 'ORG-HAYA');

DECLARE @nasr INT = (SELECT city_id FROM dbo.cities WHERE city_code = 'CITY-CAI-01');
DECLARE @dokki INT = (SELECT city_id FROM dbo.cities WHERE city_code = 'CITY-GIZ-01');
DECLARE @shebin INT = (SELECT city_id FROM dbo.cities WHERE city_code = 'CITY-MNF-01');

INSERT INTO dbo.branches (branch_code, organization_id, branch_name_ar, governorate_id, city_id, address, phone)
VALUES
('BR-FOOD-CAI', @orgFood, N'فرع بنك الطعام - القاهرة', @cairo, @nasr, N'مدينة نصر', '01020000001'),
('BR-RESALA-GIZ', @orgResala, N'فرع رسالة - الجيزة', @giza, @dokki, N'الدقي', '01020000002'),
('BR-HAYA-MNF', @orgHaya, N'فرع حياة كريمة - المنوفية', @mnf, @shebin, N'شبين الكوم', '01020000003');

DECLARE @brFood INT = (SELECT branch_id FROM dbo.branches WHERE branch_code = 'BR-FOOD-CAI');
DECLARE @brResala INT = (SELECT branch_id FROM dbo.branches WHERE branch_code = 'BR-RESALA-GIZ');
DECLARE @brHaya INT = (SELECT branch_id FROM dbo.branches WHERE branch_code = 'BR-HAYA-MNF');

------------------------------------------------------------
-- Support / Payment / Documents / Items
------------------------------------------------------------
INSERT INTO dbo.support_types (support_code, support_name_ar, support_name_en, is_cash_support, is_inventory_support)
VALUES
('SUP-FOOD', N'دعم غذائي', 'Food Support', 0, 1),
('SUP-MED', N'دعم طبي', 'Medical Support', 1, 0),
('SUP-CASH', N'دعم نقدي', 'Cash Support', 1, 0),
('SUP-CLOTH', N'بطاطين وملابس', 'Clothes and Blankets', 0, 1);

INSERT INTO dbo.payment_methods (payment_method_code, method_name_ar, method_name_en)
VALUES
('PM-CASH', N'كاش', 'Cash'),
('PM-CARD', N'بطاقة بنكية', 'Card'),
('PM-WALLET', N'محفظة إلكترونية', 'Mobile Wallet');

INSERT INTO dbo.document_types (document_type_code, document_type_name_ar, document_type_name_en, is_required_by_default)
VALUES
('NATIONAL_ID', N'صورة البطاقة', 'National ID', 1),
('INCOME_PROOF', N'إثبات دخل', 'Income Proof', 0),
('MEDICAL_REPORT', N'تقرير طبي', 'Medical Report', 0);

INSERT INTO dbo.inventory_items (item_code, item_name_ar, item_name_en, item_category, unit, default_unit_cost)
VALUES
('ITEM-FOOD-BOX', N'كرتونة غذائية', 'Food Box', N'غذاء', N'كرتونة', 450),
('ITEM-BLANKET', N'بطانية', 'Blanket', N'بطاطين وملابس', N'قطعة', 300),
('ITEM-MEDICINE', N'أدوية شهرية', 'Monthly Medicine', N'طبي', N'عبوة', 250);

------------------------------------------------------------
-- Users
------------------------------------------------------------
DECLARE @roleGov INT = (SELECT role_id FROM dbo.roles WHERE role_code = 'GOV_ADMIN');
DECLARE @roleCharity INT = (SELECT role_id FROM dbo.roles WHERE role_code = 'CHARITY_ADMIN');
DECLARE @roleBeneficiary INT = (SELECT role_id FROM dbo.roles WHERE role_code = 'BENEFICIARY');

INSERT INTO dbo.platform_users (user_code, role_id, organization_id, branch_id, full_name, phone, email, password_hash)
VALUES
('USR-GOV-001', @roleGov, NULL, NULL, N'ادمن عام', '01030000001', 'gov@test.com', 'demo_hash'),
('USR-FOOD-ADMIN', @roleCharity, @orgFood, @brFood, N'ادمن بنك الطعام', '01030000002', 'food.admin@test.com', 'demo_hash'),
('USR-RESALA-ADMIN', @roleCharity, @orgResala, @brResala, N'ادمن رسالة', '01030000003', 'resala.admin@test.com', 'demo_hash');

------------------------------------------------------------
-- Beneficiaries
------------------------------------------------------------
DECLARE @benRoleUser INT;

INSERT INTO dbo.platform_users (user_code, role_id, full_name, phone, email, password_hash)
VALUES
('USR-BEN-AHMED', @roleBeneficiary, N'أحمد محمد علي', '01099000001', 'ahmed@test.com', 'demo_hash'),
('USR-BEN-SARA', @roleBeneficiary, N'سارة محمود حسن', '01099000002', 'sara@test.com', 'demo_hash'),
('USR-BEN-MONA', @roleBeneficiary, N'منى خالد إبراهيم', '01099000003', 'mona@test.com', 'demo_hash'),
('USR-BEN-YOUSSEF', @roleBeneficiary, N'يوسف أحمد سالم', '01099000004', 'youssef@test.com', 'demo_hash');

DECLARE @uAhmed INT = (SELECT user_id FROM dbo.platform_users WHERE user_code = 'USR-BEN-AHMED');
DECLARE @uSara INT = (SELECT user_id FROM dbo.platform_users WHERE user_code = 'USR-BEN-SARA');
DECLARE @uMona INT = (SELECT user_id FROM dbo.platform_users WHERE user_code = 'USR-BEN-MONA');
DECLARE @uYoussef INT = (SELECT user_id FROM dbo.platform_users WHERE user_code = 'USR-BEN-YOUSSEF');

INSERT INTO dbo.beneficiary_profiles
(beneficiary_code, user_id, national_id, full_name, gender, birth_date, phone, email, governorate_id, city_id, address, family_size, monthly_income, employment_status)
VALUES
('BEN-0001', @uAhmed, '2990101123456', N'أحمد محمد علي', 'Male', '1999-01-01', '01099000001', 'ahmed@test.com', @cairo, @nasr, N'مدينة نصر', 5, 1800, N'عمل غير منتظم'),
('BEN-0002', @uSara, '2980202123456', N'سارة محمود حسن', 'Female', '1998-02-02', '01099000002', 'sara@test.com', @giza, @dokki, N'الدقي', 4, 1200, N'لا تعمل'),
('BEN-0003', @uMona, '3010303123456', N'منى خالد إبراهيم', 'Female', '2001-03-03', '01099000003', 'mona@test.com', @mnf, @shebin, N'شبين الكوم', 3, 1600, N'طالبة'),
('BEN-0004', @uYoussef, '3000404123456', N'يوسف أحمد سالم', 'Male', '2000-04-04', '01099000004', 'youssef@test.com', @mnf, @shebin, N'شبين الكوم', 2, 1700, N'طالب');

DECLARE @benAhmed INT = (SELECT beneficiary_id FROM dbo.beneficiary_profiles WHERE beneficiary_code = 'BEN-0001');
DECLARE @benSara INT = (SELECT beneficiary_id FROM dbo.beneficiary_profiles WHERE beneficiary_code = 'BEN-0002');
DECLARE @benMona INT = (SELECT beneficiary_id FROM dbo.beneficiary_profiles WHERE beneficiary_code = 'BEN-0003');
DECLARE @benYoussef INT = (SELECT beneficiary_id FROM dbo.beneficiary_profiles WHERE beneficiary_code = 'BEN-0004');

INSERT INTO dbo.beneficiary_org_registrations (beneficiary_id, organization_id, branch_id, registration_channel, notes)
VALUES
(@benAhmed, @orgFood, @brFood, N'PLATFORM', N'مسجل في بنك الطعام'),
(@benAhmed, @orgResala, @brResala, N'PLATFORM', N'مسجل في رسالة أيضاً'),
(@benSara, @orgResala, @brResala, N'PLATFORM', N'طلب دعم طبي'),
(@benMona, @orgHaya, @brHaya, N'PLATFORM', N'دعم ملابس'),
(@benYoussef, @orgFood, @brFood, N'PLATFORM', N'طلب مرفوض');

------------------------------------------------------------
-- Raw identity records to support duplicate/fraud detection
------------------------------------------------------------
INSERT INTO dbo.beneficiary_identity_records
(source_system, organization_id, branch_id, national_id, full_name, phone, email, governorate_id, city_id, matched_beneficiary_id, match_status, raw_payload)
VALUES
(N'food_source', @orgFood, @brFood, '2990101123456', N'أحمد محمد علي', '01099000001', 'ahmed@test.com', @cairo, @nasr, @benAhmed, N'MATCHED', N'{"source":"food"}'),
(N'resala_source', @orgResala, @brResala, '2990101123456', N'احمد م علي', '01099000001', 'ahmed.second@test.com', @giza, @dokki, @benAhmed, N'POSSIBLE_DUPLICATE', N'{"source":"resala"}'),
(N'haya_source', @orgHaya, @brHaya, '2980202123456', N'سارة م حسن', '01099000999', 'sara.dup@test.com', @mnf, @shebin, @benSara, N'POSSIBLE_DUPLICATE', N'{"source":"haya"}');

DECLARE @identityDupAhmed BIGINT = (
    SELECT TOP 1 identity_record_id
    FROM dbo.beneficiary_identity_records
    WHERE source_system = N'resala_source'
);

------------------------------------------------------------
-- Applications
------------------------------------------------------------
DECLARE @supFood INT = (SELECT support_type_id FROM dbo.support_types WHERE support_code = 'SUP-FOOD');
DECLARE @supMed INT = (SELECT support_type_id FROM dbo.support_types WHERE support_code = 'SUP-MED');
DECLARE @supCloth INT = (SELECT support_type_id FROM dbo.support_types WHERE support_code = 'SUP-CLOTH');

INSERT INTO dbo.beneficiary_applications
(application_code, beneficiary_id, organization_id, branch_id, support_type_id, requested_amount, application_status, priority_level, submitted_at, reviewed_at, admin_notes, assignment_reason)
VALUES
('APP-0001', @benAhmed, @orgFood, @brFood, @supFood, 3000, N'APPROVED', N'HIGH', DATEADD(day,-15,SYSUTCDATETIME()), DATEADD(day,-14,SYSUTCDATETIME()), N'طلب دعم غذائي', N'حسب المحافظة ونوع الدعم'),
('APP-0002', @benAhmed, @orgResala, @brResala, @supFood, 2500, N'APPROVED', N'HIGH', DATEADD(day,-13,SYSUTCDATETIME()), DATEADD(day,-12,SYSUTCDATETIME()), N'نفس نوع الدعم من جمعية أخرى', N'Cross organization demo'),
('APP-0003', @benSara, @orgResala, @brResala, @supMed, 5000, N'UNDER_REVIEW', N'MEDIUM', DATEADD(day,-11,SYSUTCDATETIME()), NULL, N'طلب دعم طبي', N'مراجعة مستندات'),
('APP-0004', @benMona, @orgHaya, @brHaya, @supCloth, 1500, N'APPROVED', N'LOW', DATEADD(day,-9,SYSUTCDATETIME()), DATEADD(day,-8,SYSUTCDATETIME()), N'دعم بطاطين', N'أقرب فرع'),
('APP-0005', @benYoussef, @orgFood, @brFood, @supFood, 1800, N'REJECTED', N'MEDIUM', DATEADD(day,-7,SYSUTCDATETIME()), DATEADD(day,-6,SYSUTCDATETIME()), N'مرفوض لنقص البيانات', N'بيانات غير مكتملة');

DECLARE @app1 INT = (SELECT application_id FROM dbo.beneficiary_applications WHERE application_code='APP-0001');
DECLARE @app2 INT = (SELECT application_id FROM dbo.beneficiary_applications WHERE application_code='APP-0002');
DECLARE @app3 INT = (SELECT application_id FROM dbo.beneficiary_applications WHERE application_code='APP-0003');
DECLARE @app4 INT = (SELECT application_id FROM dbo.beneficiary_applications WHERE application_code='APP-0004');

------------------------------------------------------------
-- Cases
------------------------------------------------------------
INSERT INTO dbo.charity_cases
(case_code, application_id, beneficiary_id, organization_id, branch_id, support_type_id, case_title, case_description, required_amount, collected_amount, case_status, priority_level, published_at, closed_at)
VALUES
('CASE-0001', @app1, @benAhmed, @orgFood, @brFood, @supFood, N'حالة دعم غذائي لأحمد محمد', N'حالة مكتملة', 3000, 3000, N'CLOSED', N'HIGH', DATEADD(day,-14,SYSUTCDATETIME()), DATEADD(day,-5,SYSUTCDATETIME())),
('CASE-0002', @app2, @benAhmed, @orgResala, @brResala, @supFood, N'حالة دعم غذائي ثانية لنفس المستفيد', N'توضح التعامل مع أكثر من جمعية', 2500, 1200, N'OPEN', N'HIGH', DATEADD(day,-12,SYSUTCDATETIME()), NULL),
('CASE-0003', @app3, @benSara, @orgResala, @brResala, @supMed, N'حالة علاج لسارة محمود', N'حالة مفتوحة لدعم طبي', 5000, 500, N'OPEN', N'MEDIUM', DATEADD(day,-10,SYSUTCDATETIME()), NULL),
('CASE-0004', @app4, @benMona, @orgHaya, @brHaya, @supCloth, N'حالة بطاطين وملابس لمنى', N'حالة مكتملة', 1500, 1500, N'CLOSED', N'LOW', DATEADD(day,-8,SYSUTCDATETIME()), DATEADD(day,-2,SYSUTCDATETIME()));

DECLARE @case1 INT = (SELECT case_id FROM dbo.charity_cases WHERE case_code='CASE-0001');
DECLARE @case2 INT = (SELECT case_id FROM dbo.charity_cases WHERE case_code='CASE-0002');
DECLARE @case3 INT = (SELECT case_id FROM dbo.charity_cases WHERE case_code='CASE-0003');
DECLARE @case4 INT = (SELECT case_id FROM dbo.charity_cases WHERE case_code='CASE-0004');

------------------------------------------------------------
-- Donations
------------------------------------------------------------
DECLARE @pmCash INT = (SELECT payment_method_id FROM dbo.payment_methods WHERE payment_method_code='PM-CASH');
DECLARE @pmWallet INT = (SELECT payment_method_id FROM dbo.payment_methods WHERE payment_method_code='PM-WALLET');

INSERT INTO dbo.donations
(donation_code, donor_name, donor_phone, donor_email, organization_id, case_id, payment_method_id, amount, donation_target_type, campaign_name, idempotency_key, created_at)
VALUES
('DON-0001', N'متبرع تجريبي 1', '01077000001', 'donor1@test.com', @orgFood, @case1, @pmCash, 1500, N'CASE', N'دعم غذائي', 'DON-SEED-001', DATEADD(day,-13,SYSUTCDATETIME())),
('DON-0002', N'متبرع تجريبي 2', '01077000002', 'donor2@test.com', @orgFood, @case1, @pmWallet, 1500, N'CASE', N'دعم غذائي', 'DON-SEED-002', DATEADD(day,-12,SYSUTCDATETIME())),
('DON-0003', N'متبرع تجريبي 3', '01077000003', 'donor3@test.com', @orgResala, @case2, @pmCash, 1200, N'CASE', N'دعم غذائي', 'DON-SEED-003', DATEADD(day,-9,SYSUTCDATETIME())),
('DON-0004', N'متبرع عام', '01077000004', 'donor4@test.com', @orgHaya, NULL, @pmWallet, 800, N'ORGANIZATION_GENERAL', N'تبرع عام', 'DON-SEED-004', DATEADD(day,-6,SYSUTCDATETIME()));

------------------------------------------------------------
-- Documents
------------------------------------------------------------
DECLARE @docNat INT = (SELECT document_type_id FROM dbo.document_types WHERE document_type_code='NATIONAL_ID');
DECLARE @docMed INT = (SELECT document_type_id FROM dbo.document_types WHERE document_type_code='MEDICAL_REPORT');

INSERT INTO dbo.beneficiary_documents
(document_code, beneficiary_id, application_id, case_id, document_type_id, original_file_name, stored_file_name, content_type, file_size_kb, bucket_name, object_key, storage_path, file_url, document_status, uploaded_at)
VALUES
('DOC-0001', @benAhmed, @app1, @case1, @docNat, N'ahmed_id.png', N'ahmed_id.png', N'image/png', 250, N'charity-documents', N'demo/ahmed_id.png', N's3://charity-documents/demo/ahmed_id.png', N'/api/documents/file/demo/ahmed_id.png', N'APPROVED', DATEADD(day,-15,SYSUTCDATETIME())),
('DOC-0002', @benAhmed, @app2, @case2, @docNat, N'ahmed_id_second_org.png', N'ahmed_id_second_org.png', N'image/png', 245, N'charity-documents', N'demo/ahmed_id_second_org.png', N's3://charity-documents/demo/ahmed_id_second_org.png', N'/api/documents/file/demo/ahmed_id_second_org.png', N'APPROVED', DATEADD(day,-13,SYSUTCDATETIME())),
('DOC-0003', @benSara, @app3, @case3, @docMed, N'sara_report.pdf', N'sara_report.pdf', N'application/pdf', 880, N'charity-documents', N'demo/sara_report.pdf', N's3://charity-documents/demo/sara_report.pdf', N'/api/documents/file/demo/sara_report.pdf', N'PENDING_REVIEW', DATEADD(day,-11,SYSUTCDATETIME()));

DECLARE @doc2 INT = (SELECT document_id FROM dbo.beneficiary_documents WHERE document_code='DOC-0002');

------------------------------------------------------------
-- Inventory
------------------------------------------------------------
DECLARE @itemFood INT = (SELECT item_id FROM dbo.inventory_items WHERE item_code='ITEM-FOOD-BOX');
DECLARE @itemBlanket INT = (SELECT item_id FROM dbo.inventory_items WHERE item_code='ITEM-BLANKET');

INSERT INTO dbo.inventory_transactions
(transaction_code, organization_id, branch_id, item_id, transaction_type, quantity, unit_cost, case_id, application_id, reference_type, reference_id, notes, transaction_date)
VALUES
('INV-0001', @orgFood, @brFood, @itemFood, N'IN', 20, 450, NULL, NULL, N'MANUAL_ADJUSTMENT', N'SEED-IN-001', N'توريد تجريبي', DATEADD(day,-16,SYSUTCDATETIME())),
('INV-0002', @orgFood, @brFood, @itemFood, N'OUT', 3, 450, @case1, @app1, N'CASE', N'CASE-0001', N'صرف دعم غذائي لحالة أحمد', DATEADD(day,-12,SYSUTCDATETIME())),
('INV-0003', @orgResala, @brResala, @itemFood, N'IN', 12, 450, NULL, NULL, N'MANUAL_ADJUSTMENT', N'SEED-IN-002', N'توريد تجريبي', DATEADD(day,-14,SYSUTCDATETIME())),
('INV-0004', @orgResala, @brResala, @itemFood, N'OUT', 2, 450, @case2, @app2, N'CASE', N'CASE-0002', N'صرف دعم غذائي لنفس المستفيد من جمعية أخرى', DATEADD(day,-9,SYSUTCDATETIME())),
('INV-0005', @orgHaya, @brHaya, @itemBlanket, N'IN', 10, 300, NULL, NULL, N'MANUAL_ADJUSTMENT', N'SEED-IN-003', N'توريد بطاطين', DATEADD(day,-11,SYSUTCDATETIME())),
('INV-0006', @orgHaya, @brHaya, @itemBlanket, N'OUT', 2, 300, @case4, @app4, N'CASE', N'CASE-0004', N'صرف بطاطين لمنى', DATEADD(day,-6,SYSUTCDATETIME()));

DECLARE @inv4 INT = (SELECT transaction_id FROM dbo.inventory_transactions WHERE transaction_code='INV-0004');

------------------------------------------------------------
-- Duplicates + Fraud
------------------------------------------------------------
INSERT INTO dbo.duplicate_candidates
(rule_code, primary_beneficiary_id, identity_record_id, organization_id, national_id, phone, candidate_reason, confidence_score, candidate_status)
VALUES
(N'SAME_NATIONAL_ID_DIFFERENT_SOURCE', @benAhmed, @identityDupAhmed, @orgResala, '2990101123456', '01099000001', N'نفس الرقم القومي ظهر من مصدر/جمعية أخرى لنفس المستفيد', 95, N'OPEN'),
(N'SUPPORT_OVERLAP_SAME_MONTH', @benAhmed, NULL, @orgResala, '2990101123456', '01099000001', N'المستفيد طلب نفس نوع الدعم الغذائي من أكثر من جمعية في نفس الشهر', 92, N'OPEN');

INSERT INTO dbo.fraud_alerts
(alert_code, alert_type, severity, risk_score, beneficiary_id, identity_record_id, application_id, case_id, document_id, organization_id, description, created_at)
VALUES
('FRD-0001', N'CROSS_ORGANIZATION_SUPPORT_OVERLAP', N'HIGH', 92, @benAhmed, @identityDupAhmed, @app2, @case2, @doc2, @orgResala, N'المستفيد أحمد محمد علي طلب نفس نوع الدعم الغذائي من أكثر من جمعية خلال نفس الشهر.', DATEADD(day,-5,SYSUTCDATETIME())),
('FRD-0002', N'DOCUMENT_REUSE_REVIEW', N'MEDIUM', 78, @benAhmed, NULL, @app2, @case2, @doc2, @orgFood, N'مستند هوية مستخدم في أكثر من طلب مرتبط بجمعيات مختلفة. يحتاج مراجعة وليس رفض تلقائي.', DATEADD(day,-4,SYSUTCDATETIME()));

------------------------------------------------------------
-- Outbox events
------------------------------------------------------------
INSERT INTO dbo.platform_event_outbox
(event_type, payload, beneficiary_id, organization_id, application_id, case_id, fraud_alert_id)
SELECT
    N'FRAUD_ALERT_CREATED',
    CONCAT(N'{"alert_code":"', alert_code, N'","risk_score":', risk_score, N'}'),
    beneficiary_id,
    organization_id,
    application_id,
    case_id,
    fraud_alert_id
FROM dbo.fraud_alerts;

PRINT N'✅ Reference and demo seed data inserted successfully.';
GO



/* ============================================================
   END FILE: 02_seed_reference_and_demo_data.sql
   ============================================================ */




/* ============================================================
   START FILE: 03_create_dashboard_and_360_views.sql
   ============================================================ */



USE unified_charity_platform_clean;
GO

/* ============================================================
   CLEAN DATABASE V1 — Views for Dashboards + Beneficiary 360
   ============================================================ */

CREATE OR ALTER VIEW dbo.v_beneficiary_360 AS
SELECT
    b.beneficiary_id,
    b.beneficiary_code,
    b.national_id,
    b.full_name,
    b.phone,
    b.email,
    g.governorate_name_ar AS governorate,
    c.city_name_ar AS city,
    b.family_size,
    b.monthly_income,

    COUNT(DISTINCT r.organization_id) AS organizations_count,
    STRING_AGG(CAST(o.organization_name_ar AS NVARCHAR(MAX)), N'، ') AS organizations_names,

    COUNT(DISTINCT a.application_id) AS applications_count,
    SUM(CASE WHEN a.application_status = N'APPROVED' THEN 1 ELSE 0 END) AS approved_applications_count,
    SUM(CASE WHEN a.application_status = N'REJECTED' THEN 1 ELSE 0 END) AS rejected_applications_count,

    COUNT(DISTINCT cc.case_id) AS cases_count,
    SUM(CASE WHEN cc.case_status = N'OPEN' THEN 1 ELSE 0 END) AS open_cases_count,
    SUM(CASE WHEN cc.case_status IN (N'CLOSED', N'COMPLETED') THEN 1 ELSE 0 END) AS closed_cases_count,
    ISNULL(SUM(DISTINCT cc.required_amount), 0) AS total_required_amount,
    ISNULL(SUM(DISTINCT cc.collected_amount), 0) AS total_collected_amount,

    COUNT(DISTINCT fa.fraud_alert_id) AS fraud_alerts_count,
    COUNT(DISTINCT dc.duplicate_candidate_id) AS duplicate_candidates_count
FROM dbo.beneficiary_profiles b
LEFT JOIN dbo.governorates g ON b.governorate_id = g.governorate_id
LEFT JOIN dbo.cities c ON b.city_id = c.city_id
LEFT JOIN dbo.beneficiary_org_registrations r ON b.beneficiary_id = r.beneficiary_id
LEFT JOIN dbo.organizations o ON r.organization_id = o.organization_id
LEFT JOIN dbo.beneficiary_applications a ON b.beneficiary_id = a.beneficiary_id
LEFT JOIN dbo.charity_cases cc ON b.beneficiary_id = cc.beneficiary_id
LEFT JOIN dbo.fraud_alerts fa ON b.beneficiary_id = fa.beneficiary_id
LEFT JOIN dbo.duplicate_candidates dc ON b.beneficiary_id = dc.primary_beneficiary_id
GROUP BY
    b.beneficiary_id,
    b.beneficiary_code,
    b.national_id,
    b.full_name,
    b.phone,
    b.email,
    g.governorate_name_ar,
    c.city_name_ar,
    b.family_size,
    b.monthly_income;
GO

CREATE OR ALTER VIEW dbo.v_beneficiary_cross_organization AS
SELECT *
FROM dbo.v_beneficiary_360
WHERE organizations_count > 1;
GO

CREATE OR ALTER VIEW dbo.v_duplicate_beneficiary_candidates AS
SELECT
    dc.duplicate_candidate_id,
    dc.rule_code,
    dc.primary_beneficiary_id,
    b.beneficiary_code,
    b.full_name,
    b.national_id,
    dc.phone,
    dc.organization_id,
    o.organization_name_ar,
    dc.candidate_reason,
    dc.confidence_score,
    dc.candidate_status,
    dc.detected_at
FROM dbo.duplicate_candidates dc
LEFT JOIN dbo.beneficiary_profiles b
    ON dc.primary_beneficiary_id = b.beneficiary_id
LEFT JOIN dbo.organizations o
    ON dc.organization_id = o.organization_id;
GO

CREATE OR ALTER VIEW dbo.v_dashboard_government_summary AS
SELECT
    (SELECT COUNT(*) FROM dbo.organizations WHERE is_active = 1) AS organizations_count,
    (SELECT COUNT(*) FROM dbo.beneficiary_profiles WHERE is_active = 1) AS beneficiaries_count,
    (SELECT COUNT(*) FROM dbo.v_beneficiary_cross_organization) AS cross_organization_beneficiaries_count,
    (SELECT COUNT(*) FROM dbo.v_duplicate_beneficiary_candidates WHERE candidate_status = N'OPEN') AS open_duplicate_candidates_count,
    (SELECT COUNT(*) FROM dbo.fraud_alerts WHERE alert_status = N'OPEN') AS open_fraud_alerts_count,
    (SELECT COUNT(*) FROM dbo.beneficiary_applications) AS applications_count,
    (SELECT COUNT(*) FROM dbo.charity_cases) AS cases_count,
    (SELECT ISNULL(SUM(amount),0) FROM dbo.donations WHERE donation_status = N'COMPLETED') AS total_donations_amount;
GO

CREATE OR ALTER VIEW dbo.v_inventory_stock_summary AS
SELECT
    o.organization_name_ar,
    b.branch_name_ar,
    i.item_name_ar,
    s.quantity_on_hand,
    s.average_unit_cost,
    s.updated_at
FROM dbo.inventory_stock_balances s
JOIN dbo.organizations o ON s.organization_id = o.organization_id
LEFT JOIN dbo.branches b ON s.branch_id = b.branch_id
JOIN dbo.inventory_items i ON s.item_id = i.item_id;
GO

PRINT N'✅ Views created successfully.';
GO



/* ============================================================
   END FILE: 03_create_dashboard_and_360_views.sql
   ============================================================ */




/* ============================================================
   START FILE: 04_advanced_views_procedures_fraud_dq_CLEANED.sql
   ============================================================ */



USE unified_charity_platform_clean;
GO

/* ============================================================
   CLEAN DATABASE V2 — Advanced Engineering Layer
   Adds:
   - Sequences for business codes
   - Data quality tables
   - Advanced views
   - Business stored procedures
   - Fraud detection procedure
   - Outbox automation
   ============================================================ */

SET NOCOUNT ON;
GO

/* ============================================================
   1) Sequences for professional business codes
   ============================================================ */

IF NOT EXISTS (SELECT 1 FROM sys.sequences WHERE name = 'seq_application_code')
    EXEC('CREATE SEQUENCE dbo.seq_application_code AS INT START WITH 1000 INCREMENT BY 1;');
GO

IF NOT EXISTS (SELECT 1 FROM sys.sequences WHERE name = 'seq_case_code')
    EXEC('CREATE SEQUENCE dbo.seq_case_code AS INT START WITH 1000 INCREMENT BY 1;');
GO

IF NOT EXISTS (SELECT 1 FROM sys.sequences WHERE name = 'seq_donation_code')
    EXEC('CREATE SEQUENCE dbo.seq_donation_code AS INT START WITH 1000 INCREMENT BY 1;');
GO

IF NOT EXISTS (SELECT 1 FROM sys.sequences WHERE name = 'seq_inventory_code')
    EXEC('CREATE SEQUENCE dbo.seq_inventory_code AS INT START WITH 1000 INCREMENT BY 1;');
GO

IF NOT EXISTS (SELECT 1 FROM sys.sequences WHERE name = 'seq_fraud_alert_code')
    EXEC('CREATE SEQUENCE dbo.seq_fraud_alert_code AS INT START WITH 1000 INCREMENT BY 1;');
GO

IF NOT EXISTS (SELECT 1 FROM sys.sequences WHERE name = 'seq_duplicate_candidate_code')
    EXEC('CREATE SEQUENCE dbo.seq_duplicate_candidate_code AS INT START WITH 1000 INCREMENT BY 1;');
GO

/* ============================================================
   2) Data Quality tables
   ============================================================ */

IF OBJECT_ID('dbo.data_quality_rule_runs') IS NULL
BEGIN
    CREATE TABLE dbo.data_quality_rule_runs (
        dq_run_id BIGINT IDENTITY(1,1) PRIMARY KEY,
        run_uuid UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() UNIQUE,
        run_name NVARCHAR(150) NOT NULL,
        started_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        finished_at DATETIME2(0) NULL,
        run_status NVARCHAR(50) NOT NULL DEFAULT N'RUNNING',
        total_issues INT NOT NULL DEFAULT 0,
        notes NVARCHAR(1000) NULL
    );
END;
GO

IF OBJECT_ID('dbo.data_quality_issues') IS NULL
BEGIN
    CREATE TABLE dbo.data_quality_issues (
        dq_issue_id BIGINT IDENTITY(1,1) PRIMARY KEY,
        dq_run_id BIGINT NULL,
        rule_code NVARCHAR(100) NOT NULL,
        severity NVARCHAR(20) NOT NULL,
        entity_name NVARCHAR(100) NOT NULL,
        entity_id NVARCHAR(100) NULL,
        beneficiary_id INT NULL,
        organization_id INT NULL,
        issue_description NVARCHAR(1000) NOT NULL,
        issue_status NVARCHAR(50) NOT NULL DEFAULT N'OPEN',
        detected_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        resolved_by INT NULL,
        resolved_at DATETIME2(0) NULL,
        resolution_notes NVARCHAR(1000) NULL,

        CONSTRAINT fk_dq_issues_runs
            FOREIGN KEY (dq_run_id) REFERENCES dbo.data_quality_rule_runs(dq_run_id),
        CONSTRAINT fk_dq_issues_beneficiaries
            FOREIGN KEY (beneficiary_id) REFERENCES dbo.beneficiary_profiles(beneficiary_id),
        CONSTRAINT fk_dq_issues_organizations
            FOREIGN KEY (organization_id) REFERENCES dbo.organizations(organization_id),
        CONSTRAINT fk_dq_issues_resolved_by
            FOREIGN KEY (resolved_by) REFERENCES dbo.platform_users(user_id)
    );
END;
GO

/* ============================================================
   3) Helper functions
   ============================================================ */

CREATE OR ALTER FUNCTION dbo.fn_normalize_phone (@phone NVARCHAR(30))
RETURNS NVARCHAR(30)
AS
BEGIN
    DECLARE @p NVARCHAR(30) = ISNULL(@phone, N'');
    SET @p = REPLACE(@p, N' ', N'');
    SET @p = REPLACE(@p, N'-', N'');
    SET @p = REPLACE(@p, N'+2', N'');
    SET @p = REPLACE(@p, N'002', N'');
    RETURN @p;
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_case_coverage_percent (@required DECIMAL(18,2), @collected DECIMAL(18,2))
RETURNS DECIMAL(9,2)
AS
BEGIN
    IF ISNULL(@required, 0) <= 0 RETURN 0;
    RETURN CAST((ISNULL(@collected, 0) / @required) * 100 AS DECIMAL(9,2));
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_arabic_status (@status NVARCHAR(50))
RETURNS NVARCHAR(100)
AS
BEGIN
    RETURN CASE UPPER(ISNULL(@status, N''))
        WHEN N'SUBMITTED' THEN N'مقدم'
        WHEN N'UNDER_REVIEW' THEN N'قيد المراجعة'
        WHEN N'APPROVED' THEN N'مقبول'
        WHEN N'REJECTED' THEN N'مرفوض'
        WHEN N'OPEN' THEN N'مفتوحة'
        WHEN N'CLOSED' THEN N'مكتملة'
        WHEN N'COMPLETED' THEN N'مكتملة'
        WHEN N'PENDING_REVIEW' THEN N'قيد مراجعة المستندات'
        WHEN N'OPEN' THEN N'مفتوح'
        ELSE ISNULL(@status, N'غير محدد')
    END;
END;
GO

/* ============================================================
   4) Advanced Analytical Views
   ============================================================ */

CREATE OR ALTER VIEW dbo.v_beneficiary_support_timeline AS
SELECT
    b.beneficiary_id,
    b.beneficiary_code,
    b.national_id,
    b.full_name,
    a.submitted_at AS event_date,
    N'APPLICATION_SUBMITTED' AS event_type,
    N'تقديم طلب' AS event_type_ar,
    a.application_code AS reference_code,
    o.organization_name_ar,
    st.support_name_ar,
    a.requested_amount AS amount,
    CAST(NULL AS DECIMAL(18,2)) AS quantity,
    CONCAT(N'تم تقديم طلب ', st.support_name_ar, N' إلى ', o.organization_name_ar) AS description_ar
FROM dbo.beneficiary_applications a
JOIN dbo.beneficiary_profiles b ON a.beneficiary_id = b.beneficiary_id
JOIN dbo.organizations o ON a.organization_id = o.organization_id
JOIN dbo.support_types st ON a.support_type_id = st.support_type_id

UNION ALL

SELECT
    b.beneficiary_id,
    b.beneficiary_code,
    b.national_id,
    b.full_name,
    cc.published_at,
    N'CASE_CREATED',
    N'إنشاء حالة',
    cc.case_code,
    o.organization_name_ar,
    st.support_name_ar,
    cc.required_amount,
    CAST(NULL AS DECIMAL(18,2)),
    CONCAT(N'تم إنشاء حالة: ', cc.case_title)
FROM dbo.charity_cases cc
JOIN dbo.beneficiary_profiles b ON cc.beneficiary_id = b.beneficiary_id
JOIN dbo.organizations o ON cc.organization_id = o.organization_id
JOIN dbo.support_types st ON cc.support_type_id = st.support_type_id

UNION ALL

SELECT
    b.beneficiary_id,
    b.beneficiary_code,
    b.national_id,
    b.full_name,
    d.created_at,
    N'DONATION_RECEIVED',
    N'تبرع مالي',
    d.donation_code,
    o.organization_name_ar,
    st.support_name_ar,
    d.amount,
    CAST(NULL AS DECIMAL(18,2)),
    CONCAT(N'تم استقبال تبرع بقيمة ', FORMAT(d.amount, 'N0'), N' جنيه للحالة ', cc.case_code)
FROM dbo.donations d
JOIN dbo.charity_cases cc ON d.case_id = cc.case_id
JOIN dbo.beneficiary_profiles b ON cc.beneficiary_id = b.beneficiary_id
JOIN dbo.organizations o ON d.organization_id = o.organization_id
JOIN dbo.support_types st ON cc.support_type_id = st.support_type_id
WHERE d.case_id IS NOT NULL

UNION ALL

SELECT
    b.beneficiary_id,
    b.beneficiary_code,
    b.national_id,
    b.full_name,
    it.transaction_date,
    N'INVENTORY_OUT',
    N'صرف مخزون',
    it.transaction_code,
    o.organization_name_ar,
    st.support_name_ar,
    it.quantity * it.unit_cost,
    it.quantity,
    CONCAT(N'تم صرف ', FORMAT(it.quantity, 'N0'), N' ', ii.unit, N' من ', ii.item_name_ar)
FROM dbo.inventory_transactions it
JOIN dbo.charity_cases cc ON it.case_id = cc.case_id
JOIN dbo.beneficiary_profiles b ON cc.beneficiary_id = b.beneficiary_id
JOIN dbo.organizations o ON it.organization_id = o.organization_id
JOIN dbo.support_types st ON cc.support_type_id = st.support_type_id
JOIN dbo.inventory_items ii ON it.item_id = ii.item_id
WHERE it.transaction_type = N'OUT'

UNION ALL

SELECT
    b.beneficiary_id,
    b.beneficiary_code,
    b.national_id,
    b.full_name,
    fa.created_at,
    N'FRAUD_ALERT',
    N'تنبيه مخاطر',
    fa.alert_code,
    o.organization_name_ar,
    CAST(NULL AS NVARCHAR(150)),
    CAST(fa.risk_score AS DECIMAL(18,2)),
    CAST(NULL AS DECIMAL(18,2)),
    fa.description
FROM dbo.fraud_alerts fa
JOIN dbo.beneficiary_profiles b ON fa.beneficiary_id = b.beneficiary_id
LEFT JOIN dbo.organizations o ON fa.organization_id = o.organization_id;
GO

CREATE OR ALTER VIEW dbo.v_fraud_command_center AS
SELECT
    fa.fraud_alert_id,
    fa.alert_code,
    fa.alert_type,
    fa.severity,
    fa.risk_score,
    fa.alert_status,
    b.beneficiary_code,
    b.national_id,
    b.full_name AS beneficiary_name,
    o.organization_name_ar,
    a.application_code,
    cc.case_code,
    bd.document_code,
    d.donation_code,
    it.transaction_code,
    fa.description,
    fa.created_at,
    DATEDIFF(day, fa.created_at, SYSUTCDATETIME()) AS days_open,
    CASE
        WHEN fa.risk_score >= 90 THEN N'حرج'
        WHEN fa.risk_score >= 75 THEN N'عالي'
        WHEN fa.risk_score >= 50 THEN N'متوسط'
        ELSE N'منخفض'
    END AS risk_bucket_ar
FROM dbo.fraud_alerts fa
LEFT JOIN dbo.beneficiary_profiles b ON fa.beneficiary_id = b.beneficiary_id
LEFT JOIN dbo.organizations o ON fa.organization_id = o.organization_id
LEFT JOIN dbo.beneficiary_applications a ON fa.application_id = a.application_id
LEFT JOIN dbo.charity_cases cc ON fa.case_id = cc.case_id
LEFT JOIN dbo.beneficiary_documents bd ON fa.document_id = bd.document_id
LEFT JOIN dbo.donations d ON fa.donation_id = d.donation_id
LEFT JOIN dbo.inventory_transactions it ON fa.inventory_transaction_id = it.transaction_id;
GO

CREATE OR ALTER VIEW dbo.v_charity_performance_dashboard AS
SELECT
    o.organization_id,
    o.organization_code,
    o.organization_name_ar,
    COUNT(DISTINCT b.beneficiary_id) AS beneficiaries_served,
    COUNT(DISTINCT a.application_id) AS applications_count,
    SUM(CASE WHEN a.application_status = N'APPROVED' THEN 1 ELSE 0 END) AS approved_applications,
    SUM(CASE WHEN a.application_status = N'REJECTED' THEN 1 ELSE 0 END) AS rejected_applications,
    COUNT(DISTINCT cc.case_id) AS cases_count,
    SUM(CASE WHEN cc.case_status = N'OPEN' THEN 1 ELSE 0 END) AS open_cases,
    SUM(CASE WHEN cc.case_status IN (N'CLOSED', N'COMPLETED') THEN 1 ELSE 0 END) AS closed_cases,
    ISNULL(SUM(DISTINCT d.amount), 0) AS total_donations,
    COUNT(DISTINCT fa.fraud_alert_id) AS fraud_alerts_count
FROM dbo.organizations o
LEFT JOIN dbo.beneficiary_org_registrations r ON o.organization_id = r.organization_id
LEFT JOIN dbo.beneficiary_profiles b ON r.beneficiary_id = b.beneficiary_id
LEFT JOIN dbo.beneficiary_applications a ON o.organization_id = a.organization_id
LEFT JOIN dbo.charity_cases cc ON o.organization_id = cc.organization_id
LEFT JOIN dbo.donations d ON o.organization_id = d.organization_id
LEFT JOIN dbo.fraud_alerts fa ON o.organization_id = fa.organization_id
GROUP BY o.organization_id, o.organization_code, o.organization_name_ar;
GO

CREATE OR ALTER VIEW dbo.v_application_funnel AS
SELECT
    o.organization_name_ar,
    st.support_name_ar,
    COUNT(*) AS submitted_count,
    SUM(CASE WHEN application_status = N'UNDER_REVIEW' THEN 1 ELSE 0 END) AS under_review_count,
    SUM(CASE WHEN application_status = N'APPROVED' THEN 1 ELSE 0 END) AS approved_count,
    SUM(CASE WHEN application_status = N'REJECTED' THEN 1 ELSE 0 END) AS rejected_count,
    CAST(SUM(CASE WHEN application_status = N'APPROVED' THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*),0) AS DECIMAL(9,2)) AS approval_rate
FROM dbo.beneficiary_applications a
JOIN dbo.organizations o ON a.organization_id = o.organization_id
JOIN dbo.support_types st ON a.support_type_id = st.support_type_id
GROUP BY o.organization_name_ar, st.support_name_ar;
GO

CREATE OR ALTER VIEW dbo.v_inventory_risk_dashboard AS
SELECT
    o.organization_name_ar,
    b.branch_name_ar,
    i.item_name_ar,
    s.quantity_on_hand,
    s.average_unit_cost,
    CASE
        WHEN s.quantity_on_hand = 0 THEN N'نفذ المخزون'
        WHEN s.quantity_on_hand <= 5 THEN N'مخزون منخفض'
        ELSE N'مستقر'
    END AS stock_status_ar,
    s.updated_at
FROM dbo.inventory_stock_balances s
JOIN dbo.organizations o ON s.organization_id = o.organization_id
LEFT JOIN dbo.branches b ON s.branch_id = b.branch_id
JOIN dbo.inventory_items i ON s.item_id = i.item_id;
GO

CREATE OR ALTER VIEW dbo.v_data_quality_scorecard AS
SELECT
    severity,
    issue_status,
    COUNT(*) AS issues_count,
    MIN(detected_at) AS first_detected_at,
    MAX(detected_at) AS latest_detected_at
FROM dbo.data_quality_issues
GROUP BY severity, issue_status;
GO

/* ============================================================
   5) Business Stored Procedures
   ============================================================ */

CREATE OR ALTER PROCEDURE dbo.sp_submit_beneficiary_application
    @beneficiary_id INT,
    @organization_id INT,
    @branch_id INT = NULL,
    @support_type_id INT,
    @requested_amount DECIMAL(18,2) = NULL,
    @priority_level NVARCHAR(50) = N'MEDIUM',
    @admin_notes NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.beneficiary_profiles WHERE beneficiary_id = @beneficiary_id)
        THROW 53001, 'Beneficiary does not exist.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.organizations WHERE organization_id = @organization_id)
        THROW 53002, 'Organization does not exist.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.support_types WHERE support_type_id = @support_type_id)
        THROW 53003, 'Support type does not exist.', 1;

    DECLARE @application_code NVARCHAR(50) =
        CONCAT(N'APP-', FORMAT(NEXT VALUE FOR dbo.seq_application_code, '000000'));

    BEGIN TRAN;

    INSERT INTO dbo.beneficiary_applications
    (application_code, beneficiary_id, organization_id, branch_id, support_type_id,
     requested_amount, application_status, priority_level, admin_notes, submitted_at)
    VALUES
    (@application_code, @beneficiary_id, @organization_id, @branch_id, @support_type_id,
     @requested_amount, N'SUBMITTED', @priority_level, @admin_notes, SYSUTCDATETIME());

    DECLARE @application_id INT = SCOPE_IDENTITY();

    IF NOT EXISTS (
        SELECT 1 FROM dbo.beneficiary_org_registrations
        WHERE beneficiary_id = @beneficiary_id AND organization_id = @organization_id
    )
    BEGIN
        INSERT INTO dbo.beneficiary_org_registrations
        (beneficiary_id, organization_id, branch_id, registration_channel, notes)
        VALUES
        (@beneficiary_id, @organization_id, @branch_id, N'APPLICATION', N'Auto registration from application submission');
    END;

    INSERT INTO dbo.platform_event_outbox
    (event_type, payload, beneficiary_id, organization_id, branch_id, application_id)
    VALUES
    (N'BENEFICIARY_APPLICATION_SUBMITTED',
     CONCAT(N'{"application_code":"', @application_code, N'"}'),
     @beneficiary_id, @organization_id, @branch_id, @application_id);

    COMMIT;

    SELECT @application_id AS application_id, @application_code AS application_code;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_create_case_from_application
    @application_id INT,
    @case_title NVARCHAR(250),
    @case_description NVARCHAR(2000) = NULL,
    @required_amount DECIMAL(18,2),
    @published BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @beneficiary_id INT,
        @organization_id INT,
        @branch_id INT,
        @support_type_id INT,
        @status NVARCHAR(50);

    SELECT
        @beneficiary_id = beneficiary_id,
        @organization_id = organization_id,
        @branch_id = branch_id,
        @support_type_id = support_type_id,
        @status = application_status
    FROM dbo.beneficiary_applications
    WHERE application_id = @application_id;

    IF @beneficiary_id IS NULL
        THROW 53101, 'Application does not exist.', 1;

    IF @status NOT IN (N'APPROVED', N'UNDER_REVIEW')
        THROW 53102, 'Only approved or under-review applications can be converted to cases.', 1;

    DECLARE @case_code NVARCHAR(50) =
        CONCAT(N'CASE-', FORMAT(NEXT VALUE FOR dbo.seq_case_code, '000000'));

    INSERT INTO dbo.charity_cases
    (case_code, application_id, beneficiary_id, organization_id, branch_id, support_type_id,
     case_title, case_description, required_amount, collected_amount, case_status,
     priority_level, published_at)
    VALUES
    (@case_code, @application_id, @beneficiary_id, @organization_id, @branch_id, @support_type_id,
     @case_title, @case_description, @required_amount, 0,
     CASE WHEN @published = 1 THEN N'OPEN' ELSE N'DRAFT' END,
     N'MEDIUM',
     CASE WHEN @published = 1 THEN SYSUTCDATETIME() ELSE NULL END);

    DECLARE @case_id INT = SCOPE_IDENTITY();

    INSERT INTO dbo.platform_event_outbox
    (event_type, payload, beneficiary_id, organization_id, branch_id, application_id, case_id)
    VALUES
    (N'CHARITY_CASE_CREATED',
     CONCAT(N'{"case_code":"', @case_code, N'"}'),
     @beneficiary_id, @organization_id, @branch_id, @application_id, @case_id);

    SELECT @case_id AS case_id, @case_code AS case_code;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_record_donation
    @donor_name NVARCHAR(200),
    @donor_phone NVARCHAR(30) = NULL,
    @donor_email NVARCHAR(150) = NULL,
    @amount DECIMAL(18,2),
    @payment_method_id INT,
    @donation_target_type NVARCHAR(50),
    @organization_id INT = NULL,
    @case_id INT = NULL,
    @campaign_name NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @amount <= 0 THROW 53201, 'Donation amount must be greater than zero.', 1;

    IF @donation_target_type = N'CASE' AND @case_id IS NULL
        THROW 53202, 'CASE donation requires case_id.', 1;

    IF @donation_target_type = N'ORGANIZATION_GENERAL' AND @organization_id IS NULL
        THROW 53203, 'Organization general donation requires organization_id.', 1;

    IF @donation_target_type = N'CASE'
    BEGIN
        SELECT @organization_id = organization_id
        FROM dbo.charity_cases
        WHERE case_id = @case_id;
    END;

    DECLARE @donation_code NVARCHAR(50) =
        CONCAT(N'DON-', FORMAT(NEXT VALUE FOR dbo.seq_donation_code, '000000'));

    BEGIN TRAN;

    INSERT INTO dbo.donations
    (donation_code, donor_name, donor_phone, donor_email, organization_id, case_id,
     payment_method_id, amount, donation_target_type, campaign_name,
     donation_status, payment_status, idempotency_key, created_at)
    VALUES
    (@donation_code, @donor_name, @donor_phone, @donor_email, @organization_id, @case_id,
     @payment_method_id, @amount, @donation_target_type, @campaign_name,
     N'COMPLETED', N'SUCCESS', CONCAT(N'IDEMP-', @donation_code), SYSUTCDATETIME());

    DECLARE @donation_id INT = SCOPE_IDENTITY();

    IF @case_id IS NOT NULL
    BEGIN
        UPDATE dbo.charity_cases
        SET collected_amount = (
            SELECT ISNULL(SUM(amount),0)
            FROM dbo.donations
            WHERE case_id = @case_id
              AND donation_status = N'COMPLETED'
              AND payment_status = N'SUCCESS'
        )
        WHERE case_id = @case_id;

        UPDATE dbo.charity_cases
        SET case_status = N'CLOSED',
            closed_at = COALESCE(closed_at, SYSUTCDATETIME())
        WHERE case_id = @case_id
          AND collected_amount >= required_amount;
    END;

    INSERT INTO dbo.platform_event_outbox
    (event_type, payload, organization_id, case_id, donation_id)
    VALUES
    (N'DONATION_RECORDED',
     CONCAT(N'{"donation_code":"', @donation_code, N'","amount":', @amount, N'}'),
     @organization_id, @case_id, @donation_id);

    COMMIT;

    SELECT @donation_id AS donation_id, @donation_code AS donation_code;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_record_inventory_transaction
    @organization_id INT,
    @branch_id INT = NULL,
    @item_id INT,
    @transaction_type NVARCHAR(20),
    @quantity DECIMAL(18,2),
    @unit_cost DECIMAL(18,2) = NULL,
    @case_id INT = NULL,
    @application_id INT = NULL,
    @donation_id INT = NULL,
    @reference_type NVARCHAR(50) = NULL,
    @reference_id NVARCHAR(100) = NULL,
    @notes NVARCHAR(500) = NULL,
    @created_by INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @quantity <= 0 THROW 53301, 'Quantity must be greater than zero.', 1;

    IF @unit_cost IS NULL
        SELECT @unit_cost = default_unit_cost FROM dbo.inventory_items WHERE item_id = @item_id;

    IF @transaction_type = N'OUT' AND @case_id IS NULL AND ISNULL(@reference_type, N'') NOT IN (N'LOSS', N'DAMAGE', N'MANUAL_ADJUSTMENT')
        THROW 53302, 'Inventory OUT must be linked to a case unless it is loss/damage/manual adjustment.', 1;

    DECLARE @current_stock DECIMAL(18,2) =
    (
        SELECT ISNULL(quantity_on_hand, 0)
        FROM dbo.inventory_stock_balances
        WHERE organization_id = @organization_id
          AND ISNULL(branch_id, -1) = ISNULL(@branch_id, -1)
          AND item_id = @item_id
    );

    IF @transaction_type IN (N'OUT', N'LOSS') AND @current_stock < @quantity
        THROW 53303, 'Not enough stock for this OUT/LOSS transaction.', 1;

    DECLARE @transaction_code NVARCHAR(50) =
        CONCAT(N'INV-', FORMAT(NEXT VALUE FOR dbo.seq_inventory_code, '000000'));

    INSERT INTO dbo.inventory_transactions
    (transaction_code, organization_id, branch_id, item_id, transaction_type, quantity, unit_cost,
     case_id, application_id, donation_id, reference_type, reference_id, notes, created_by)
    VALUES
    (@transaction_code, @organization_id, @branch_id, @item_id, @transaction_type, @quantity, @unit_cost,
     @case_id, @application_id, @donation_id, @reference_type, @reference_id, @notes, @created_by);

    DECLARE @transaction_id INT = SCOPE_IDENTITY();

    INSERT INTO dbo.platform_event_outbox
    (event_type, payload, organization_id, branch_id, case_id, application_id, donation_id, inventory_transaction_id)
    VALUES
    (N'INVENTORY_TRANSACTION_RECORDED',
     CONCAT(N'{"transaction_code":"', @transaction_code, N'","type":"', @transaction_type, N'"}'),
     @organization_id, @branch_id, @case_id, @application_id, @donation_id, @transaction_id);

    SELECT @transaction_id AS transaction_id, @transaction_code AS transaction_code;
END;
GO

/* ============================================================
   6) Fraud + Data Quality Stored Procedures
   ============================================================ */

CREATE OR ALTER PROCEDURE dbo.sp_run_fraud_detection
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @inserted_duplicates INT = 0;
    DECLARE @inserted_alerts INT = 0;

    BEGIN TRAN;

    -- Rule 1: same national_id appears in raw identity records from multiple organizations.
    INSERT INTO dbo.duplicate_candidates
    (rule_code, primary_beneficiary_id, identity_record_id, organization_id, national_id, phone,
     candidate_reason, confidence_score, candidate_status)
    SELECT
        N'SAME_NATIONAL_ID_MULTIPLE_SOURCES',
        MIN(ir.matched_beneficiary_id),
        MIN(ir.identity_record_id),
        MIN(ir.organization_id),
        ir.national_id,
        MIN(ir.phone),
        N'نفس الرقم القومي ظهر في أكثر من مصدر أو جمعية.',
        95,
        N'OPEN'
    FROM dbo.beneficiary_identity_records ir
    WHERE ir.national_id IS NOT NULL
    GROUP BY ir.national_id
    HAVING COUNT(DISTINCT ISNULL(ir.organization_id, -1)) > 1
       AND NOT EXISTS (
            SELECT 1
            FROM dbo.duplicate_candidates dc
            WHERE dc.rule_code = N'SAME_NATIONAL_ID_MULTIPLE_SOURCES'
              AND dc.national_id = ir.national_id
              AND dc.candidate_status = N'OPEN'
       );

    SET @inserted_duplicates += @@ROWCOUNT;

    -- Rule 2: same support type from more than one organization in same month.
    INSERT INTO dbo.duplicate_candidates
    (rule_code, primary_beneficiary_id, organization_id, national_id, phone,
     candidate_reason, confidence_score, candidate_status)
    SELECT
        N'SUPPORT_OVERLAP_SAME_MONTH',
        a.beneficiary_id,
        MIN(a.organization_id),
        b.national_id,
        b.phone,
        CONCAT(N'المستفيد طلب نفس نوع الدعم من أكثر من جمعية في نفس الشهر: ', st.support_name_ar),
        90,
        N'OPEN'
    FROM dbo.beneficiary_applications a
    JOIN dbo.beneficiary_profiles b ON a.beneficiary_id = b.beneficiary_id
    JOIN dbo.support_types st ON a.support_type_id = st.support_type_id
    GROUP BY a.beneficiary_id, b.national_id, b.phone, a.support_type_id, st.support_name_ar, FORMAT(a.submitted_at, 'yyyy-MM')
    HAVING COUNT(DISTINCT a.organization_id) > 1
       AND NOT EXISTS (
            SELECT 1
            FROM dbo.duplicate_candidates dc
            WHERE dc.rule_code = N'SUPPORT_OVERLAP_SAME_MONTH'
              AND dc.primary_beneficiary_id = a.beneficiary_id
              AND dc.candidate_status = N'OPEN'
       );

    SET @inserted_duplicates += @@ROWCOUNT;

    -- Convert high-confidence duplicate candidates into fraud alerts.
    INSERT INTO dbo.fraud_alerts
    (alert_code, alert_type, severity, risk_score, alert_status, beneficiary_id, identity_record_id,
     organization_id, description, created_at)
    SELECT
        CONCAT(N'FRD-AUTO-', FORMAT(NEXT VALUE FOR dbo.seq_fraud_alert_code, '000000')),
        dc.rule_code,
        CASE WHEN dc.confidence_score >= 90 THEN N'HIGH' ELSE N'MEDIUM' END,
        dc.confidence_score,
        N'OPEN',
        dc.primary_beneficiary_id,
        dc.identity_record_id,
        dc.organization_id,
        dc.candidate_reason,
        SYSUTCDATETIME()
    FROM dbo.duplicate_candidates dc
    WHERE dc.candidate_status = N'OPEN'
      AND dc.confidence_score >= 85
      AND NOT EXISTS (
        SELECT 1
        FROM dbo.fraud_alerts fa
        WHERE fa.beneficiary_id = dc.primary_beneficiary_id
          AND fa.alert_type = dc.rule_code
          AND fa.alert_status = N'OPEN'
      );

    SET @inserted_alerts += @@ROWCOUNT;

    INSERT INTO dbo.platform_event_outbox
    (event_type, payload, beneficiary_id, organization_id, fraud_alert_id)
    SELECT
        N'FRAUD_ALERT_CREATED',
        CONCAT(N'{"alert_code":"', fa.alert_code, N'","risk_score":', fa.risk_score, N'}'),
        fa.beneficiary_id,
        fa.organization_id,
        fa.fraud_alert_id
    FROM dbo.fraud_alerts fa
    WHERE fa.created_at >= DATEADD(second, -10, SYSUTCDATETIME());

    COMMIT;

    SELECT
        @inserted_duplicates AS inserted_duplicate_candidates,
        @inserted_alerts AS inserted_fraud_alerts;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_run_data_quality_checks
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @run_id BIGINT;

    INSERT INTO dbo.data_quality_rule_runs (run_name)
    VALUES (N'Operational DB Data Quality Checks');

    SET @run_id = SCOPE_IDENTITY();

    -- Missing phone
    INSERT INTO dbo.data_quality_issues
    (dq_run_id, rule_code, severity, entity_name, entity_id, beneficiary_id, issue_description)
    SELECT
        @run_id,
        N'BENEFICIARY_MISSING_PHONE',
        N'MEDIUM',
        N'BENEFICIARY',
        beneficiary_code,
        beneficiary_id,
        N'المستفيد لا يحتوي على رقم هاتف.'
    FROM dbo.beneficiary_profiles
    WHERE phone IS NULL OR LTRIM(RTRIM(phone)) = N'';

    -- Open cases with zero required amount
    INSERT INTO dbo.data_quality_issues
    (dq_run_id, rule_code, severity, entity_name, entity_id, beneficiary_id, organization_id, issue_description)
    SELECT
        @run_id,
        N'CASE_INVALID_REQUIRED_AMOUNT',
        N'HIGH',
        N'CASE',
        case_code,
        beneficiary_id,
        organization_id,
        N'الحالة مفتوحة أو منشورة لكن قيمة الدعم المطلوبة غير صحيحة.'
    FROM dbo.charity_cases
    WHERE required_amount <= 0;

    -- Donations not linked correctly
    INSERT INTO dbo.data_quality_issues
    (dq_run_id, rule_code, severity, entity_name, entity_id, organization_id, issue_description)
    SELECT
        @run_id,
        N'DONATION_TARGET_INCONSISTENCY',
        N'HIGH',
        N'DONATION',
        donation_code,
        organization_id,
        N'نوع التبرع لا يتوافق مع case_id / organization_id.'
    FROM dbo.donations
    WHERE
        (donation_target_type = N'CASE' AND case_id IS NULL)
        OR (donation_target_type = N'ORGANIZATION_GENERAL' AND organization_id IS NULL)
        OR (donation_target_type = N'PLATFORM_GENERAL' AND case_id IS NOT NULL);

    UPDATE dbo.data_quality_rule_runs
    SET finished_at = SYSUTCDATETIME(),
        run_status = N'COMPLETED',
        total_issues = (SELECT COUNT(*) FROM dbo.data_quality_issues WHERE dq_run_id = @run_id)
    WHERE dq_run_id = @run_id;

    SELECT * FROM dbo.data_quality_rule_runs WHERE dq_run_id = @run_id;
    SELECT * FROM dbo.data_quality_issues WHERE dq_run_id = @run_id;
END;
GO

/* sp_get_beneficiary_360 is intentionally created later by the V2.1 final fixed section. */
GO

PRINT N'✅ Advanced objects created successfully.';
GO



/* ============================================================
   END FILE: 04_advanced_views_procedures_fraud_dq_CLEANED.sql
   ============================================================ */




/* ============================================================
   START FILE: 05_automation_triggers_and_indexes.sql
   ============================================================ */



USE unified_charity_platform_clean;
GO

/* ============================================================
   CLEAN DATABASE V2 — Automation Triggers + Performance Indexes
   ============================================================ */

SET NOCOUNT ON;
GO

/* ============================================================
   1) Recalculate case collected amount after donation changes
   ============================================================ */

CREATE OR ALTER TRIGGER dbo.trg_donations_recalculate_case_collected
ON dbo.donations
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH affected_cases AS (
        SELECT case_id FROM inserted WHERE case_id IS NOT NULL
        UNION
        SELECT case_id FROM deleted WHERE case_id IS NOT NULL
    )
    UPDATE cc
    SET collected_amount = x.total_collected,
        case_status = CASE
            WHEN x.total_collected >= cc.required_amount THEN N'CLOSED'
            ELSE cc.case_status
        END,
        closed_at = CASE
            WHEN x.total_collected >= cc.required_amount THEN COALESCE(cc.closed_at, SYSUTCDATETIME())
            ELSE cc.closed_at
        END
    FROM dbo.charity_cases cc
    JOIN affected_cases ac ON cc.case_id = ac.case_id
    CROSS APPLY (
        SELECT ISNULL(SUM(d.amount), 0) AS total_collected
        FROM dbo.donations d
        WHERE d.case_id = cc.case_id
          AND d.donation_status = N'COMPLETED'
          AND d.payment_status = N'SUCCESS'
    ) x;
END;
GO

/* ============================================================
   2) Recalculate stock balance after inventory changes
   Replaces the basic insert-only trigger from V1 with a stronger one.
   ============================================================ */

CREATE OR ALTER TRIGGER dbo.trg_inventory_update_stock_balance
ON dbo.inventory_transactions
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH affected AS (
        SELECT organization_id, branch_id, item_id FROM inserted
        UNION
        SELECT organization_id, branch_id, item_id FROM deleted
    ),
    recalculated AS (
        SELECT
            a.organization_id,
            a.branch_id,
            a.item_id,
            ISNULL(SUM(CASE
                WHEN it.transaction_type = N'IN' THEN it.quantity
                WHEN it.transaction_type IN (N'OUT', N'LOSS') THEN -it.quantity
                WHEN it.transaction_type = N'ADJUSTMENT' THEN it.quantity
                ELSE 0
            END), 0) AS quantity_on_hand,
            ISNULL(AVG(NULLIF(it.unit_cost,0)), 0) AS average_unit_cost
        FROM affected a
        LEFT JOIN dbo.inventory_transactions it
            ON a.organization_id = it.organization_id
           AND ISNULL(a.branch_id, -1) = ISNULL(it.branch_id, -1)
           AND a.item_id = it.item_id
        GROUP BY a.organization_id, a.branch_id, a.item_id
    )
    MERGE dbo.inventory_stock_balances AS target
    USING recalculated AS source
    ON target.organization_id = source.organization_id
       AND ISNULL(target.branch_id, -1) = ISNULL(source.branch_id, -1)
       AND target.item_id = source.item_id
    WHEN MATCHED THEN
        UPDATE SET
            quantity_on_hand = source.quantity_on_hand,
            average_unit_cost = source.average_unit_cost,
            updated_at = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (organization_id, branch_id, item_id, quantity_on_hand, average_unit_cost, updated_at)
        VALUES (source.organization_id, source.branch_id, source.item_id, source.quantity_on_hand, source.average_unit_cost, SYSUTCDATETIME());

    IF EXISTS (SELECT 1 FROM dbo.inventory_stock_balances WHERE quantity_on_hand < 0)
    BEGIN
        THROW 54001, 'Inventory stock cannot become negative.', 1;
    END;
END;
GO

/* ============================================================
   3) Outbox triggers for important business events
   ============================================================ */

CREATE OR ALTER TRIGGER dbo.trg_applications_outbox
ON dbo.beneficiary_applications
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.platform_event_outbox
    (event_type, payload, beneficiary_id, organization_id, branch_id, application_id)
    SELECT
        N'BENEFICIARY_APPLICATION_SUBMITTED',
        CONCAT(N'{"application_code":"', i.application_code, N'"}'),
        i.beneficiary_id,
        i.organization_id,
        i.branch_id,
        i.application_id
    FROM inserted i;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_cases_outbox
ON dbo.charity_cases
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.platform_event_outbox
    (event_type, payload, beneficiary_id, organization_id, branch_id, application_id, case_id)
    SELECT
        N'CHARITY_CASE_CREATED',
        CONCAT(N'{"case_code":"', i.case_code, N'"}'),
        i.beneficiary_id,
        i.organization_id,
        i.branch_id,
        i.application_id,
        i.case_id
    FROM inserted i;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_fraud_alerts_outbox
ON dbo.fraud_alerts
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.platform_event_outbox
    (event_type, payload, beneficiary_id, organization_id, application_id, case_id, document_id, donation_id, inventory_transaction_id, fraud_alert_id)
    SELECT
        N'FRAUD_ALERT_CREATED',
        CONCAT(N'{"alert_code":"', i.alert_code, N'","risk_score":', i.risk_score, N'}'),
        i.beneficiary_id,
        i.organization_id,
        i.application_id,
        i.case_id,
        i.document_id,
        i.donation_id,
        i.inventory_transaction_id,
        i.fraud_alert_id
    FROM inserted i;
END;
GO

/* ============================================================
   4) Performance Indexes
   ============================================================ */

CREATE INDEX ix_beneficiary_profiles_national_id
ON dbo.beneficiary_profiles(national_id);

CREATE INDEX ix_beneficiary_profiles_location
ON dbo.beneficiary_profiles(governorate_id, city_id);

CREATE INDEX ix_identity_records_national_phone
ON dbo.beneficiary_identity_records(national_id, phone);

CREATE INDEX ix_applications_beneficiary_date
ON dbo.beneficiary_applications(beneficiary_id, submitted_at DESC);

CREATE INDEX ix_applications_org_status
ON dbo.beneficiary_applications(organization_id, application_status, submitted_at DESC);

CREATE INDEX ix_cases_beneficiary_status
ON dbo.charity_cases(beneficiary_id, case_status);

CREATE INDEX ix_cases_org_status
ON dbo.charity_cases(organization_id, case_status);

CREATE INDEX ix_donations_case_date
ON dbo.donations(case_id, created_at DESC);

CREATE INDEX ix_inventory_org_item_date
ON dbo.inventory_transactions(organization_id, item_id, transaction_date DESC);

CREATE INDEX ix_fraud_alerts_beneficiary_status
ON dbo.fraud_alerts(beneficiary_id, alert_status, risk_score DESC);

CREATE INDEX ix_fraud_alerts_status_risk
ON dbo.fraud_alerts(alert_status, risk_score DESC);

CREATE INDEX ix_duplicate_candidates_beneficiary_status
ON dbo.duplicate_candidates(primary_beneficiary_id, candidate_status, confidence_score DESC);

CREATE INDEX ix_outbox_status_created
ON dbo.platform_event_outbox(event_status, created_at);
GO

PRINT N'✅ Automation triggers and indexes created successfully.';
GO



/* ============================================================
   END FILE: 05_automation_triggers_and_indexes.sql
   ============================================================ */




/* ============================================================
   START FILE: 07_V2_1_FINAL_FIX_beneficiary_360_proc.sql
   ============================================================ */



USE unified_charity_platform_clean;
GO

/* ============================================================
   V2.1 FINAL FIX — Beneficiary 360 Procedure
   Fixes:
   - Invalid column name 'beneficiary_id' inside sp_get_beneficiary_360
   - Makes the procedure independent from view column issues
   - Recreates the views with explicit IDs
   ============================================================ */

SET NOCOUNT ON;
GO

------------------------------------------------------------
-- 1) Recreate duplicate candidates view with explicit IDs
------------------------------------------------------------
CREATE OR ALTER VIEW dbo.v_duplicate_beneficiary_candidates AS
SELECT
    dc.duplicate_candidate_id,
    dc.rule_code,

    -- Explicit IDs
    dc.primary_beneficiary_id,
    dc.duplicate_beneficiary_id,
    dc.identity_record_id,
    dc.organization_id,

    b.beneficiary_code,
    b.full_name,
    b.national_id,
    dc.phone,
    o.organization_name_ar,
    dc.candidate_reason,
    dc.confidence_score,
    dc.candidate_status,
    dc.detected_at,
    dc.resolved_by,
    dc.resolved_at,
    dc.resolution_notes
FROM dbo.duplicate_candidates dc
LEFT JOIN dbo.beneficiary_profiles b
    ON dc.primary_beneficiary_id = b.beneficiary_id
LEFT JOIN dbo.organizations o
    ON dc.organization_id = o.organization_id;
GO

------------------------------------------------------------
-- 2) Recreate fraud command center view with explicit IDs
------------------------------------------------------------
CREATE OR ALTER VIEW dbo.v_fraud_command_center AS
SELECT
    fa.fraud_alert_id,
    fa.alert_code,
    fa.alert_type,
    fa.severity,
    fa.risk_score,
    fa.alert_status,

    -- Explicit IDs for filtering and APIs
    fa.beneficiary_id,
    fa.identity_record_id,
    fa.organization_id,
    fa.application_id,
    fa.case_id,
    fa.document_id,
    fa.donation_id,
    fa.inventory_transaction_id,

    b.beneficiary_code,
    b.national_id,
    b.full_name AS beneficiary_name,
    o.organization_name_ar,
    a.application_code,
    cc.case_code,
    bd.document_code,
    d.donation_code,
    it.transaction_code,

    fa.description,
    fa.created_at,
    DATEDIFF(day, fa.created_at, SYSUTCDATETIME()) AS days_open,
    CASE
        WHEN fa.risk_score >= 90 THEN N'حرج'
        WHEN fa.risk_score >= 75 THEN N'عالي'
        WHEN fa.risk_score >= 50 THEN N'متوسط'
        ELSE N'منخفض'
    END AS risk_bucket_ar
FROM dbo.fraud_alerts fa
LEFT JOIN dbo.beneficiary_profiles b
    ON fa.beneficiary_id = b.beneficiary_id
LEFT JOIN dbo.organizations o
    ON fa.organization_id = o.organization_id
LEFT JOIN dbo.beneficiary_applications a
    ON fa.application_id = a.application_id
LEFT JOIN dbo.charity_cases cc
    ON fa.case_id = cc.case_id
LEFT JOIN dbo.beneficiary_documents bd
    ON fa.document_id = bd.document_id
LEFT JOIN dbo.donations d
    ON fa.donation_id = d.donation_id
LEFT JOIN dbo.inventory_transactions it
    ON fa.inventory_transaction_id = it.transaction_id;
GO

------------------------------------------------------------
-- 3) Recreate Beneficiary 360 procedure safely
-- Important:
-- The fraud and duplicate result sets filter from base tables first,
-- not only from views, so it will not fail if view columns differ.
------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.sp_get_beneficiary_360
    @national_id NVARCHAR(30) = NULL,
    @beneficiary_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @beneficiary_id IS NULL
    BEGIN
        SELECT @beneficiary_id = beneficiary_id
        FROM dbo.beneficiary_profiles
        WHERE national_id = @national_id;
    END;

    IF @beneficiary_id IS NULL
        THROW 53401, 'Beneficiary not found.', 1;

    --------------------------------------------------------
    -- 1) Summary profile
    --------------------------------------------------------
    SELECT *
    FROM dbo.v_beneficiary_360
    WHERE beneficiary_id = @beneficiary_id;

    --------------------------------------------------------
    -- 2) Applications
    --------------------------------------------------------
    SELECT
        a.application_id,
        a.application_code,
        a.beneficiary_id,
        a.organization_id,
        o.organization_name_ar,
        a.branch_id,
        br.branch_name_ar,
        a.support_type_id,
        st.support_name_ar,
        a.requested_amount,
        a.application_status,
        dbo.fn_arabic_status(a.application_status) AS application_status_ar,
        a.priority_level,
        a.submitted_at,
        a.reviewed_by,
        a.reviewed_at,
        a.admin_notes,
        a.assignment_reason
    FROM dbo.beneficiary_applications a
    JOIN dbo.organizations o
        ON a.organization_id = o.organization_id
    LEFT JOIN dbo.branches br
        ON a.branch_id = br.branch_id
    JOIN dbo.support_types st
        ON a.support_type_id = st.support_type_id
    WHERE a.beneficiary_id = @beneficiary_id
    ORDER BY a.submitted_at DESC;

    --------------------------------------------------------
    -- 3) Cases
    --------------------------------------------------------
    SELECT
        c.case_id,
        c.case_code,
        c.application_id,
        c.beneficiary_id,
        c.organization_id,
        o.organization_name_ar,
        c.branch_id,
        br.branch_name_ar,
        c.support_type_id,
        st.support_name_ar,
        c.case_title,
        c.case_description,
        c.required_amount,
        c.collected_amount,
        dbo.fn_case_coverage_percent(c.required_amount, c.collected_amount) AS coverage_percent,
        c.case_status,
        dbo.fn_arabic_status(c.case_status) AS case_status_ar,
        c.priority_level,
        c.published_at,
        c.closed_at,
        c.created_at
    FROM dbo.charity_cases c
    JOIN dbo.organizations o
        ON c.organization_id = o.organization_id
    LEFT JOIN dbo.branches br
        ON c.branch_id = br.branch_id
    JOIN dbo.support_types st
        ON c.support_type_id = st.support_type_id
    WHERE c.beneficiary_id = @beneficiary_id
    ORDER BY c.created_at DESC;

    --------------------------------------------------------
    -- 4) Timeline
    --------------------------------------------------------
    SELECT *
    FROM dbo.v_beneficiary_support_timeline
    WHERE beneficiary_id = @beneficiary_id
    ORDER BY event_date DESC;

    --------------------------------------------------------
    -- 5) Fraud alerts
    -- Filter from base table to avoid invalid view column issues.
    --------------------------------------------------------
    SELECT fcc.*
    FROM dbo.v_fraud_command_center fcc
    JOIN dbo.fraud_alerts fa
        ON fcc.fraud_alert_id = fa.fraud_alert_id
    WHERE fa.beneficiary_id = @beneficiary_id
    ORDER BY fcc.created_at DESC;

    --------------------------------------------------------
    -- 6) Duplicate candidates
    -- Filter from base table to avoid invalid view column issues.
    --------------------------------------------------------
    SELECT vdc.*
    FROM dbo.v_duplicate_beneficiary_candidates vdc
    JOIN dbo.duplicate_candidates dc
        ON vdc.duplicate_candidate_id = dc.duplicate_candidate_id
    WHERE dc.primary_beneficiary_id = @beneficiary_id
       OR dc.duplicate_beneficiary_id = @beneficiary_id
    ORDER BY vdc.detected_at DESC;
END;
GO

------------------------------------------------------------
-- 4) Quick validation
------------------------------------------------------------
PRINT N'✅ V2.1 Beneficiary 360 procedure fixed successfully.';

PRINT N'Check v_fraud_command_center columns:';
SELECT TOP 1
    fraud_alert_id,
    beneficiary_id,
    alert_code,
    risk_score
FROM dbo.v_fraud_command_center;

PRINT N'Check v_duplicate_beneficiary_candidates columns:';
SELECT TOP 1
    duplicate_candidate_id,
    primary_beneficiary_id,
    rule_code,
    confidence_score
FROM dbo.v_duplicate_beneficiary_candidates;

GO



/* ============================================================
   END FILE: 07_V2_1_FINAL_FIX_beneficiary_360_proc.sql
   ============================================================ */




/* ============================================================
   START FILE: FINAL_VALIDATION.sql
   ============================================================ */



USE unified_charity_platform_clean;
GO

/* ============================================================
   FINAL QUICK VALIDATION — NO ERROR VERSION
   ============================================================ */

PRINT N'✅ All-in-one NO ERRORS database script completed.';
PRINT N'Quick validation results:';

SELECT N'Government Summary' AS section_name, *
FROM dbo.v_dashboard_government_summary;

SELECT N'Beneficiary 360 Rows' AS section_name, COUNT(*) AS row_count
FROM dbo.v_beneficiary_360;

SELECT N'Fraud Alerts' AS section_name, COUNT(*) AS row_count
FROM dbo.fraud_alerts;

SELECT N'Duplicate Candidates' AS section_name, COUNT(*) AS row_count
FROM dbo.duplicate_candidates;

SELECT N'Pending Outbox Events' AS section_name, COUNT(*) AS row_count
FROM dbo.platform_event_outbox
WHERE event_status = N'PENDING';

PRINT N'✅ Beneficiary 360 procedure smoke test:';
EXEC dbo.sp_get_beneficiary_360 @national_id = '2990101123456';
GO



/* ============================================================
   END FILE: FINAL_VALIDATION.sql
   ============================================================ */

   USE unified_charity_platform_clean;
GO

SELECT * FROM dbo.v_dashboard_government_summary;
SELECT * FROM dbo.v_beneficiary_360;
SELECT * FROM dbo.v_fraud_command_center;
SELECT * FROM dbo.v_duplicate_beneficiary_candidates;

EXEC dbo.sp_get_beneficiary_360 @national_id = '2990101123456';


/* =============================== END INCLUDED FILE ============================== */


/* ==============================================================================
   START INCLUDED FILE: 10_PHASE_2_BUSINESS_SCHEMA.sql
   ============================================================================== */

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


/* =============================== END INCLUDED FILE ============================== */


/* ==============================================================================
   START INCLUDED FILE: 11_PHASE_3_MINIO_VALIDATION_PRESENTATION_READY.sql
   ============================================================================== */

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


/* =============================== END INCLUDED FILE ============================== */


/* ==============================================================================
   START INCLUDED FILE: 01_create_three_charity_operational_dbs.sql
   ============================================================================== */

/*
================================================================================
Unified Charity Platform - Three Independent Charity Operational Databases
================================================================================
Purpose:
    This script creates a realistic OLTP schema inside each charity source DB.
    It replaces the old "3 source schemas inside one DB" simulation when you want
    the database layer to look like the architecture diagram.

Important:
    - This does NOT replace unified_charity_platform_clean.
    - The platform backend should keep using unified_charity_platform_clean.
    - These 3 DBs are source systems for CDC/Debezium/Kafka or batch ingestion.
================================================================================
*/

/*===============================================================================
Reusable pattern:
Each charity DB owns its daily operational data:
    branches, staff_users, beneficiaries, applications, cases, donors, donations,
    inventory_items, inventory_transactions, beneficiary_documents, source_event_outbox
===============================================================================*/

/* ========================= FOOD BANK ========================= */
USE charity_food_bank_operational;
GO

IF OBJECT_ID('dbo.source_system_settings', 'U') IS NULL
CREATE TABLE dbo.source_system_settings (
    setting_key NVARCHAR(100) NOT NULL PRIMARY KEY,
    setting_value NVARCHAR(300) NOT NULL
);
GO

MERGE dbo.source_system_settings AS t
USING (VALUES
    (N'SOURCE_ORGANIZATION_CODE', N'FOOD_BANK'),
    (N'SOURCE_ORGANIZATION_NAME', N'Food Bank System')
) AS s(setting_key, setting_value)
ON t.setting_key = s.setting_key
WHEN MATCHED THEN UPDATE SET setting_value = s.setting_value
WHEN NOT MATCHED THEN INSERT (setting_key, setting_value) VALUES (s.setting_key, s.setting_value);
GO

IF OBJECT_ID('dbo.branches', 'U') IS NULL
CREATE TABLE dbo.branches (
    source_branch_id INT IDENTITY(1,1) PRIMARY KEY,
    branch_code NVARCHAR(50) NOT NULL UNIQUE,
    branch_name NVARCHAR(200) NOT NULL,
    governorate_name NVARCHAR(100) NOT NULL,
    city_name NVARCHAR(100) NOT NULL,
    address NVARCHAR(300) NULL,
    phone NVARCHAR(30) NULL,
    is_active BIT NOT NULL DEFAULT 1,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at DATETIME2(0) NULL
);
GO

IF OBJECT_ID('dbo.staff_users', 'U') IS NULL
CREATE TABLE dbo.staff_users (
    source_user_id INT IDENTITY(1,1) PRIMARY KEY,
    user_code NVARCHAR(50) NOT NULL UNIQUE,
    source_branch_id INT NULL,
    full_name NVARCHAR(200) NOT NULL,
    email NVARCHAR(150) NULL,
    phone NVARCHAR(30) NULL,
    role_code NVARCHAR(50) NOT NULL DEFAULT N'CHARITY_STAFF',
    is_active BIT NOT NULL DEFAULT 1,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at DATETIME2(0) NULL,
    CONSTRAINT fk_fb_staff_branch FOREIGN KEY (source_branch_id) REFERENCES dbo.branches(source_branch_id)
);
GO

IF OBJECT_ID('dbo.beneficiaries', 'U') IS NULL
CREATE TABLE dbo.beneficiaries (
    source_beneficiary_id INT IDENTITY(1,1) PRIMARY KEY,
    national_id NVARCHAR(30) NOT NULL,
    full_name NVARCHAR(200) NOT NULL,
    gender NVARCHAR(20) NULL,
    birth_date DATE NULL,
    phone NVARCHAR(30) NULL,
    email NVARCHAR(150) NULL,
    governorate_name NVARCHAR(100) NOT NULL,
    city_name NVARCHAR(100) NOT NULL,
    address NVARCHAR(300) NULL,
    family_size INT NULL,
    monthly_income DECIMAL(18,2) NULL,
    employment_status NVARCHAR(100) NULL,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at DATETIME2(0) NULL,
    CONSTRAINT ck_fb_beneficiary_family CHECK (family_size IS NULL OR family_size >= 1),
    CONSTRAINT ck_fb_beneficiary_income CHECK (monthly_income IS NULL OR monthly_income >= 0)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_fb_beneficiaries_national_id' AND object_id = OBJECT_ID('dbo.beneficiaries'))
CREATE INDEX ix_fb_beneficiaries_national_id ON dbo.beneficiaries(national_id);
GO

IF OBJECT_ID('dbo.applications', 'U') IS NULL
CREATE TABLE dbo.applications (
    source_application_id INT IDENTITY(1,1) PRIMARY KEY,
    application_code NVARCHAR(50) NOT NULL UNIQUE,
    source_beneficiary_id INT NOT NULL,
    source_branch_id INT NULL,
    support_type_name NVARCHAR(150) NOT NULL,
    requested_amount DECIMAL(18,2) NULL,
    application_status NVARCHAR(50) NOT NULL DEFAULT N'SUBMITTED',
    priority_level NVARCHAR(50) NOT NULL DEFAULT N'MEDIUM',
    submitted_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    reviewed_at DATETIME2(0) NULL,
    staff_notes NVARCHAR(1000) NULL,
    updated_at DATETIME2(0) NULL,
    CONSTRAINT fk_fb_app_beneficiary FOREIGN KEY (source_beneficiary_id) REFERENCES dbo.beneficiaries(source_beneficiary_id),
    CONSTRAINT fk_fb_app_branch FOREIGN KEY (source_branch_id) REFERENCES dbo.branches(source_branch_id)
);
GO

IF OBJECT_ID('dbo.cases', 'U') IS NULL
CREATE TABLE dbo.cases (
    source_case_id INT IDENTITY(1,1) PRIMARY KEY,
    case_code NVARCHAR(50) NOT NULL UNIQUE,
    source_application_id INT NULL,
    source_beneficiary_id INT NOT NULL,
    source_branch_id INT NULL,
    case_title NVARCHAR(200) NOT NULL,
    support_type_name NVARCHAR(150) NOT NULL,
    case_status NVARCHAR(50) NOT NULL DEFAULT N'OPEN',
    target_amount DECIMAL(18,2) NULL,
    collected_amount DECIMAL(18,2) NOT NULL DEFAULT 0,
    opened_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    closed_at DATETIME2(0) NULL,
    updated_at DATETIME2(0) NULL,
    CONSTRAINT fk_fb_case_application FOREIGN KEY (source_application_id) REFERENCES dbo.applications(source_application_id),
    CONSTRAINT fk_fb_case_beneficiary FOREIGN KEY (source_beneficiary_id) REFERENCES dbo.beneficiaries(source_beneficiary_id),
    CONSTRAINT fk_fb_case_branch FOREIGN KEY (source_branch_id) REFERENCES dbo.branches(source_branch_id)
);
GO

IF OBJECT_ID('dbo.donors', 'U') IS NULL
CREATE TABLE dbo.donors (
    source_donor_id INT IDENTITY(1,1) PRIMARY KEY,
    donor_code NVARCHAR(50) NOT NULL UNIQUE,
    donor_name NVARCHAR(200) NOT NULL,
    phone NVARCHAR(30) NULL,
    email NVARCHAR(150) NULL,
    donor_category NVARCHAR(100) NULL,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at DATETIME2(0) NULL
);
GO

IF OBJECT_ID('dbo.donations', 'U') IS NULL
CREATE TABLE dbo.donations (
    source_donation_id INT IDENTITY(1,1) PRIMARY KEY,
    donation_code NVARCHAR(50) NOT NULL UNIQUE,
    source_donor_id INT NULL,
    source_case_id INT NULL,
    source_branch_id INT NULL,
    amount DECIMAL(18,2) NOT NULL,
    payment_method_name NVARCHAR(100) NULL,
    donation_status NVARCHAR(50) NOT NULL DEFAULT N'COMPLETED',
    donated_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    notes NVARCHAR(500) NULL,
    updated_at DATETIME2(0) NULL,
    CONSTRAINT fk_fb_donation_donor FOREIGN KEY (source_donor_id) REFERENCES dbo.donors(source_donor_id),
    CONSTRAINT fk_fb_donation_case FOREIGN KEY (source_case_id) REFERENCES dbo.cases(source_case_id),
    CONSTRAINT fk_fb_donation_branch FOREIGN KEY (source_branch_id) REFERENCES dbo.branches(source_branch_id),
    CONSTRAINT ck_fb_donation_amount CHECK (amount > 0)
);
GO

IF OBJECT_ID('dbo.inventory_items', 'U') IS NULL
CREATE TABLE dbo.inventory_items (
    source_item_id INT IDENTITY(1,1) PRIMARY KEY,
    item_code NVARCHAR(50) NOT NULL UNIQUE,
    item_name NVARCHAR(150) NOT NULL,
    item_category NVARCHAR(100) NULL,
    unit NVARCHAR(50) NOT NULL,
    default_unit_cost DECIMAL(18,2) NOT NULL DEFAULT 0,
    is_active BIT NOT NULL DEFAULT 1,
    updated_at DATETIME2(0) NULL
);
GO

IF OBJECT_ID('dbo.inventory_transactions', 'U') IS NULL
CREATE TABLE dbo.inventory_transactions (
    source_inventory_transaction_id INT IDENTITY(1,1) PRIMARY KEY,
    transaction_code NVARCHAR(50) NOT NULL UNIQUE,
    source_branch_id INT NULL,
    source_item_id INT NOT NULL,
    source_case_id INT NULL,
    transaction_type NVARCHAR(20) NOT NULL,
    quantity DECIMAL(18,2) NOT NULL,
    unit_cost DECIMAL(18,2) NOT NULL DEFAULT 0,
    transaction_date DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    notes NVARCHAR(500) NULL,
    updated_at DATETIME2(0) NULL,
    CONSTRAINT fk_fb_inv_branch FOREIGN KEY (source_branch_id) REFERENCES dbo.branches(source_branch_id),
    CONSTRAINT fk_fb_inv_item FOREIGN KEY (source_item_id) REFERENCES dbo.inventory_items(source_item_id),
    CONSTRAINT fk_fb_inv_case FOREIGN KEY (source_case_id) REFERENCES dbo.cases(source_case_id),
    CONSTRAINT ck_fb_inv_qty CHECK (quantity > 0),
    CONSTRAINT ck_fb_inv_unit_cost CHECK (unit_cost >= 0)
);
GO

IF OBJECT_ID('dbo.beneficiary_documents', 'U') IS NULL
CREATE TABLE dbo.beneficiary_documents (
    source_document_id INT IDENTITY(1,1) PRIMARY KEY,
    source_beneficiary_id INT NOT NULL,
    source_application_id INT NULL,
    document_type_name NVARCHAR(150) NOT NULL,
    file_name NVARCHAR(255) NOT NULL,
    object_store_key NVARCHAR(500) NULL,
    file_url NVARCHAR(1000) NULL,
    verification_status NVARCHAR(50) NOT NULL DEFAULT N'PENDING',
    uploaded_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at DATETIME2(0) NULL,
    CONSTRAINT fk_fb_doc_beneficiary FOREIGN KEY (source_beneficiary_id) REFERENCES dbo.beneficiaries(source_beneficiary_id),
    CONSTRAINT fk_fb_doc_application FOREIGN KEY (source_application_id) REFERENCES dbo.applications(source_application_id)
);
GO

IF OBJECT_ID('dbo.source_event_outbox', 'U') IS NULL
CREATE TABLE dbo.source_event_outbox (
    source_event_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    event_uuid UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() UNIQUE,
    event_type NVARCHAR(100) NOT NULL,
    entity_name NVARCHAR(100) NOT NULL,
    entity_id NVARCHAR(100) NOT NULL,
    payload_json NVARCHAR(MAX) NULL,
    event_status NVARCHAR(50) NOT NULL DEFAULT N'PENDING',
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    published_at DATETIME2(0) NULL
);
GO

/* ========================= RESALA ========================= */
USE charity_resala_operational;
GO

IF OBJECT_ID('dbo.source_system_settings', 'U') IS NULL
CREATE TABLE dbo.source_system_settings (
    setting_key NVARCHAR(100) NOT NULL PRIMARY KEY,
    setting_value NVARCHAR(300) NOT NULL
);
GO

MERGE dbo.source_system_settings AS t
USING (VALUES
    (N'SOURCE_ORGANIZATION_CODE', N'RESALA'),
    (N'SOURCE_ORGANIZATION_NAME', N'Resala System')
) AS s(setting_key, setting_value)
ON t.setting_key = s.setting_key
WHEN MATCHED THEN UPDATE SET setting_value = s.setting_value
WHEN NOT MATCHED THEN INSERT (setting_key, setting_value) VALUES (s.setting_key, s.setting_value);
GO

IF OBJECT_ID('dbo.branches', 'U') IS NULL
CREATE TABLE dbo.branches (
    source_branch_id INT IDENTITY(1,1) PRIMARY KEY,
    branch_code NVARCHAR(50) NOT NULL UNIQUE,
    branch_name NVARCHAR(200) NOT NULL,
    governorate_name NVARCHAR(100) NOT NULL,
    city_name NVARCHAR(100) NOT NULL,
    address NVARCHAR(300) NULL,
    phone NVARCHAR(30) NULL,
    is_active BIT NOT NULL DEFAULT 1,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at DATETIME2(0) NULL
);
GO

IF OBJECT_ID('dbo.staff_users', 'U') IS NULL
CREATE TABLE dbo.staff_users (
    source_user_id INT IDENTITY(1,1) PRIMARY KEY,
    user_code NVARCHAR(50) NOT NULL UNIQUE,
    source_branch_id INT NULL,
    full_name NVARCHAR(200) NOT NULL,
    email NVARCHAR(150) NULL,
    phone NVARCHAR(30) NULL,
    role_code NVARCHAR(50) NOT NULL DEFAULT N'CHARITY_STAFF',
    is_active BIT NOT NULL DEFAULT 1,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at DATETIME2(0) NULL,
    CONSTRAINT fk_res_staff_branch FOREIGN KEY (source_branch_id) REFERENCES dbo.branches(source_branch_id)
);
GO

IF OBJECT_ID('dbo.beneficiaries', 'U') IS NULL
CREATE TABLE dbo.beneficiaries (
    source_beneficiary_id INT IDENTITY(1,1) PRIMARY KEY,
    national_id NVARCHAR(30) NOT NULL,
    full_name NVARCHAR(200) NOT NULL,
    gender NVARCHAR(20) NULL,
    birth_date DATE NULL,
    phone NVARCHAR(30) NULL,
    email NVARCHAR(150) NULL,
    governorate_name NVARCHAR(100) NOT NULL,
    city_name NVARCHAR(100) NOT NULL,
    address NVARCHAR(300) NULL,
    family_size INT NULL,
    monthly_income DECIMAL(18,2) NULL,
    employment_status NVARCHAR(100) NULL,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at DATETIME2(0) NULL,
    CONSTRAINT ck_res_beneficiary_family CHECK (family_size IS NULL OR family_size >= 1),
    CONSTRAINT ck_res_beneficiary_income CHECK (monthly_income IS NULL OR monthly_income >= 0)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_res_beneficiaries_national_id' AND object_id = OBJECT_ID('dbo.beneficiaries'))
CREATE INDEX ix_res_beneficiaries_national_id ON dbo.beneficiaries(national_id);
GO

IF OBJECT_ID('dbo.applications', 'U') IS NULL
CREATE TABLE dbo.applications (
    source_application_id INT IDENTITY(1,1) PRIMARY KEY,
    application_code NVARCHAR(50) NOT NULL UNIQUE,
    source_beneficiary_id INT NOT NULL,
    source_branch_id INT NULL,
    support_type_name NVARCHAR(150) NOT NULL,
    requested_amount DECIMAL(18,2) NULL,
    application_status NVARCHAR(50) NOT NULL DEFAULT N'SUBMITTED',
    priority_level NVARCHAR(50) NOT NULL DEFAULT N'MEDIUM',
    submitted_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    reviewed_at DATETIME2(0) NULL,
    staff_notes NVARCHAR(1000) NULL,
    updated_at DATETIME2(0) NULL,
    CONSTRAINT fk_res_app_beneficiary FOREIGN KEY (source_beneficiary_id) REFERENCES dbo.beneficiaries(source_beneficiary_id),
    CONSTRAINT fk_res_app_branch FOREIGN KEY (source_branch_id) REFERENCES dbo.branches(source_branch_id)
);
GO

IF OBJECT_ID('dbo.cases', 'U') IS NULL
CREATE TABLE dbo.cases (
    source_case_id INT IDENTITY(1,1) PRIMARY KEY,
    case_code NVARCHAR(50) NOT NULL UNIQUE,
    source_application_id INT NULL,
    source_beneficiary_id INT NOT NULL,
    source_branch_id INT NULL,
    case_title NVARCHAR(200) NOT NULL,
    support_type_name NVARCHAR(150) NOT NULL,
    case_status NVARCHAR(50) NOT NULL DEFAULT N'OPEN',
    target_amount DECIMAL(18,2) NULL,
    collected_amount DECIMAL(18,2) NOT NULL DEFAULT 0,
    opened_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    closed_at DATETIME2(0) NULL,
    updated_at DATETIME2(0) NULL,
    CONSTRAINT fk_res_case_application FOREIGN KEY (source_application_id) REFERENCES dbo.applications(source_application_id),
    CONSTRAINT fk_res_case_beneficiary FOREIGN KEY (source_beneficiary_id) REFERENCES dbo.beneficiaries(source_beneficiary_id),
    CONSTRAINT fk_res_case_branch FOREIGN KEY (source_branch_id) REFERENCES dbo.branches(source_branch_id)
);
GO

IF OBJECT_ID('dbo.donors', 'U') IS NULL
CREATE TABLE dbo.donors (
    source_donor_id INT IDENTITY(1,1) PRIMARY KEY,
    donor_code NVARCHAR(50) NOT NULL UNIQUE,
    donor_name NVARCHAR(200) NOT NULL,
    phone NVARCHAR(30) NULL,
    email NVARCHAR(150) NULL,
    donor_category NVARCHAR(100) NULL,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at DATETIME2(0) NULL
);
GO

IF OBJECT_ID('dbo.donations', 'U') IS NULL
CREATE TABLE dbo.donations (
    source_donation_id INT IDENTITY(1,1) PRIMARY KEY,
    donation_code NVARCHAR(50) NOT NULL UNIQUE,
    source_donor_id INT NULL,
    source_case_id INT NULL,
    source_branch_id INT NULL,
    amount DECIMAL(18,2) NOT NULL,
    payment_method_name NVARCHAR(100) NULL,
    donation_status NVARCHAR(50) NOT NULL DEFAULT N'COMPLETED',
    donated_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    notes NVARCHAR(500) NULL,
    updated_at DATETIME2(0) NULL,
    CONSTRAINT fk_res_donation_donor FOREIGN KEY (source_donor_id) REFERENCES dbo.donors(source_donor_id),
    CONSTRAINT fk_res_donation_case FOREIGN KEY (source_case_id) REFERENCES dbo.cases(source_case_id),
    CONSTRAINT fk_res_donation_branch FOREIGN KEY (source_branch_id) REFERENCES dbo.branches(source_branch_id),
    CONSTRAINT ck_res_donation_amount CHECK (amount > 0)
);
GO

IF OBJECT_ID('dbo.inventory_items', 'U') IS NULL
CREATE TABLE dbo.inventory_items (
    source_item_id INT IDENTITY(1,1) PRIMARY KEY,
    item_code NVARCHAR(50) NOT NULL UNIQUE,
    item_name NVARCHAR(150) NOT NULL,
    item_category NVARCHAR(100) NULL,
    unit NVARCHAR(50) NOT NULL,
    default_unit_cost DECIMAL(18,2) NOT NULL DEFAULT 0,
    is_active BIT NOT NULL DEFAULT 1,
    updated_at DATETIME2(0) NULL
);
GO

IF OBJECT_ID('dbo.inventory_transactions', 'U') IS NULL
CREATE TABLE dbo.inventory_transactions (
    source_inventory_transaction_id INT IDENTITY(1,1) PRIMARY KEY,
    transaction_code NVARCHAR(50) NOT NULL UNIQUE,
    source_branch_id INT NULL,
    source_item_id INT NOT NULL,
    source_case_id INT NULL,
    transaction_type NVARCHAR(20) NOT NULL,
    quantity DECIMAL(18,2) NOT NULL,
    unit_cost DECIMAL(18,2) NOT NULL DEFAULT 0,
    transaction_date DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    notes NVARCHAR(500) NULL,
    updated_at DATETIME2(0) NULL,
    CONSTRAINT fk_res_inv_branch FOREIGN KEY (source_branch_id) REFERENCES dbo.branches(source_branch_id),
    CONSTRAINT fk_res_inv_item FOREIGN KEY (source_item_id) REFERENCES dbo.inventory_items(source_item_id),
    CONSTRAINT fk_res_inv_case FOREIGN KEY (source_case_id) REFERENCES dbo.cases(source_case_id),
    CONSTRAINT ck_res_inv_qty CHECK (quantity > 0),
    CONSTRAINT ck_res_inv_unit_cost CHECK (unit_cost >= 0)
);
GO

IF OBJECT_ID('dbo.beneficiary_documents', 'U') IS NULL
CREATE TABLE dbo.beneficiary_documents (
    source_document_id INT IDENTITY(1,1) PRIMARY KEY,
    source_beneficiary_id INT NOT NULL,
    source_application_id INT NULL,
    document_type_name NVARCHAR(150) NOT NULL,
    file_name NVARCHAR(255) NOT NULL,
    object_store_key NVARCHAR(500) NULL,
    file_url NVARCHAR(1000) NULL,
    verification_status NVARCHAR(50) NOT NULL DEFAULT N'PENDING',
    uploaded_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at DATETIME2(0) NULL,
    CONSTRAINT fk_res_doc_beneficiary FOREIGN KEY (source_beneficiary_id) REFERENCES dbo.beneficiaries(source_beneficiary_id),
    CONSTRAINT fk_res_doc_application FOREIGN KEY (source_application_id) REFERENCES dbo.applications(source_application_id)
);
GO

IF OBJECT_ID('dbo.source_event_outbox', 'U') IS NULL
CREATE TABLE dbo.source_event_outbox (
    source_event_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    event_uuid UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() UNIQUE,
    event_type NVARCHAR(100) NOT NULL,
    entity_name NVARCHAR(100) NOT NULL,
    entity_id NVARCHAR(100) NOT NULL,
    payload_json NVARCHAR(MAX) NULL,
    event_status NVARCHAR(50) NOT NULL DEFAULT N'PENDING',
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    published_at DATETIME2(0) NULL
);
GO

/* ========================= HAYA KARIMA ========================= */
USE charity_haya_karima_operational;
GO

IF OBJECT_ID('dbo.source_system_settings', 'U') IS NULL
CREATE TABLE dbo.source_system_settings (
    setting_key NVARCHAR(100) NOT NULL PRIMARY KEY,
    setting_value NVARCHAR(300) NOT NULL
);
GO

MERGE dbo.source_system_settings AS t
USING (VALUES
    (N'SOURCE_ORGANIZATION_CODE', N'HAYA_KARIMA'),
    (N'SOURCE_ORGANIZATION_NAME', N'Haya Karima System')
) AS s(setting_key, setting_value)
ON t.setting_key = s.setting_key
WHEN MATCHED THEN UPDATE SET setting_value = s.setting_value
WHEN NOT MATCHED THEN INSERT (setting_key, setting_value) VALUES (s.setting_key, s.setting_value);
GO

IF OBJECT_ID('dbo.branches', 'U') IS NULL
CREATE TABLE dbo.branches (
    source_branch_id INT IDENTITY(1,1) PRIMARY KEY,
    branch_code NVARCHAR(50) NOT NULL UNIQUE,
    branch_name NVARCHAR(200) NOT NULL,
    governorate_name NVARCHAR(100) NOT NULL,
    city_name NVARCHAR(100) NOT NULL,
    address NVARCHAR(300) NULL,
    phone NVARCHAR(30) NULL,
    is_active BIT NOT NULL DEFAULT 1,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at DATETIME2(0) NULL
);
GO

IF OBJECT_ID('dbo.staff_users', 'U') IS NULL
CREATE TABLE dbo.staff_users (
    source_user_id INT IDENTITY(1,1) PRIMARY KEY,
    user_code NVARCHAR(50) NOT NULL UNIQUE,
    source_branch_id INT NULL,
    full_name NVARCHAR(200) NOT NULL,
    email NVARCHAR(150) NULL,
    phone NVARCHAR(30) NULL,
    role_code NVARCHAR(50) NOT NULL DEFAULT N'CHARITY_STAFF',
    is_active BIT NOT NULL DEFAULT 1,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at DATETIME2(0) NULL,
    CONSTRAINT fk_haya_staff_branch FOREIGN KEY (source_branch_id) REFERENCES dbo.branches(source_branch_id)
);
GO

IF OBJECT_ID('dbo.beneficiaries', 'U') IS NULL
CREATE TABLE dbo.beneficiaries (
    source_beneficiary_id INT IDENTITY(1,1) PRIMARY KEY,
    national_id NVARCHAR(30) NOT NULL,
    full_name NVARCHAR(200) NOT NULL,
    gender NVARCHAR(20) NULL,
    birth_date DATE NULL,
    phone NVARCHAR(30) NULL,
    email NVARCHAR(150) NULL,
    governorate_name NVARCHAR(100) NOT NULL,
    city_name NVARCHAR(100) NOT NULL,
    address NVARCHAR(300) NULL,
    family_size INT NULL,
    monthly_income DECIMAL(18,2) NULL,
    employment_status NVARCHAR(100) NULL,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at DATETIME2(0) NULL,
    CONSTRAINT ck_haya_beneficiary_family CHECK (family_size IS NULL OR family_size >= 1),
    CONSTRAINT ck_haya_beneficiary_income CHECK (monthly_income IS NULL OR monthly_income >= 0)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_haya_beneficiaries_national_id' AND object_id = OBJECT_ID('dbo.beneficiaries'))
CREATE INDEX ix_haya_beneficiaries_national_id ON dbo.beneficiaries(national_id);
GO

IF OBJECT_ID('dbo.applications', 'U') IS NULL
CREATE TABLE dbo.applications (
    source_application_id INT IDENTITY(1,1) PRIMARY KEY,
    application_code NVARCHAR(50) NOT NULL UNIQUE,
    source_beneficiary_id INT NOT NULL,
    source_branch_id INT NULL,
    support_type_name NVARCHAR(150) NOT NULL,
    requested_amount DECIMAL(18,2) NULL,
    application_status NVARCHAR(50) NOT NULL DEFAULT N'SUBMITTED',
    priority_level NVARCHAR(50) NOT NULL DEFAULT N'MEDIUM',
    submitted_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    reviewed_at DATETIME2(0) NULL,
    staff_notes NVARCHAR(1000) NULL,
    updated_at DATETIME2(0) NULL,
    CONSTRAINT fk_haya_app_beneficiary FOREIGN KEY (source_beneficiary_id) REFERENCES dbo.beneficiaries(source_beneficiary_id),
    CONSTRAINT fk_haya_app_branch FOREIGN KEY (source_branch_id) REFERENCES dbo.branches(source_branch_id)
);
GO

IF OBJECT_ID('dbo.cases', 'U') IS NULL
CREATE TABLE dbo.cases (
    source_case_id INT IDENTITY(1,1) PRIMARY KEY,
    case_code NVARCHAR(50) NOT NULL UNIQUE,
    source_application_id INT NULL,
    source_beneficiary_id INT NOT NULL,
    source_branch_id INT NULL,
    case_title NVARCHAR(200) NOT NULL,
    support_type_name NVARCHAR(150) NOT NULL,
    case_status NVARCHAR(50) NOT NULL DEFAULT N'OPEN',
    target_amount DECIMAL(18,2) NULL,
    collected_amount DECIMAL(18,2) NOT NULL DEFAULT 0,
    opened_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    closed_at DATETIME2(0) NULL,
    updated_at DATETIME2(0) NULL,
    CONSTRAINT fk_haya_case_application FOREIGN KEY (source_application_id) REFERENCES dbo.applications(source_application_id),
    CONSTRAINT fk_haya_case_beneficiary FOREIGN KEY (source_beneficiary_id) REFERENCES dbo.beneficiaries(source_beneficiary_id),
    CONSTRAINT fk_haya_case_branch FOREIGN KEY (source_branch_id) REFERENCES dbo.branches(source_branch_id)
);
GO

IF OBJECT_ID('dbo.donors', 'U') IS NULL
CREATE TABLE dbo.donors (
    source_donor_id INT IDENTITY(1,1) PRIMARY KEY,
    donor_code NVARCHAR(50) NOT NULL UNIQUE,
    donor_name NVARCHAR(200) NOT NULL,
    phone NVARCHAR(30) NULL,
    email NVARCHAR(150) NULL,
    donor_category NVARCHAR(100) NULL,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at DATETIME2(0) NULL
);
GO

IF OBJECT_ID('dbo.donations', 'U') IS NULL
CREATE TABLE dbo.donations (
    source_donation_id INT IDENTITY(1,1) PRIMARY KEY,
    donation_code NVARCHAR(50) NOT NULL UNIQUE,
    source_donor_id INT NULL,
    source_case_id INT NULL,
    source_branch_id INT NULL,
    amount DECIMAL(18,2) NOT NULL,
    payment_method_name NVARCHAR(100) NULL,
    donation_status NVARCHAR(50) NOT NULL DEFAULT N'COMPLETED',
    donated_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    notes NVARCHAR(500) NULL,
    updated_at DATETIME2(0) NULL,
    CONSTRAINT fk_haya_donation_donor FOREIGN KEY (source_donor_id) REFERENCES dbo.donors(source_donor_id),
    CONSTRAINT fk_haya_donation_case FOREIGN KEY (source_case_id) REFERENCES dbo.cases(source_case_id),
    CONSTRAINT fk_haya_donation_branch FOREIGN KEY (source_branch_id) REFERENCES dbo.branches(source_branch_id),
    CONSTRAINT ck_haya_donation_amount CHECK (amount > 0)
);
GO

IF OBJECT_ID('dbo.inventory_items', 'U') IS NULL
CREATE TABLE dbo.inventory_items (
    source_item_id INT IDENTITY(1,1) PRIMARY KEY,
    item_code NVARCHAR(50) NOT NULL UNIQUE,
    item_name NVARCHAR(150) NOT NULL,
    item_category NVARCHAR(100) NULL,
    unit NVARCHAR(50) NOT NULL,
    default_unit_cost DECIMAL(18,2) NOT NULL DEFAULT 0,
    is_active BIT NOT NULL DEFAULT 1,
    updated_at DATETIME2(0) NULL
);
GO

IF OBJECT_ID('dbo.inventory_transactions', 'U') IS NULL
CREATE TABLE dbo.inventory_transactions (
    source_inventory_transaction_id INT IDENTITY(1,1) PRIMARY KEY,
    transaction_code NVARCHAR(50) NOT NULL UNIQUE,
    source_branch_id INT NULL,
    source_item_id INT NOT NULL,
    source_case_id INT NULL,
    transaction_type NVARCHAR(20) NOT NULL,
    quantity DECIMAL(18,2) NOT NULL,
    unit_cost DECIMAL(18,2) NOT NULL DEFAULT 0,
    transaction_date DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    notes NVARCHAR(500) NULL,
    updated_at DATETIME2(0) NULL,
    CONSTRAINT fk_haya_inv_branch FOREIGN KEY (source_branch_id) REFERENCES dbo.branches(source_branch_id),
    CONSTRAINT fk_haya_inv_item FOREIGN KEY (source_item_id) REFERENCES dbo.inventory_items(source_item_id),
    CONSTRAINT fk_haya_inv_case FOREIGN KEY (source_case_id) REFERENCES dbo.cases(source_case_id),
    CONSTRAINT ck_haya_inv_qty CHECK (quantity > 0),
    CONSTRAINT ck_haya_inv_unit_cost CHECK (unit_cost >= 0)
);
GO

IF OBJECT_ID('dbo.beneficiary_documents', 'U') IS NULL
CREATE TABLE dbo.beneficiary_documents (
    source_document_id INT IDENTITY(1,1) PRIMARY KEY,
    source_beneficiary_id INT NOT NULL,
    source_application_id INT NULL,
    document_type_name NVARCHAR(150) NOT NULL,
    file_name NVARCHAR(255) NOT NULL,
    object_store_key NVARCHAR(500) NULL,
    file_url NVARCHAR(1000) NULL,
    verification_status NVARCHAR(50) NOT NULL DEFAULT N'PENDING',
    uploaded_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at DATETIME2(0) NULL,
    CONSTRAINT fk_haya_doc_beneficiary FOREIGN KEY (source_beneficiary_id) REFERENCES dbo.beneficiaries(source_beneficiary_id),
    CONSTRAINT fk_haya_doc_application FOREIGN KEY (source_application_id) REFERENCES dbo.applications(source_application_id)
);
GO

IF OBJECT_ID('dbo.source_event_outbox', 'U') IS NULL
CREATE TABLE dbo.source_event_outbox (
    source_event_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    event_uuid UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() UNIQUE,
    event_type NVARCHAR(100) NOT NULL,
    entity_name NVARCHAR(100) NOT NULL,
    entity_id NVARCHAR(100) NOT NULL,
    payload_json NVARCHAR(MAX) NULL,
    event_status NVARCHAR(50) NOT NULL DEFAULT N'PENDING',
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    published_at DATETIME2(0) NULL
);
GO

/* ========================= VERIFY ========================= */
SELECT DB_NAME() AS current_database;
GO


/* =============================== END INCLUDED FILE ============================== */


/* ==============================================================================
   START INCLUDED FILE: 06_seed_three_operational_dbs_sample.sql
   ============================================================================== */

/*
================================================================================
Unified Charity Platform - Sample Source Data for 3 Operational DBs
================================================================================
Purpose:
    Create small overlapping sample data so you can demonstrate Beneficiary 360,
    cross-organization matching, duplicated aid detection, and CDC events.
================================================================================
*/

/* ========================= FOOD BANK ========================= */
USE charity_food_bank_operational;
GO

IF NOT EXISTS (SELECT 1 FROM dbo.branches WHERE branch_code = N'FB-CAIRO-01')
INSERT INTO dbo.branches(branch_code, branch_name, governorate_name, city_name, address, phone)
VALUES (N'FB-CAIRO-01', N'Food Bank Cairo Branch', N'Cairo', N'Nasr City', N'Cairo - Nasr City', N'0220000001');
GO

IF NOT EXISTS (SELECT 1 FROM dbo.inventory_items WHERE item_code = N'FOOD_BOX')
INSERT INTO dbo.inventory_items(item_code, item_name, item_category, unit, default_unit_cost)
VALUES (N'FOOD_BOX', N'Food Box', N'Food', N'Box', 250.00);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.beneficiaries WHERE national_id = N'29901011234567')
INSERT INTO dbo.beneficiaries(national_id, full_name, gender, phone, governorate_name, city_name, address, family_size, monthly_income, employment_status)
VALUES (N'29901011234567', N'Ahmed Mohamed Ali', N'MALE', N'01012345678', N'Cairo', N'Nasr City', N'Street 1', 5, 1800, N'Unemployed');
GO

IF NOT EXISTS (SELECT 1 FROM dbo.applications WHERE application_code = N'FB-APP-0001')
INSERT INTO dbo.applications(application_code, source_beneficiary_id, source_branch_id, support_type_name, requested_amount, application_status, priority_level, staff_notes)
SELECT N'FB-APP-0001', b.source_beneficiary_id, br.source_branch_id, N'Food Support', 1500, N'APPROVED', N'HIGH', N'Food aid requested'
FROM dbo.beneficiaries b CROSS JOIN dbo.branches br
WHERE b.national_id = N'29901011234567' AND br.branch_code = N'FB-CAIRO-01';
GO

IF NOT EXISTS (SELECT 1 FROM dbo.cases WHERE case_code = N'FB-CASE-0001')
INSERT INTO dbo.cases(case_code, source_application_id, source_beneficiary_id, source_branch_id, case_title, support_type_name, case_status, target_amount, collected_amount)
SELECT N'FB-CASE-0001', a.source_application_id, b.source_beneficiary_id, br.source_branch_id, N'Food support case for Ahmed', N'Food Support', N'OPEN', 1500, 500
FROM dbo.applications a
JOIN dbo.beneficiaries b ON a.source_beneficiary_id = b.source_beneficiary_id
JOIN dbo.branches br ON a.source_branch_id = br.source_branch_id
WHERE a.application_code = N'FB-APP-0001';
GO

IF NOT EXISTS (SELECT 1 FROM dbo.donors WHERE donor_code = N'FB-DONOR-0001')
INSERT INTO dbo.donors(donor_code, donor_name, phone, donor_category)
VALUES (N'FB-DONOR-0001', N'Good Donor Food Bank', N'01011110001', N'Individual');
GO

IF NOT EXISTS (SELECT 1 FROM dbo.donations WHERE donation_code = N'FB-DON-0001')
INSERT INTO dbo.donations(donation_code, source_donor_id, source_case_id, source_branch_id, amount, payment_method_name)
SELECT N'FB-DON-0001', d.source_donor_id, c.source_case_id, c.source_branch_id, 500, N'Wallet'
FROM dbo.donors d CROSS JOIN dbo.cases c
WHERE d.donor_code = N'FB-DONOR-0001' AND c.case_code = N'FB-CASE-0001';
GO

/* ========================= RESALA ========================= */
USE charity_resala_operational;
GO

IF NOT EXISTS (SELECT 1 FROM dbo.branches WHERE branch_code = N'RS-GIZA-01')
INSERT INTO dbo.branches(branch_code, branch_name, governorate_name, city_name, address, phone)
VALUES (N'RS-GIZA-01', N'Resala Giza Branch', N'Giza', N'Dokki', N'Giza - Dokki', N'0230000001');
GO

IF NOT EXISTS (SELECT 1 FROM dbo.inventory_items WHERE item_code = N'RAMADAN_BOX')
INSERT INTO dbo.inventory_items(item_code, item_name, item_category, unit, default_unit_cost)
VALUES (N'RAMADAN_BOX', N'Ramadan Box', N'Food', N'Box', 300.00);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.beneficiaries WHERE national_id = N'29901011234567')
INSERT INTO dbo.beneficiaries(national_id, full_name, gender, phone, governorate_name, city_name, address, family_size, monthly_income, employment_status)
VALUES (N'29901011234567', N'Ahmed Mohamed Ali', N'MALE', N'01012345678', N'Giza', N'Dokki', N'Street 2', 5, 1800, N'Unemployed');
GO

IF NOT EXISTS (SELECT 1 FROM dbo.applications WHERE application_code = N'RS-APP-0001')
INSERT INTO dbo.applications(application_code, source_beneficiary_id, source_branch_id, support_type_name, requested_amount, application_status, priority_level, staff_notes)
SELECT N'RS-APP-0001', b.source_beneficiary_id, br.source_branch_id, N'Food Support', 1200, N'UNDER_REVIEW', N'HIGH', N'Possible repeated support'
FROM dbo.beneficiaries b CROSS JOIN dbo.branches br
WHERE b.national_id = N'29901011234567' AND br.branch_code = N'RS-GIZA-01';
GO

IF NOT EXISTS (SELECT 1 FROM dbo.cases WHERE case_code = N'RS-CASE-0001')
INSERT INTO dbo.cases(case_code, source_application_id, source_beneficiary_id, source_branch_id, case_title, support_type_name, case_status, target_amount, collected_amount)
SELECT N'RS-CASE-0001', a.source_application_id, b.source_beneficiary_id, br.source_branch_id, N'Food support review for Ahmed', N'Food Support', N'OPEN', 1200, 0
FROM dbo.applications a
JOIN dbo.beneficiaries b ON a.source_beneficiary_id = b.source_beneficiary_id
JOIN dbo.branches br ON a.source_branch_id = br.source_branch_id
WHERE a.application_code = N'RS-APP-0001';
GO

/* ========================= HAYA KARIMA ========================= */
USE charity_haya_karima_operational;
GO

IF NOT EXISTS (SELECT 1 FROM dbo.branches WHERE branch_code = N'HK-ASWAN-01')
INSERT INTO dbo.branches(branch_code, branch_name, governorate_name, city_name, address, phone)
VALUES (N'HK-ASWAN-01', N'Haya Karima Aswan Branch', N'Aswan', N'Aswan', N'Aswan Center', N'0970000001');
GO

IF NOT EXISTS (SELECT 1 FROM dbo.inventory_items WHERE item_code = N'SCHOOL_BAG')
INSERT INTO dbo.inventory_items(item_code, item_name, item_category, unit, default_unit_cost)
VALUES (N'SCHOOL_BAG', N'School Bag', N'Education', N'Piece', 200.00);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.beneficiaries WHERE national_id = N'29205051234567')
INSERT INTO dbo.beneficiaries(national_id, full_name, gender, phone, governorate_name, city_name, address, family_size, monthly_income, employment_status)
VALUES (N'29205051234567', N'Fatma Elsayed Abdullah', N'FEMALE', N'01055555555', N'Aswan', N'Aswan', N'Street 9', 7, 900, N'Unemployed');
GO

IF NOT EXISTS (SELECT 1 FROM dbo.applications WHERE application_code = N'HK-APP-0001')
INSERT INTO dbo.applications(application_code, source_beneficiary_id, source_branch_id, support_type_name, requested_amount, application_status, priority_level, staff_notes)
SELECT N'HK-APP-0001', b.source_beneficiary_id, br.source_branch_id, N'Education Support', 2200, N'APPROVED', N'MEDIUM', N'School expenses support'
FROM dbo.beneficiaries b CROSS JOIN dbo.branches br
WHERE b.national_id = N'29205051234567' AND br.branch_code = N'HK-ASWAN-01';
GO

PRINT N'Sample source data inserted in 3 operational DBs.';
GO


/* =============================== END INCLUDED FILE ============================== */


/* ==============================================================================
   START INCLUDED FILE: 03_add_platform_integration_tables.sql
   ============================================================================== */

/*
================================================================================
Unified Charity Platform - Add Integration Tables to Platform DB
================================================================================
Run this AFTER your existing 00_ALL_IN_ONE_unified_charity_platform_clean.sql.
It adds the missing professional integration layer that connects Kafka/CDC events
into the existing platform database without breaking your current backend tables.
================================================================================
*/

USE unified_charity_platform_clean;
GO

/* 1) Source systems registry: maps each source DB to the platform organization. */
IF OBJECT_ID('dbo.source_systems', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.source_systems (
        source_system_id INT IDENTITY(1,1) PRIMARY KEY,
        source_system_code NVARCHAR(50) NOT NULL UNIQUE,
        source_system_name NVARCHAR(200) NOT NULL,
        source_database_name NVARCHAR(200) NOT NULL,
        kafka_topic_prefix NVARCHAR(200) NULL,
        organization_id INT NULL,
        ingestion_mode NVARCHAR(50) NOT NULL DEFAULT N'CDC', -- CDC / BATCH / API
        is_active BIT NOT NULL DEFAULT 1,
        created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        updated_at DATETIME2(0) NULL,
        CONSTRAINT fk_source_systems_organization
            FOREIGN KEY (organization_id) REFERENCES dbo.organizations(organization_id)
    );
END;
GO

MERGE dbo.source_systems AS t
USING (
    SELECT N'FOOD_BANK' AS source_system_code, N'Food Bank Operational DB' AS source_system_name,
           N'charity_food_bank_operational' AS source_database_name, N'sqlserver.food_bank' AS kafka_topic_prefix,
           (SELECT organization_id FROM dbo.organizations WHERE organization_code IN (N'FOOD_BANK', N'FOODBANK')) AS organization_id
    UNION ALL
    SELECT N'RESALA', N'Resala Operational DB', N'charity_resala_operational', N'sqlserver.resala',
           (SELECT organization_id FROM dbo.organizations WHERE organization_code = N'RESALA')
    UNION ALL
    SELECT N'HAYA_KARIMA', N'Haya Karima Operational DB', N'charity_haya_karima_operational', N'sqlserver.haya_karima',
           (SELECT organization_id FROM dbo.organizations WHERE organization_code IN (N'HAYA_KARIMA', N'HAYAKARIMA'))
) AS s
ON t.source_system_code = s.source_system_code
WHEN MATCHED THEN UPDATE SET
    source_system_name = s.source_system_name,
    source_database_name = s.source_database_name,
    kafka_topic_prefix = s.kafka_topic_prefix,
    organization_id = COALESCE(s.organization_id, t.organization_id),
    updated_at = SYSUTCDATETIME()
WHEN NOT MATCHED THEN INSERT (
    source_system_code, source_system_name, source_database_name, kafka_topic_prefix, organization_id
) VALUES (
    s.source_system_code, s.source_system_name, s.source_database_name, s.kafka_topic_prefix, s.organization_id
);
GO

/* 2) Inbound event staging: CDC/Kafka consumer writes here before applying business logic. */
IF OBJECT_ID('dbo.inbound_event_staging', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.inbound_event_staging (
        inbound_event_id BIGINT IDENTITY(1,1) PRIMARY KEY,
        event_uuid UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
        source_system_id INT NOT NULL,
        event_type NVARCHAR(100) NOT NULL,
        source_table NVARCHAR(150) NOT NULL,
        source_primary_key NVARCHAR(150) NOT NULL,
        operation NVARCHAR(20) NOT NULL, -- c/u/d/r or INSERT/UPDATE/DELETE/READ
        kafka_topic NVARCHAR(300) NULL,
        kafka_partition INT NULL,
        kafka_offset BIGINT NULL,
        payload_json NVARCHAR(MAX) NOT NULL,
        schema_version NVARCHAR(50) NULL,
        process_status NVARCHAR(50) NOT NULL DEFAULT N'RECEIVED', -- RECEIVED / VALIDATED / APPLIED / FAILED / DLQ
        retry_count INT NOT NULL DEFAULT 0,
        processing_error NVARCHAR(MAX) NULL,
        received_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        processed_at DATETIME2(0) NULL,
        CONSTRAINT fk_inbound_events_source_system
            FOREIGN KEY (source_system_id) REFERENCES dbo.source_systems(source_system_id),
        CONSTRAINT ck_inbound_event_status CHECK (process_status IN (N'RECEIVED', N'VALIDATED', N'APPLIED', N'FAILED', N'DLQ'))
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_inbound_event_status' AND object_id = OBJECT_ID('dbo.inbound_event_staging'))
CREATE INDEX ix_inbound_event_status ON dbo.inbound_event_staging(process_status, received_at);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_inbound_event_source_offset' AND object_id = OBJECT_ID('dbo.inbound_event_staging'))
CREATE UNIQUE INDEX ix_inbound_event_source_offset
ON dbo.inbound_event_staging(kafka_topic, kafka_partition, kafka_offset)
WHERE kafka_topic IS NOT NULL AND kafka_partition IS NOT NULL AND kafka_offset IS NOT NULL;
GO

/* 3) Mapping table: source primary keys to platform entity ids. */
IF OBJECT_ID('dbo.source_to_platform_entity_map', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.source_to_platform_entity_map (
        entity_map_id BIGINT IDENTITY(1,1) PRIMARY KEY,
        source_system_id INT NOT NULL,
        source_entity_name NVARCHAR(100) NOT NULL,
        source_entity_id NVARCHAR(150) NOT NULL,
        platform_entity_name NVARCHAR(100) NOT NULL,
        platform_entity_id NVARCHAR(150) NOT NULL,
        confidence_score DECIMAL(5,2) NULL,
        mapping_status NVARCHAR(50) NOT NULL DEFAULT N'ACTIVE',
        mapped_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        updated_at DATETIME2(0) NULL,
        CONSTRAINT fk_entity_map_source_system
            FOREIGN KEY (source_system_id) REFERENCES dbo.source_systems(source_system_id),
        CONSTRAINT uq_source_entity_map UNIQUE (source_system_id, source_entity_name, source_entity_id, platform_entity_name)
    );
END;
GO

/* 4) Dead Letter Queue table for events that cannot be processed. */
IF OBJECT_ID('dbo.dead_letter_events', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.dead_letter_events (
        dead_letter_event_id BIGINT IDENTITY(1,1) PRIMARY KEY,
        inbound_event_id BIGINT NULL,
        source_system_id INT NULL,
        event_type NVARCHAR(100) NULL,
        source_table NVARCHAR(150) NULL,
        source_primary_key NVARCHAR(150) NULL,
        payload_json NVARCHAR(MAX) NULL,
        error_category NVARCHAR(100) NOT NULL,
        error_message NVARCHAR(MAX) NOT NULL,
        is_reprocessed BIT NOT NULL DEFAULT 0,
        reprocessed_at DATETIME2(0) NULL,
        created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT fk_dlq_inbound_event FOREIGN KEY (inbound_event_id) REFERENCES dbo.inbound_event_staging(inbound_event_id),
        CONSTRAINT fk_dlq_source_system FOREIGN KEY (source_system_id) REFERENCES dbo.source_systems(source_system_id)
    );
END;
GO

/* 5) Data lineage for traceability from source -> bronze/silver/gold -> DWH. */
IF OBJECT_ID('dbo.data_lineage_events', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.data_lineage_events (
        lineage_event_id BIGINT IDENTITY(1,1) PRIMARY KEY,
        source_system_id INT NULL,
        source_layer NVARCHAR(50) NOT NULL, -- SOURCE / BRONZE / SILVER / GOLD / DWH / PLATFORM
        source_object NVARCHAR(300) NOT NULL,
        target_layer NVARCHAR(50) NOT NULL,
        target_object NVARCHAR(300) NOT NULL,
        record_count BIGINT NULL,
        status NVARCHAR(50) NOT NULL DEFAULT N'SUCCESS',
        started_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        finished_at DATETIME2(0) NULL,
        notes NVARCHAR(MAX) NULL,
        CONSTRAINT fk_lineage_source_system FOREIGN KEY (source_system_id) REFERENCES dbo.source_systems(source_system_id)
    );
END;
GO

/* 6) Optional data quality rules table if your current script does not already create one. */
IF OBJECT_ID('dbo.data_quality_rules', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.data_quality_rules (
        data_quality_rule_id INT IDENTITY(1,1) PRIMARY KEY,
        rule_code NVARCHAR(100) NOT NULL UNIQUE,
        rule_name NVARCHAR(200) NOT NULL,
        target_layer NVARCHAR(50) NOT NULL,
        target_object NVARCHAR(300) NOT NULL,
        severity NVARCHAR(20) NOT NULL DEFAULT N'MEDIUM',
        rule_description NVARCHAR(1000) NULL,
        is_active BIT NOT NULL DEFAULT 1,
        created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
    );
END;
GO

MERGE dbo.data_quality_rules AS t
USING (VALUES
    (N'NATIONAL_ID_REQUIRED', N'National ID is required', N'SILVER', N'beneficiaries', N'HIGH', N'national_id must not be null or empty.'),
    (N'NATIONAL_ID_LENGTH', N'National ID length check', N'SILVER', N'beneficiaries', N'HIGH', N'national_id should contain 14 digits in the Egyptian context.'),
    (N'AMOUNT_POSITIVE', N'Positive financial amount', N'SILVER', N'donations', N'HIGH', N'Donation amount and requested amount must be greater than zero.'),
    (N'ORG_MAPPING_EXISTS', N'Organization mapping exists', N'SILVER', N'all_entities', N'CRITICAL', N'Every standardized record must map to a platform organization_id.'),
    (N'DUPLICATE_EVENT_ID', N'Duplicate Kafka event detection', N'BRONZE', N'kafka_events', N'MEDIUM', N'Kafka topic, partition and offset must not be processed twice.')
) AS s(rule_code, rule_name, target_layer, target_object, severity, rule_description)
ON t.rule_code = s.rule_code
WHEN MATCHED THEN UPDATE SET
    rule_name = s.rule_name,
    target_layer = s.target_layer,
    target_object = s.target_object,
    severity = s.severity,
    rule_description = s.rule_description,
    is_active = 1
WHEN NOT MATCHED THEN INSERT (rule_code, rule_name, target_layer, target_object, severity, rule_description)
VALUES (s.rule_code, s.rule_name, s.target_layer, s.target_object, s.severity, s.rule_description);
GO

/* 7) Useful integration status view. */
CREATE OR ALTER VIEW dbo.v_integration_pipeline_status AS
SELECT
    ss.source_system_code,
    ss.source_system_name,
    ies.process_status,
    COUNT_BIG(*) AS events_count,
    MIN(ies.received_at) AS first_received_at,
    MAX(ies.received_at) AS last_received_at,
    MAX(ies.processed_at) AS last_processed_at
FROM dbo.source_systems ss
LEFT JOIN dbo.inbound_event_staging ies
    ON ss.source_system_id = ies.source_system_id
GROUP BY ss.source_system_code, ss.source_system_name, ies.process_status;
GO

PRINT N'Platform integration tables are ready.';
GO


/* =============================== END INCLUDED FILE ============================== */


/* ==============================================================================
   START INCLUDED FILE: 04_create_dwh_star_schema.sql
   ============================================================================== */

/*
================================================================================
Unified Charity Platform - Data Warehouse Star Schema
================================================================================
Purpose:
    The DWH is the official analytical layer used by Power BI.
    It receives curated Gold data from HDFS / Spark jobs.

Design:
    - SCD Type 2 dimensions where useful.
    - Append-only fact tables.
    - Surrogate keys for Power BI-friendly star schema.
================================================================================
*/

USE charity_dwh;
GO

/* ========================= ETL AUDIT ========================= */
IF OBJECT_ID('dbo.etl_load_runs', 'U') IS NULL
CREATE TABLE dbo.etl_load_runs (
    etl_load_run_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    pipeline_name NVARCHAR(200) NOT NULL,
    source_layer NVARCHAR(50) NOT NULL,
    target_table NVARCHAR(200) NOT NULL,
    load_status NVARCHAR(50) NOT NULL DEFAULT N'RUNNING',
    records_inserted BIGINT NULL,
    records_updated BIGINT NULL,
    records_rejected BIGINT NULL,
    started_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    finished_at DATETIME2(0) NULL,
    error_message NVARCHAR(MAX) NULL
);
GO

/* ========================= DIMENSIONS ========================= */
IF OBJECT_ID('dbo.dim_time', 'U') IS NULL
CREATE TABLE dbo.dim_time (
    time_key INT NOT NULL PRIMARY KEY, -- YYYYMMDD
    full_date DATE NOT NULL UNIQUE,
    day_number INT NOT NULL,
    month_number INT NOT NULL,
    month_name_en NVARCHAR(20) NOT NULL,
    quarter_number INT NOT NULL,
    year_number INT NOT NULL,
    week_number INT NOT NULL,
    is_weekend BIT NOT NULL DEFAULT 0
);
GO

IF OBJECT_ID('dbo.dim_governorate', 'U') IS NULL
CREATE TABLE dbo.dim_governorate (
    governorate_key INT IDENTITY(1,1) PRIMARY KEY,
    governorate_id INT NULL,
    governorate_code NVARCHAR(50) NULL,
    governorate_name_ar NVARCHAR(100) NOT NULL,
    governorate_name_en NVARCHAR(100) NULL,
    is_current BIT NOT NULL DEFAULT 1,
    valid_from DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    valid_to DATETIME2(0) NULL
);
GO

IF OBJECT_ID('dbo.dim_organization', 'U') IS NULL
CREATE TABLE dbo.dim_organization (
    organization_key INT IDENTITY(1,1) PRIMARY KEY,
    organization_id INT NULL,
    organization_code NVARCHAR(50) NOT NULL,
    organization_name_ar NVARCHAR(200) NOT NULL,
    organization_name_en NVARCHAR(200) NULL,
    phone NVARCHAR(30) NULL,
    email NVARCHAR(150) NULL,
    is_active BIT NOT NULL DEFAULT 1,
    is_current BIT NOT NULL DEFAULT 1,
    valid_from DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    valid_to DATETIME2(0) NULL
);
GO

IF OBJECT_ID('dbo.dim_branch', 'U') IS NULL
CREATE TABLE dbo.dim_branch (
    branch_key INT IDENTITY(1,1) PRIMARY KEY,
    branch_id INT NULL,
    branch_code NVARCHAR(50) NOT NULL,
    organization_key INT NULL,
    governorate_key INT NULL,
    branch_name_ar NVARCHAR(200) NOT NULL,
    branch_name_en NVARCHAR(200) NULL,
    city_name_ar NVARCHAR(100) NULL,
    city_name_en NVARCHAR(100) NULL,
    is_active BIT NOT NULL DEFAULT 1,
    is_current BIT NOT NULL DEFAULT 1,
    valid_from DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    valid_to DATETIME2(0) NULL,
    CONSTRAINT fk_dim_branch_organization FOREIGN KEY (organization_key) REFERENCES dbo.dim_organization(organization_key),
    CONSTRAINT fk_dim_branch_governorate FOREIGN KEY (governorate_key) REFERENCES dbo.dim_governorate(governorate_key)
);
GO

IF OBJECT_ID('dbo.dim_beneficiary', 'U') IS NULL
CREATE TABLE dbo.dim_beneficiary (
    beneficiary_key BIGINT IDENTITY(1,1) PRIMARY KEY,
    beneficiary_id INT NULL,
    beneficiary_code NVARCHAR(50) NULL,
    national_id_hash NVARCHAR(128) NULL,
    full_name_masked NVARCHAR(200) NULL,
    gender NVARCHAR(20) NULL,
    birth_year INT NULL,
    age_group NVARCHAR(50) NULL,
    governorate_key INT NULL,
    family_size INT NULL,
    income_band NVARCHAR(50) NULL,
    employment_status NVARCHAR(100) NULL,
    is_active BIT NOT NULL DEFAULT 1,
    is_current BIT NOT NULL DEFAULT 1,
    valid_from DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    valid_to DATETIME2(0) NULL,
    CONSTRAINT fk_dim_beneficiary_governorate FOREIGN KEY (governorate_key) REFERENCES dbo.dim_governorate(governorate_key)
);
GO

IF OBJECT_ID('dbo.dim_support_type', 'U') IS NULL
CREATE TABLE dbo.dim_support_type (
    support_type_key INT IDENTITY(1,1) PRIMARY KEY,
    support_type_id INT NULL,
    support_code NVARCHAR(50) NULL,
    support_name_ar NVARCHAR(150) NOT NULL,
    support_name_en NVARCHAR(150) NULL,
    is_cash_support BIT NOT NULL DEFAULT 0,
    is_inventory_support BIT NOT NULL DEFAULT 0,
    is_current BIT NOT NULL DEFAULT 1,
    valid_from DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    valid_to DATETIME2(0) NULL
);
GO

IF OBJECT_ID('dbo.dim_donor', 'U') IS NULL
CREATE TABLE dbo.dim_donor (
    donor_key BIGINT IDENTITY(1,1) PRIMARY KEY,
    donor_id INT NULL,
    donor_code NVARCHAR(50) NULL,
    donor_name_masked NVARCHAR(200) NULL,
    donor_category NVARCHAR(100) NULL,
    is_current BIT NOT NULL DEFAULT 1,
    valid_from DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    valid_to DATETIME2(0) NULL
);
GO

IF OBJECT_ID('dbo.dim_item', 'U') IS NULL
CREATE TABLE dbo.dim_item (
    item_key INT IDENTITY(1,1) PRIMARY KEY,
    item_id INT NULL,
    item_code NVARCHAR(50) NULL,
    item_name_ar NVARCHAR(150) NOT NULL,
    item_name_en NVARCHAR(150) NULL,
    item_category NVARCHAR(100) NULL,
    unit NVARCHAR(50) NULL,
    is_current BIT NOT NULL DEFAULT 1,
    valid_from DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    valid_to DATETIME2(0) NULL
);
GO

IF OBJECT_ID('dbo.dim_payment_method', 'U') IS NULL
CREATE TABLE dbo.dim_payment_method (
    payment_method_key INT IDENTITY(1,1) PRIMARY KEY,
    payment_method_id INT NULL,
    payment_method_code NVARCHAR(50) NULL,
    method_name_ar NVARCHAR(100) NOT NULL,
    method_name_en NVARCHAR(100) NULL,
    is_current BIT NOT NULL DEFAULT 1,
    valid_from DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    valid_to DATETIME2(0) NULL
);
GO

/* ========================= FACTS ========================= */
IF OBJECT_ID('dbo.fact_applications', 'U') IS NULL
CREATE TABLE dbo.fact_applications (
    application_fact_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    application_id INT NOT NULL,
    application_code NVARCHAR(50) NOT NULL,
    submitted_time_key INT NOT NULL,
    organization_key INT NOT NULL,
    branch_key INT NULL,
    beneficiary_key BIGINT NOT NULL,
    support_type_key INT NOT NULL,
    requested_amount DECIMAL(18,2) NULL,
    application_status NVARCHAR(50) NOT NULL,
    priority_level NVARCHAR(50) NULL,
    days_to_review INT NULL,
    is_approved BIT NULL,
    is_rejected BIT NULL,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT fk_fact_app_time FOREIGN KEY (submitted_time_key) REFERENCES dbo.dim_time(time_key),
    CONSTRAINT fk_fact_app_org FOREIGN KEY (organization_key) REFERENCES dbo.dim_organization(organization_key),
    CONSTRAINT fk_fact_app_branch FOREIGN KEY (branch_key) REFERENCES dbo.dim_branch(branch_key),
    CONSTRAINT fk_fact_app_beneficiary FOREIGN KEY (beneficiary_key) REFERENCES dbo.dim_beneficiary(beneficiary_key),
    CONSTRAINT fk_fact_app_support FOREIGN KEY (support_type_key) REFERENCES dbo.dim_support_type(support_type_key)
);
GO

IF OBJECT_ID('dbo.fact_cases', 'U') IS NULL
CREATE TABLE dbo.fact_cases (
    case_fact_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    case_id INT NOT NULL,
    case_code NVARCHAR(50) NOT NULL,
    opened_time_key INT NOT NULL,
    closed_time_key INT NULL,
    organization_key INT NOT NULL,
    branch_key INT NULL,
    beneficiary_key BIGINT NOT NULL,
    support_type_key INT NOT NULL,
    target_amount DECIMAL(18,2) NULL,
    collected_amount DECIMAL(18,2) NULL,
    remaining_amount DECIMAL(18,2) NULL,
    case_status NVARCHAR(50) NOT NULL,
    days_open INT NULL,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT fk_fact_case_open_time FOREIGN KEY (opened_time_key) REFERENCES dbo.dim_time(time_key),
    CONSTRAINT fk_fact_case_close_time FOREIGN KEY (closed_time_key) REFERENCES dbo.dim_time(time_key),
    CONSTRAINT fk_fact_case_org FOREIGN KEY (organization_key) REFERENCES dbo.dim_organization(organization_key),
    CONSTRAINT fk_fact_case_branch FOREIGN KEY (branch_key) REFERENCES dbo.dim_branch(branch_key),
    CONSTRAINT fk_fact_case_beneficiary FOREIGN KEY (beneficiary_key) REFERENCES dbo.dim_beneficiary(beneficiary_key),
    CONSTRAINT fk_fact_case_support FOREIGN KEY (support_type_key) REFERENCES dbo.dim_support_type(support_type_key)
);
GO

IF OBJECT_ID('dbo.fact_donations', 'U') IS NULL
CREATE TABLE dbo.fact_donations (
    donation_fact_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    donation_id INT NOT NULL,
    donation_code NVARCHAR(50) NOT NULL,
    donation_time_key INT NOT NULL,
    organization_key INT NULL,
    branch_key INT NULL,
    donor_key BIGINT NULL,
    payment_method_key INT NULL,
    case_id INT NULL,
    amount DECIMAL(18,2) NOT NULL,
    donation_status NVARCHAR(50) NULL,
    donation_target_type NVARCHAR(50) NULL,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT fk_fact_donation_time FOREIGN KEY (donation_time_key) REFERENCES dbo.dim_time(time_key),
    CONSTRAINT fk_fact_donation_org FOREIGN KEY (organization_key) REFERENCES dbo.dim_organization(organization_key),
    CONSTRAINT fk_fact_donation_branch FOREIGN KEY (branch_key) REFERENCES dbo.dim_branch(branch_key),
    CONSTRAINT fk_fact_donation_donor FOREIGN KEY (donor_key) REFERENCES dbo.dim_donor(donor_key),
    CONSTRAINT fk_fact_donation_payment FOREIGN KEY (payment_method_key) REFERENCES dbo.dim_payment_method(payment_method_key)
);
GO

IF OBJECT_ID('dbo.fact_inventory_transactions', 'U') IS NULL
CREATE TABLE dbo.fact_inventory_transactions (
    inventory_fact_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    transaction_id INT NOT NULL,
    transaction_code NVARCHAR(50) NOT NULL,
    transaction_time_key INT NOT NULL,
    organization_key INT NOT NULL,
    branch_key INT NULL,
    item_key INT NOT NULL,
    case_id INT NULL,
    application_id INT NULL,
    transaction_type NVARCHAR(20) NOT NULL,
    quantity DECIMAL(18,2) NOT NULL,
    unit_cost DECIMAL(18,2) NOT NULL,
    total_cost DECIMAL(18,2) NOT NULL,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT fk_fact_inv_time FOREIGN KEY (transaction_time_key) REFERENCES dbo.dim_time(time_key),
    CONSTRAINT fk_fact_inv_org FOREIGN KEY (organization_key) REFERENCES dbo.dim_organization(organization_key),
    CONSTRAINT fk_fact_inv_branch FOREIGN KEY (branch_key) REFERENCES dbo.dim_branch(branch_key),
    CONSTRAINT fk_fact_inv_item FOREIGN KEY (item_key) REFERENCES dbo.dim_item(item_key)
);
GO

IF OBJECT_ID('dbo.fact_fraud_alerts', 'U') IS NULL
CREATE TABLE dbo.fact_fraud_alerts (
    fraud_alert_fact_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    fraud_alert_id BIGINT NOT NULL,
    alert_code NVARCHAR(50) NOT NULL,
    created_time_key INT NOT NULL,
    organization_key INT NULL,
    beneficiary_key BIGINT NULL,
    alert_type NVARCHAR(100) NOT NULL,
    severity NVARCHAR(20) NOT NULL,
    risk_score DECIMAL(5,2) NOT NULL,
    alert_status NVARCHAR(50) NOT NULL,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT fk_fact_fraud_time FOREIGN KEY (created_time_key) REFERENCES dbo.dim_time(time_key),
    CONSTRAINT fk_fact_fraud_org FOREIGN KEY (organization_key) REFERENCES dbo.dim_organization(organization_key),
    CONSTRAINT fk_fact_fraud_beneficiary FOREIGN KEY (beneficiary_key) REFERENCES dbo.dim_beneficiary(beneficiary_key)
);
GO

IF OBJECT_ID('dbo.fact_data_quality_issues', 'U') IS NULL
CREATE TABLE dbo.fact_data_quality_issues (
    data_quality_fact_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    issue_id BIGINT NULL,
    detected_time_key INT NOT NULL,
    source_system_code NVARCHAR(50) NULL,
    data_layer NVARCHAR(50) NOT NULL,
    entity_name NVARCHAR(100) NOT NULL,
    rule_code NVARCHAR(100) NOT NULL,
    severity NVARCHAR(20) NOT NULL,
    issue_status NVARCHAR(50) NOT NULL,
    records_affected BIGINT NOT NULL DEFAULT 1,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT fk_fact_dq_time FOREIGN KEY (detected_time_key) REFERENCES dbo.dim_time(time_key)
);
GO

/* ========================= INDEXES ========================= */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_fact_app_org_time' AND object_id = OBJECT_ID('dbo.fact_applications'))
CREATE INDEX ix_fact_app_org_time ON dbo.fact_applications(organization_key, submitted_time_key);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_fact_case_org_time' AND object_id = OBJECT_ID('dbo.fact_cases'))
CREATE INDEX ix_fact_case_org_time ON dbo.fact_cases(organization_key, opened_time_key);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_fact_donation_time' AND object_id = OBJECT_ID('dbo.fact_donations'))
CREATE INDEX ix_fact_donation_time ON dbo.fact_donations(donation_time_key, organization_key);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_fact_inventory_time' AND object_id = OBJECT_ID('dbo.fact_inventory_transactions'))
CREATE INDEX ix_fact_inventory_time ON dbo.fact_inventory_transactions(transaction_time_key, organization_key);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_fact_fraud_time' AND object_id = OBJECT_ID('dbo.fact_fraud_alerts'))
CREATE INDEX ix_fact_fraud_time ON dbo.fact_fraud_alerts(created_time_key, organization_key, severity);
GO

/* ========================= POWER BI VIEWS ========================= */
CREATE OR ALTER VIEW dbo.v_powerbi_government_overview AS
SELECT
    o.organization_code,
    o.organization_name_en,
    t.year_number,
    t.month_number,
    COUNT(DISTINCT a.application_id) AS total_applications,
    SUM(CASE WHEN a.is_approved = 1 THEN 1 ELSE 0 END) AS approved_applications,
    SUM(CASE WHEN a.is_rejected = 1 THEN 1 ELSE 0 END) AS rejected_applications,
    SUM(COALESCE(a.requested_amount, 0)) AS total_requested_amount
FROM dbo.fact_applications a
JOIN dbo.dim_organization o ON a.organization_key = o.organization_key
JOIN dbo.dim_time t ON a.submitted_time_key = t.time_key
GROUP BY o.organization_code, o.organization_name_en, t.year_number, t.month_number;
GO

CREATE OR ALTER VIEW dbo.v_powerbi_donations_overview AS
SELECT
    o.organization_code,
    o.organization_name_en,
    t.year_number,
    t.month_number,
    COUNT_BIG(*) AS donations_count,
    SUM(d.amount) AS total_donation_amount,
    AVG(d.amount) AS average_donation_amount
FROM dbo.fact_donations d
LEFT JOIN dbo.dim_organization o ON d.organization_key = o.organization_key
JOIN dbo.dim_time t ON d.donation_time_key = t.time_key
GROUP BY o.organization_code, o.organization_name_en, t.year_number, t.month_number;
GO

PRINT N'DWH star schema is ready.';
GO


/* =============================== END INCLUDED FILE ============================== */


/* ==============================================================================
   START INCLUDED FILE: 05_create_role_based_views.sql
   ============================================================================== */

/*
================================================================================
Unified Charity Platform - Role-Based Views for API and Dashboards
================================================================================
Purpose:
    Government dashboard = global.
    Charity dashboard = filtered by organization_id.
    Beneficiary 360 = cross-organization summary but hides sensitive internal data.
================================================================================
*/

USE unified_charity_platform_clean;
GO

/* Charity dashboard view: API must add WHERE organization_id = current_user.organization_id */
CREATE OR ALTER VIEW dbo.v_charity_dashboard_organization_scoped AS
SELECT
    o.organization_id,
    o.organization_code,
    o.organization_name_en,
    COUNT(DISTINCT a.application_id) AS total_applications,
    SUM(CASE WHEN a.application_status IN (N'APPROVED', N'ACCEPTED') THEN 1 ELSE 0 END) AS approved_applications,
    SUM(CASE WHEN a.application_status IN (N'REJECTED') THEN 1 ELSE 0 END) AS rejected_applications,
    COUNT(DISTINCT c.case_id) AS total_cases,
    SUM(CASE WHEN c.case_status IN (N'OPEN', N'ACTIVE') THEN 1 ELSE 0 END) AS open_cases,
    COUNT(DISTINCT d.donation_id) AS total_donations_count,
    SUM(COALESCE(d.amount, 0)) AS total_donations_amount,
    COUNT(DISTINCT it.transaction_id) AS inventory_transactions_count,
    COUNT(DISTINCT fa.fraud_alert_id) AS fraud_alerts_count
FROM dbo.organizations o
LEFT JOIN dbo.beneficiary_applications a ON o.organization_id = a.organization_id
LEFT JOIN dbo.charity_cases c ON o.organization_id = c.organization_id
LEFT JOIN dbo.donations d ON o.organization_id = d.organization_id
LEFT JOIN dbo.inventory_transactions it ON o.organization_id = it.organization_id
LEFT JOIN dbo.fraud_alerts fa ON o.organization_id = fa.organization_id
GROUP BY o.organization_id, o.organization_code, o.organization_name_en;
GO

/* Government dashboard view: no organization filter. */
CREATE OR ALTER VIEW dbo.v_government_dashboard_global AS
SELECT
    COUNT(DISTINCT o.organization_id) AS organizations_count,
    COUNT(DISTINCT b.beneficiary_id) AS beneficiaries_count,
    COUNT(DISTINCT a.application_id) AS applications_count,
    COUNT(DISTINCT c.case_id) AS cases_count,
    COUNT(DISTINCT d.donation_id) AS donations_count,
    SUM(COALESCE(d.amount, 0)) AS donations_amount,
    COUNT(DISTINCT fa.fraud_alert_id) AS fraud_alerts_count,
    COUNT(DISTINCT dc.duplicate_candidate_id) AS duplicate_candidates_count
FROM dbo.organizations o
LEFT JOIN dbo.beneficiary_profiles b ON 1 = 1
LEFT JOIN dbo.beneficiary_applications a ON a.organization_id = o.organization_id
LEFT JOIN dbo.charity_cases c ON c.organization_id = o.organization_id
LEFT JOIN dbo.donations d ON d.organization_id = o.organization_id
LEFT JOIN dbo.fraud_alerts fa ON fa.organization_id = o.organization_id
LEFT JOIN dbo.duplicate_candidates dc ON dc.organization_id = o.organization_id;
GO

/* Safe Beneficiary 360 summary: shows support history/risk without private documents/internal reviewer notes. */
CREATE OR ALTER VIEW dbo.v_beneficiary_360_safe AS
SELECT
    b.beneficiary_id,
    b.beneficiary_code,
    b.national_id,
    b.full_name,
    b.phone,
    g.governorate_name_en,
    c.city_name_en,
    COUNT(DISTINCT bor.organization_id) AS registered_organizations_count,
    COUNT(DISTINCT a.application_id) AS total_applications,
    COUNT(DISTINCT cc.case_id) AS total_cases,
    SUM(COALESCE(d.amount, 0)) AS total_direct_or_case_donations,
    COUNT(DISTINCT it.transaction_id) AS inventory_support_transactions,
    MAX(CASE WHEN fa.alert_status = N'OPEN' THEN 1 ELSE 0 END) AS has_open_fraud_alert,
    MAX(COALESCE(fa.risk_score, 0)) AS max_risk_score,
    MAX(a.submitted_at) AS last_application_at
FROM dbo.beneficiary_profiles b
LEFT JOIN dbo.governorates g ON b.governorate_id = g.governorate_id
LEFT JOIN dbo.cities c ON b.city_id = c.city_id
LEFT JOIN dbo.beneficiary_org_registrations bor ON b.beneficiary_id = bor.beneficiary_id
LEFT JOIN dbo.beneficiary_applications a ON b.beneficiary_id = a.beneficiary_id
LEFT JOIN dbo.charity_cases cc ON b.beneficiary_id = cc.beneficiary_id
LEFT JOIN dbo.donations d ON cc.case_id = d.case_id
LEFT JOIN dbo.inventory_transactions it ON cc.case_id = it.case_id
LEFT JOIN dbo.fraud_alerts fa ON b.beneficiary_id = fa.beneficiary_id
GROUP BY
    b.beneficiary_id, b.beneficiary_code, b.national_id, b.full_name, b.phone,
    g.governorate_name_en, c.city_name_en;
GO

/* Cross organization beneficiary summary for duplicate/support overlap detection. */
CREATE OR ALTER VIEW dbo.v_cross_organization_support_overlap AS
SELECT
    b.beneficiary_id,
    b.national_id,
    b.full_name,
    COUNT(DISTINCT a.organization_id) AS organizations_with_applications,
    COUNT(DISTINCT a.support_type_id) AS support_types_requested,
    COUNT(DISTINCT a.application_id) AS applications_count,
    MIN(a.submitted_at) AS first_application_at,
    MAX(a.submitted_at) AS last_application_at
FROM dbo.beneficiary_profiles b
JOIN dbo.beneficiary_applications a ON b.beneficiary_id = a.beneficiary_id
GROUP BY b.beneficiary_id, b.national_id, b.full_name
HAVING COUNT(DISTINCT a.organization_id) > 1;
GO

PRINT N'Role-based API/dashboard views are ready.';
GO


/* =============================== END INCLUDED FILE ============================== */


/* ==============================================================================
   START INCLUDED FILE: 07_dwh_load_templates.sql
   ============================================================================== */

/*
================================================================================
Unified Charity Platform - DWH Load Templates
================================================================================
These are templates. In the final pipeline, Spark reads HDFS Gold and writes into
these DWH tables. You can also export Gold as CSV/Parquet and load it here.
================================================================================
*/

USE charity_dwh;
GO

/* Template 1: fill dim_time for 2026. Extend dates when needed. */
DECLARE @start_date DATE = '2026-01-01';
DECLARE @end_date DATE = '2026-12-31';

;WITH d AS (
    SELECT @start_date AS full_date
    UNION ALL
    SELECT DATEADD(DAY, 1, full_date)
    FROM d
    WHERE full_date < @end_date
)
INSERT INTO dbo.dim_time (
    time_key, full_date, day_number, month_number, month_name_en,
    quarter_number, year_number, week_number, is_weekend
)
SELECT
    CONVERT(INT, FORMAT(full_date, 'yyyyMMdd')) AS time_key,
    full_date,
    DAY(full_date),
    MONTH(full_date),
    DATENAME(MONTH, full_date),
    DATEPART(QUARTER, full_date),
    YEAR(full_date),
    DATEPART(WEEK, full_date),
    CASE WHEN DATENAME(WEEKDAY, full_date) IN ('Friday', 'Saturday') THEN 1 ELSE 0 END
FROM d
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.dim_time t WHERE t.full_date = d.full_date
)
OPTION (MAXRECURSION 400);
GO

/* Template 2: create staging tables that Spark/CSV loaders can write into. */
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'stg')
BEGIN
    EXEC('CREATE SCHEMA stg');
END;
GO

IF OBJECT_ID('stg.gold_dim_organization', 'U') IS NULL
CREATE TABLE stg.gold_dim_organization (
    organization_id INT NULL,
    organization_code NVARCHAR(50) NOT NULL,
    organization_name_ar NVARCHAR(200) NOT NULL,
    organization_name_en NVARCHAR(200) NULL,
    phone NVARCHAR(30) NULL,
    email NVARCHAR(150) NULL,
    is_active BIT NOT NULL
);
GO

IF OBJECT_ID('stg.gold_fact_applications', 'U') IS NULL
CREATE TABLE stg.gold_fact_applications (
    application_id INT NOT NULL,
    application_code NVARCHAR(50) NOT NULL,
    submitted_date DATE NOT NULL,
    organization_code NVARCHAR(50) NOT NULL,
    branch_code NVARCHAR(50) NULL,
    beneficiary_id INT NOT NULL,
    support_code NVARCHAR(50) NOT NULL,
    requested_amount DECIMAL(18,2) NULL,
    application_status NVARCHAR(50) NOT NULL,
    priority_level NVARCHAR(50) NULL,
    days_to_review INT NULL,
    is_approved BIT NULL,
    is_rejected BIT NULL
);
GO

PRINT N'DWH load templates are ready. Spark can load HDFS Gold into stg tables, then merge into dims/facts.';
GO


/* =============================== END INCLUDED FILE ============================== */

USE master;
GO
SELECT name AS database_name FROM sys.databases WHERE name IN (N'charity_food_bank_operational', N'charity_resala_operational', N'charity_haya_karima_operational', N'unified_charity_platform_clean', N'charity_dwh') ORDER BY name;
GO
PRINT 'MASTER FULL SETUP FINISHED SUCCESSFULLY.';
GO
