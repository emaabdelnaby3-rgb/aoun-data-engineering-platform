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
