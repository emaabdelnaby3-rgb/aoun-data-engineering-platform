# Phase 2 — Arabic Platform Database + Backend Business Flow

This phase keeps the Arabic frontend from Phase 1, but adds real SQL Server tables, views, and FastAPI endpoints for the business workflow.

## What Phase 2 adds

- Beneficiary applications stored in SQL Server with business fields.
- Priority scoring stored in `case_priority_scores`.
- Monthly eligibility checks stored in `eligibility_checks`.
- Support received this month stored in `support_disbursements`.
- Donor favorites stored in `donor_favorites`.
- Admin review workflow stored in `admin_reviews` and `application_status_history`.
- Donor-safe public cases view: `v_public_donor_cases`.
- Charity/Government support profile view: `v_beneficiary_support_profiles`.
- FastAPI routes under `/api/phase2`.

## Run order

Open SQL Server Management Studio and run:

```sql
-- 1) Main clean database, only if not already installed
backend/sql/00_ALL_IN_ONE_unified_charity_platform_clean.sql

-- 2) Phase 2 migration
backend/sql/10_PHASE_2_BUSINESS_SCHEMA.sql
```

Then run the backend:

```bash
cd unified_charity_platform_mvp/backend
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Then run the frontend:

```bash
cd unified_charity_platform_mvp/frontend
npm install
npm run dev
```

Open:

```text
http://localhost:5174
```

Backend docs:

```text
http://localhost:8000/docs
```

## Important API routes

### Beneficiary

```text
POST /api/phase2/beneficiary/applications
GET  /api/phase2/beneficiary/{national_id}/applications
GET  /api/phase2/beneficiary/{national_id}/support-profile
```

### Charity Admin

```text
GET  /api/phase2/admin/dashboard?organization_id=1
GET  /api/phase2/admin/applications?organization_id=1
POST /api/phase2/admin/applications/{application_code}/review
GET  /api/phase2/support-profiles?organization_id=1
```

### Donor

```text
GET  /api/phase2/donor/cases?only_available=true
POST /api/phase2/donor/favorites
GET  /api/phase2/donor/favorites?donor_phone=01022222222
POST /api/phase2/donor/donations
```

### Government

```text
GET /api/phase2/government/dashboard
GET /api/phase2/support-profiles
```

## Example: submit beneficiary application

```json
{
  "national_id": "29801011234567",
  "full_name": "سارة أحمد",
  "phone": "01011111111",
  "governorate": "القاهرة",
  "city": "مدينة نصر",
  "address": "شارع النصر",
  "family_size": 6,
  "monthly_income": 1200,
  "support_type": "دعم شهري",
  "requested_amount": 3000,
  "organization_id": 1,
  "children_count": 4,
  "has_chronic_disease": true,
  "has_disability": false,
  "is_widow_or_single_mother": true,
  "rent_amount": 1800,
  "emergency_level": "MEDIUM",
  "public_case_description": "أسرة تحتاج دعم شهري للغذاء والإيجار"
}
```

The API will return:

```text
application_code
priority_score
priority_level
eligibility_status
```

## Example: admin approves and publishes a case

```json
{
  "decision": "APPROVED",
  "notes": "المستندات صحيحة والحالة مستحقة",
  "create_case": true,
  "required_amount": 3000,
  "case_title": "دعم شهري لأسرة محتاجة",
  "public_display_name": "أسرة محتاجة - القاهرة",
  "documents_verified": true,
  "is_monthly_case": true
}
```

Route:

```text
POST /api/phase2/admin/applications/APP-00001/review
```

## Example: donor donation

```json
{
  "case_code": "CASE-00001",
  "donor_name": "محمد علي",
  "donor_phone": "01022222222",
  "amount": 3000,
  "payment_method": "Cash"
}
```

When the collected amount reaches the required amount, Phase 2 automatically:

```text
1. closes the case
2. disables donation
3. creates support_disbursement for the beneficiary
4. changes monthly eligibility to غير مستحق هذا الشهر
```

## Business rules implemented

Priority score:

```text
family size >= 5: +5
more than 3 children: +5
income <= 1500: +8
income <= 800: +5
chronic disease: +10
disability: +10
widow / single mother: +8
rent >= 1500: +5
medium emergency: +7
high/critical emergency: +15
received support this month: -10
high/critical fraud alert: -30
```

Levels:

```text
0-20 Low
21-40 Medium
41-60 High
61+ Critical
```

## Safe visibility

Donor public view does not expose:

```text
national_id
private documents
internal admin notes
reviewer name
fraud investigation notes
```

Charity admin can scope support profiles by `organization_id`.
Government admin can omit `organization_id` to see all organizations.
