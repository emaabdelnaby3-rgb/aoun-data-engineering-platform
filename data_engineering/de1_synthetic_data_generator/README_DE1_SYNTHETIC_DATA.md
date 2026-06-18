# DE-1 â€” Synthetic Charity Data Generator

This phase creates realistic synthetic source data because we do not have the real operational databases of Food Bank, Resala, and Haya Karima.

The generator produces data as if it came from three independent charity operational systems:

- `charity_food_bank_operational`
- `charity_resala_operational`
- `charity_haya_karima_operational`

It generates:

- beneficiaries
- applications
- cases
- donors
- donations
- inventory items
- inventory transactions
- beneficiary document metadata
- source event outbox rows
- dirty rows for data quality testing
- duplicate national IDs across organizations for fraud / Beneficiary 360 testing

## 1. Open the project folder

```powershell
cd C:\Users\Admin\Downloads\unified_charity_platform_final_before_data_engineering_v3\unified_charity_platform_mvp\data_engineering\de1_synthetic_data_generator
```

If you copy this folder into another version of the project, use that project path instead.

## 2. Generate the data

Small demo dataset:

```powershell
python generate_synthetic_data.py --beneficiaries-per-org 500 --months 12 --output-dir output
```

Larger presentation dataset:

```powershell
python generate_synthetic_data.py --beneficiaries-per-org 3000 --months 18 --output-dir output
```

The output will contain:

```text
output/01_load_synthetic_source_data.sql
output/generation_summary.json
output/csv/charity_food_bank_operational/*.csv
output/csv/charity_resala_operational/*.csv
output/csv/charity_haya_karima_operational/*.csv
```

## 3. Load the generated data into SQL Server

Open SSMS and connect to:

```text
Server: localhost,1433
Login: sa
Password: ChangeMe_StrongPassword_2026!
Trust Server Certificate: ON
```

Open and run this generated file on `master`:

```text
output/01_load_synthetic_source_data.sql
```

## 4. Verify the load

Run:

```text
sql/01_verify_source_data.sql
```

Expected result:

- Row counts for all 3 operational source databases.
- `PASS` or at least non-empty row counts.
- Duplicate national IDs across organizations should appear. These are intentional for fraud and Beneficiary 360 scenarios.

## 5. What comes next

After this phase, the three charity operational databases contain enough realistic historical source data.

Next phase:

```text
DE-2: Enable SQL Server CDC
DE-3/DE-4: Kafka + Zookeeper + Debezium
```

Then new inserts/updates in these source DBs will be captured as CDC events and streamed to Kafka.

