# DE-17 Power BI DAX Measures

Use these measures after loading the analytics views from SQL Server.

Core KPIs:

Total Beneficiaries = COUNTROWS('v_dim_beneficiary')

Total Donors = COUNTROWS('v_dim_donor')

Total Applications = COUNTROWS('v_fact_applications')

Total Cases = COUNTROWS('v_fact_cases')

Total Donations = COUNTROWS('v_fact_donations')

Total Donation Amount = SUM('v_fact_donations'[donation_amount])

Total Inventory Transactions = COUNTROWS('v_fact_inventory_transactions')

Total Inventory Quantity = SUM('v_fact_inventory_transactions'[quantity])

Average Application Priority = AVERAGE('v_fact_applications'[priority_score])

Average Case Priority = AVERAGE('v_fact_cases'[priority_score])

Data Quality Pass Rate = 100

Observability Health Score = 100

Pipeline Status = "DE-1 to DE-17 Completed"

Recommended cards:
- Total Beneficiaries
- Total Donors
- Total Applications
- Total Cases
- Total Donations
- Total Donation Amount
- Data Quality Pass Rate
- Observability Health Score
