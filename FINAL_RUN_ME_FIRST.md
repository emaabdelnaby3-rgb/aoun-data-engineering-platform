# Unified Charity Platform â€” Final Clean Package Before Data Engineering

This is the final working version before starting the Data Engineering phase.
It includes the Arabic frontend, FastAPI backend, SQL Server operational databases, DWH, MinIO upload, API integration, validation, and health checks.

## What this package includes

- Arabic RTL frontend
- FastAPI backend
- SQL Server operational platform database
- 3 independent charity source databases
- Data Warehouse star schema for Power BI
- MinIO object storage for document upload
- Beneficiary portal
- Donor portal
- Charity admin portal
- Government admin portal
- Beneficiary 360
- Fraud alerts
- Priority scoring
- Monthly support eligibility profiles
- Health check scripts
- Ready structure for the Data Engineering phase

## Databases created

The SQL setup creates these 5 databases:

1. `charity_food_bank_operational`
2. `charity_resala_operational`
3. `charity_haya_karima_operational`
4. `unified_charity_platform_clean`
5. `charity_dwh`

The backend uses:

```env
SQL_SERVER_DATABASE=unified_charity_platform_clean
SQL_SERVER_USER=charity_app_user
SQL_SERVER_PASSWORD=ChangeMe_StrongPassword_2026!
```

## Step 1 â€” Start infrastructure

From the project root:

```powershell
cd unified_charity_platform_mvp\infra
docker compose -f .\docker-compose.presentation.yml up -d
```

This starts:

- SQL Server on `localhost:1433`
- MinIO on `localhost:9000`
- MinIO console on `localhost:9001`

MinIO login:

```text
Username: ChangeMe_MinIO_2026!
Password: ChangeMe_MinIO_2026!123
```

## Step 2 â€” Run the full database setup

Open SSMS and connect to SQL Server.

Recommended if using the included Docker SQL Server:

```text
Server: localhost,1433
Authentication: SQL Server Authentication
Login: sa
Password: ChangeMe_StrongPassword_2026!
Trust Server Certificate: ON
```

Then open and run this file on `master`:

```text
database_setup\00_RUN_ME_FIRST_FULL_RESET_AND_SETUP.sql
```

This script resets and creates the whole demo database environment and creates the backend SQL login `charity_app_user`.

## Step 3 â€” Confirm database setup

Run this in SSMS:

```sql
SELECT name
FROM sys.databases
WHERE name IN (
    'charity_food_bank_operational',
    'charity_resala_operational',
    'charity_haya_karima_operational',
    'unified_charity_platform_clean',
    'charity_dwh'
);
```

You should see 5 databases.

Then run:

```sql
SELECT TOP 10 * FROM unified_charity_platform_clean.dbo.v_public_donor_cases;
SELECT TOP 10 * FROM unified_charity_platform_clean.dbo.v_beneficiary_support_profiles;
SELECT TOP 10 * FROM charity_dwh.dbo.v_powerbi_government_overview;
SELECT TOP 10 * FROM charity_dwh.dbo.v_powerbi_donations_overview;
```

They may return demo rows or empty analytical rows, but they should not throw errors.

## Step 4 â€” Run backend

From the project root:

```powershell
cd unified_charity_platform_mvp\backend
copy .env.example .env
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Backend docs:

```text
http://127.0.0.1:8000/docs
```

Health check:

```text
http://127.0.0.1:8000/api/phase3/health
```

Reference data:

```text
http://127.0.0.1:8000/api/phase3/reference-data
```

## Step 5 â€” Test backend SQL connection manually

From `backend`:

```powershell
python -c "from app.config import settings; print(settings.sql_server_host, settings.sql_server_port, settings.sql_server_database, settings.sql_server_trusted_connection, settings.sql_server_user); from app.database import get_connection; c=get_connection(); cur=c.cursor(); cur.execute('SELECT DB_NAME(), COUNT(*) FROM dbo.organizations'); print(cur.fetchone())"
```

Expected result:

```text
localhost 1433 unified_charity_platform_clean False charity_app_user
('unified_charity_platform_clean', 3)
```

## Step 6 â€” Run frontend

Open another terminal:

```powershell
cd unified_charity_platform_mvp\frontend
npm install
npm run dev
```

Open:

```text
http://localhost:5173
```

## Demo login accounts

All demo passwords are:

```text
123456
```

Accounts:

```text
gov@test.com              Government Admin
food.admin@test.com       Food Bank Admin
resala.admin@test.com     Resala Admin
haya.admin@test.com       Haya Karima Admin
ahmed@test.com            Beneficiary
donor@test.com            Donor
```

## Step 7 â€” Run complete API health check

Open:

```text
http://127.0.0.1:8000/api/phase3/healthcheck
```

Expected: all important objects should return `PASS`.

## What is ready for Data Engineering next

After this package works, start Data Engineering with:

```text
3 charity operational DBs
        â†“
CDC / Kafka / Batch ingestion
        â†“
HDFS Data Lake Bronze
        â†“
Spark cleaning to Silver
        â†“
Gold analytical datasets
        â†“
Load Gold to charity_dwh
        â†“
Power BI dashboards
```

Do not connect Power BI directly to `unified_charity_platform_clean` for final analytics. Use `charity_dwh`.

## Important notes

- `00_RUN_ME_FIRST_FULL_RESET_AND_SETUP.sql` resets the demo databases. Do not run it on production data.
- The backend should use `charity_app_user`, not Windows Authentication.
- The old database name `unified_charity_platform` should not be used. The correct database is `unified_charity_platform_clean`.
- If `reference-data` returns 400, check `.env` first.

