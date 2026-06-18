# Phase 3 â€” Complete Arabic Platform Integration

This phase finishes the operational platform before starting the Data Engineering part.

## What is included

### Frontend
- Arabic RTL interface.
- Beneficiary portal:
  - Dashboard.
  - Submit application.
  - Upload documents to MinIO.
  - Track application status from SQL Server.
  - View monthly eligibility/support profile.
- Donor portal:
  - View public donor-safe cases.
  - Add cases to favorites.
  - Donate to eligible cases.
  - View donation history.
  - Fully funded/not eligible cases disable donation.
- Charity admin portal:
  - Organization-scoped dashboard.
  - Review applications.
  - Approve/reject/under review.
  - Create cases from applications.
  - Manage cases and publish them to donors.
  - Fraud alerts.
  - Beneficiary 360.
  - Support profiles.
  - Manual support disbursement.
- Government admin portal:
  - Global dashboard.
  - All organizations.
  - Global support profiles.
  - Fraud overview.
  - DWH / Power BI overview.
  - Data Engineering pipeline page.

### Backend
- New Phase 3 API router: `backend/app/routers/phase3_complete.py`
- API prefix: `/api/phase3`
- Keeps the Phase 2 and original APIs for compatibility.
- Backend validates key business rules before insert/update.

### Database
- SQL Server operational database: `unified_charity_platform_clean`
- Three source operational databases:
  - `charity_food_bank_operational`
  - `charity_resala_operational`
  - `charity_haya_karima_operational`
- DWH database: `charity_dwh`
- Corrected views:
  - `dbo.v_public_donor_cases`
  - `dbo.v_beneficiary_support_profiles`
- Stored procedures:
  - `dbo.sp_phase3_recalculate_priority`
  - `dbo.sp_phase3_record_eligibility`
  - `dbo.sp_phase3_close_case_if_funded`

### DWH / Power BI
- Star schema is available in `charity_dwh`.
- Power BI-ready views:
  - `charity_dwh.dbo.v_powerbi_government_overview`
  - `charity_dwh.dbo.v_powerbi_donations_overview`

## Recommended run order

### 1. Start infrastructure

```powershell
cd unified_charity_platform_mvp\infra
docker compose -f .\docker-compose.presentation.yml up -d
```

### 2. Run SQL setup in SSMS

Open SSMS and connect to:

```text
Server: localhost,1433
User: sa
Password: ChangeMe_StrongPassword_2026!
Trust server certificate: ON
```

Run this file on `master`:

```text
database_setup\00_PHASE_3_FULL_DATABASE_SETUP_RUN_ON_MASTER.sql
```

If you already ran Phase 2 v3 successfully, you may run only:

```text
backend\sql\20_PHASE_3_COMPLETE_INTEGRATION.sql
```

Then run the final health check:

```text
backend\sql\21_PHASE_3_COMPLETE_HEALTHCHECK.sql
```

Expected result: important checks should be `PASS`. Row counts may vary depending on your data.

### 3. Backend

```powershell
cd unified_charity_platform_mvp\backend
copy .env.example .env
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Backend docs:

```text
http://localhost:8000/docs
```

### 4. Frontend

```powershell
cd unified_charity_platform_mvp\frontend
npm install
npm run dev
```

Frontend:

```text
http://localhost:5173
```

## Demo login accounts

Password for all demo accounts:

```text
123456
```

Accounts:

```text
gov@test.com            Government Admin
food.admin@test.com     Food Bank Admin
resala.admin@test.com   Resala Admin
haya.admin@test.com     Haya Karima Admin
ahmed@test.com          Beneficiary
donor@test.com          Donor
```

## Important presentation notes

- Charity admin is organization-scoped.
- Government admin sees all organizations.
- Donor only sees public donor-safe data.
- Donor cannot see national ID, private documents, fraud notes, or reviewer names.
- Fully funded cases are disabled for donation and show â€œØºÙŠØ± Ù…Ø³ØªØ­Ù‚ Ù‡Ø°Ø§ Ø§Ù„Ø´Ù‡Ø±â€.
- Support profiles show whether the beneficiary received support this month.
- Priority scoring is calculated from family size, children count, income, medical/disability flags, rent burden, emergency level, previous support, and fraud risk.
- DWH is separate from the operational DB and is used for Power BI.

## After this phase

Start the Data Engineering part:

```text
3 charity operational DBs
â†’ CDC / Debezium
â†’ Kafka + Schema Registry
â†’ Spark Structured Streaming
â†’ HDFS Bronze / Silver / Gold
â†’ Airflow + Data Quality
â†’ DWH
â†’ Power BI
```

