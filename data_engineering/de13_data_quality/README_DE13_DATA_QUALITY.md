# DE-13 Data Quality / Great Expectations

This phase validates the Silver and Gold data layers before they are trusted by the DWH and BI layer.

Main checks:
- Critical tables are not empty.
- Primary analytical keys are not null.
- Donation amounts are valid.
- Case funding values are valid.
- Inventory quantities are valid.
- Application priority scores are within expected range.
- Data quality results are saved for audit and observability.

Target layers:
- HDFS Silver
- HDFS Gold
- SQL Server DWH
