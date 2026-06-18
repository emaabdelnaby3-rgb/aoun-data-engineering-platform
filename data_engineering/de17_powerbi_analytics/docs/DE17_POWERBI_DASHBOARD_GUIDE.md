# DE-17 Power BI Dashboard Guide

Connection:
- Server: localhost,1433
- Database: charity_dwh
- Authentication: Database
- Username: sa
- Password: ChangeMe_StrongPassword_2026!
- Recommended mode: Import
- Schema to load: analytics

Recommended views:
- analytics.v_kpi_overview
- analytics.v_dim_organization
- analytics.v_dim_beneficiary
- analytics.v_dim_donor
- analytics.v_fact_applications
- analytics.v_fact_cases
- analytics.v_fact_donations
- analytics.v_fact_inventory_transactions
- analytics.v_donation_summary_by_organization
- analytics.v_application_summary_by_organization
- analytics.v_case_summary_by_organization
- analytics.v_inventory_summary_by_organization
- analytics.v_dashboard_manifest

Dashboard pages:

Page 1: Executive Overview
- Total beneficiaries
- Total donors
- Total applications
- Total cases
- Total donations
- Total donation amount
- Applications by organization
- Donations by organization
- Data Quality Pass Rate

Page 2: Beneficiary 360
- Beneficiaries by organization
- Beneficiary distribution
- Income and family size analysis if available

Page 3: Applications and Cases
- Applications count
- Cases count
- Average priority score
- Applications by organization
- Cases by organization

Page 4: Donations and Donors
- Total donors
- Donation count
- Donation amount
- Donations by organization

Page 5: Inventory Monitoring
- Inventory transactions
- Total inventory quantity
- Inventory by organization

Page 6: Data Engineering Health
Load these CSV files:
- data_engineering/de13_data_quality/results/de13_latest_results.csv
- data_engineering/de15_observability_monitoring/results/de15_observability_latest.csv
- data_engineering/de16_data_governance/catalog/ucp_data_catalog.csv
- data_engineering/de16_data_governance/classification/ucp_pii_classification.csv

Defense statement:
The Power BI dashboard consumes curated Gold and DWH analytics views from SQL Server. It visualizes charity performance, beneficiaries, applications, cases, donations, inventory, data quality, observability, and governance readiness. This completes the serving and analytics layer of the enterprise data engineering pipeline.

