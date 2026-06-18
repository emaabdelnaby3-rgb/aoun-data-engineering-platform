# Phase 2 v3 â€” Arabic Platform + MinIO Upload + Professional DB Setup

This package is presentation-ready for the charity platform business flow.

## What is included

- Arabic RTL frontend with simple UX.
- Real file upload page for beneficiaries.
- MinIO/S3 object storage integration.
- SQL Server metadata saving for uploaded documents.
- Backend validation for file type and size.
- Priority scoring, eligibility, support profiles, donor favorites, admin review flow.
- Professional database architecture setup:
  - `charity_food_bank_operational`
  - `charity_resala_operational`
  - `charity_haya_karima_operational`
  - `unified_charity_platform_clean`
  - `charity_dwh`

## 1) Start infrastructure

From the project root:

```powershell
cd infra
docker compose -f docker-compose.presentation.yml up -d
```

Services:

```text
SQL Server: localhost:1433
MinIO API: http://localhost:9000
MinIO Console: http://localhost:9001
MinIO user: ChangeMe_MinIO_2026!
MinIO password: ChangeMe_MinIO_2026!123
Bucket: charity-documents
```

## 2) Create the databases

Open SSMS and connect to SQL Server using:

```text
Server: localhost,1433
Login: sa
Password: ChangeMe_StrongPassword_2026!
Trust server certificate: enabled
```

Run this single master SQL file:

```text
database_setup/00_MASTER_FULL_SETUP_PRESENTATION.sql
```

This creates the 3 charity source databases, the unified platform operational database, and the DWH.

## 3) Configure backend

```powershell
cd backend
copy .env.example .env
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Check:

```text
http://localhost:8000/health
http://localhost:8000/api/documents/storage-health
http://localhost:8000/docs
```

## 4) Run frontend

Open a second terminal:

```powershell
cd frontend
npm install
npm run dev
```

Open:

```text
http://localhost:5173
```

## 5) Test upload file flow

Login as beneficiary:

```text
National ID: 29801011234567
Password: 123456
```

Go to:

```text
Ø±ÙØ¹ Ø§Ù„Ù…Ø³ØªÙ†Ø¯Ø§Øª
```

Choose:

```text
Ø§Ù„Ø·Ù„Ø¨ Ø§Ù„Ù…Ø±ØªØ¨Ø·
Ù†ÙˆØ¹ Ø§Ù„Ù…Ø³ØªÙ†Ø¯
file: PDF/JPG/PNG/DOCX
```

Click:

```text
Ø±ÙØ¹ Ø§Ù„Ù…Ø³ØªÙ†Ø¯ Ø¹Ù„Ù‰ MinIO
```

Expected result:

- The file is uploaded to MinIO bucket `charity-documents`.
- The document metadata is inserted into SQL Server table `beneficiary_documents`.
- An outbox event is inserted into `platform_event_outbox`.
- The file appears in the beneficiary document list.

## 6) Why this is professional

Operational layer:

```text
3 charity source databases -> CDC/Kafka ready
unified_charity_platform_clean -> frontend/backend operational serving DB
```

Storage layer:

```text
MinIO stores documents as object storage
SQL Server stores document metadata only
```

Analytics layer:

```text
charity_dwh -> star schema for Power BI
```

Security/business rule:

```text
Donors see public case data only.
Admins see their own organization.
Government sees all organizations.
Documents are not exposed to donors.
```

