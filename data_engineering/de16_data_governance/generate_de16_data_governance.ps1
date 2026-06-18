$ErrorActionPreference = "Continue"

Write-Host "Starting DE-16 Data Governance..."

$baseDir = $PSScriptRoot
$catalogDir = Join-Path $baseDir "catalog"
$classDir = Join-Path $baseDir "classification"
$lineageDir = Join-Path $baseDir "lineage"
$policiesDir = Join-Path $baseDir "policies"
$reportsDir = Join-Path $baseDir "reports"
$resultsDir = Join-Path $baseDir "results"

New-Item -ItemType Directory -Force -Path $catalogDir, $classDir, $lineageDir, $policiesDir, $reportsDir, $resultsDir | Out-Null

$runId = Get-Date -Format "yyyyMMdd_HHmmss"
$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$dataCatalogFile = Join-Path $catalogDir "ucp_data_catalog.csv"
$classFile = Join-Path $classDir "ucp_pii_classification.csv"
$lineageFile = Join-Path $lineageDir "ucp_data_lineage.csv"
$retentionFile = Join-Path $policiesDir "ucp_retention_policy.csv"
$accessFile = Join-Path $policiesDir "ucp_access_control_policy.csv"
$governanceJsonFile = Join-Path $resultsDir "de16_data_governance_latest.json"
$governanceReportFile = Join-Path $reportsDir "DE16_DATA_GOVERNANCE_REPORT.md"

# -----------------------------
# Data Catalog
# -----------------------------
$dataCatalog = @(
    [pscustomobject]@{ layer="source"; system="SQL Server Operational DBs"; dataset="beneficiaries"; domain="beneficiary_management"; owner="charity_operations_team"; description="Beneficiary master records from each charity organization"; sensitivity="HIGH"; pii="YES"; retention="5 years" }
    [pscustomobject]@{ layer="source"; system="SQL Server Operational DBs"; dataset="beneficiary_documents"; domain="document_management"; owner="case_review_team"; description="Uploaded beneficiary supporting documents metadata"; sensitivity="HIGH"; pii="YES"; retention="5 years" }
    [pscustomobject]@{ layer="source"; system="SQL Server Operational DBs"; dataset="applications"; domain="application_processing"; owner="case_review_team"; description="Aid applications submitted by beneficiaries"; sensitivity="HIGH"; pii="YES"; retention="5 years" }
    [pscustomobject]@{ layer="source"; system="SQL Server Operational DBs"; dataset="cases"; domain="case_management"; owner="case_management_team"; description="Approved support cases and aid requirements"; sensitivity="MEDIUM"; pii="PARTIAL"; retention="5 years" }
    [pscustomobject]@{ layer="source"; system="SQL Server Operational DBs"; dataset="donors"; domain="donor_management"; owner="fundraising_team"; description="Donor profile records"; sensitivity="HIGH"; pii="YES"; retention="5 years" }
    [pscustomobject]@{ layer="source"; system="SQL Server Operational DBs"; dataset="donations"; domain="donation_management"; owner="finance_team"; description="Donation transactions"; sensitivity="MEDIUM"; pii="PARTIAL"; retention="7 years" }
    [pscustomobject]@{ layer="source"; system="SQL Server Operational DBs"; dataset="inventory_items"; domain="inventory_management"; owner="inventory_team"; description="Charity inventory item reference data"; sensitivity="LOW"; pii="NO"; retention="5 years" }
    [pscustomobject]@{ layer="source"; system="SQL Server Operational DBs"; dataset="inventory_transactions"; domain="inventory_management"; owner="inventory_team"; description="Inventory movement transactions"; sensitivity="LOW"; pii="NO"; retention="5 years" }

    [pscustomobject]@{ layer="bronze"; system="HDFS Data Lake"; dataset="/charity_data_lake/bronze/kafka_events"; domain="raw_cdc_ingestion"; owner="data_engineering_team"; description="Raw Debezium CDC events from Kafka"; sensitivity="HIGH"; pii="YES"; retention="90 days" }

    [pscustomobject]@{ layer="silver"; system="HDFS Data Lake"; dataset="/charity_data_lake/silver/beneficiaries"; domain="cleansed_beneficiary_data"; owner="data_engineering_team"; description="Cleansed beneficiary records with source organization tracking"; sensitivity="HIGH"; pii="YES"; retention="3 years" }
    [pscustomobject]@{ layer="silver"; system="HDFS Data Lake"; dataset="/charity_data_lake/silver/applications"; domain="cleansed_application_data"; owner="data_engineering_team"; description="Cleansed application records"; sensitivity="HIGH"; pii="YES"; retention="3 years" }
    [pscustomobject]@{ layer="silver"; system="HDFS Data Lake"; dataset="/charity_data_lake/silver/cases"; domain="cleansed_case_data"; owner="data_engineering_team"; description="Cleansed case records"; sensitivity="MEDIUM"; pii="PARTIAL"; retention="3 years" }
    [pscustomobject]@{ layer="silver"; system="HDFS Data Lake"; dataset="/charity_data_lake/silver/donations"; domain="cleansed_donation_data"; owner="data_engineering_team"; description="Cleansed donation records"; sensitivity="MEDIUM"; pii="PARTIAL"; retention="5 years" }

    [pscustomobject]@{ layer="gold"; system="HDFS Data Lake"; dataset="/charity_data_lake/gold/dimensions/dim_organization"; domain="analytics_dimension"; owner="analytics_team"; description="Organization dimension"; sensitivity="LOW"; pii="NO"; retention="5 years" }
    [pscustomobject]@{ layer="gold"; system="HDFS Data Lake"; dataset="/charity_data_lake/gold/dimensions/dim_beneficiary"; domain="analytics_dimension"; owner="analytics_team"; description="Beneficiary 360 analytical dimension"; sensitivity="HIGH"; pii="YES"; retention="5 years" }
    [pscustomobject]@{ layer="gold"; system="HDFS Data Lake"; dataset="/charity_data_lake/gold/dimensions/dim_donor"; domain="analytics_dimension"; owner="analytics_team"; description="Donor analytical dimension"; sensitivity="HIGH"; pii="YES"; retention="5 years" }
    [pscustomobject]@{ layer="gold"; system="HDFS Data Lake"; dataset="/charity_data_lake/gold/facts/fact_applications"; domain="analytics_fact"; owner="analytics_team"; description="Application analytics fact table"; sensitivity="MEDIUM"; pii="PARTIAL"; retention="5 years" }
    [pscustomobject]@{ layer="gold"; system="HDFS Data Lake"; dataset="/charity_data_lake/gold/facts/fact_cases"; domain="analytics_fact"; owner="analytics_team"; description="Case analytics fact table"; sensitivity="MEDIUM"; pii="PARTIAL"; retention="5 years" }
    [pscustomobject]@{ layer="gold"; system="HDFS Data Lake"; dataset="/charity_data_lake/gold/facts/fact_donations"; domain="analytics_fact"; owner="analytics_team"; description="Donation analytics fact table"; sensitivity="MEDIUM"; pii="PARTIAL"; retention="7 years" }
    [pscustomobject]@{ layer="gold"; system="HDFS Data Lake"; dataset="/charity_data_lake/gold/facts/fact_inventory_transactions"; domain="analytics_fact"; owner="analytics_team"; description="Inventory analytics fact table"; sensitivity="LOW"; pii="NO"; retention="5 years" }

    [pscustomobject]@{ layer="dwh"; system="SQL Server DWH"; dataset="charity_dwh.gold.dim_beneficiary"; domain="analytics_serving"; owner="bi_team"; description="DWH beneficiary dimension"; sensitivity="HIGH"; pii="YES"; retention="5 years" }
    [pscustomobject]@{ layer="dwh"; system="SQL Server DWH"; dataset="charity_dwh.gold.fact_donations"; domain="analytics_serving"; owner="bi_team"; description="DWH donation fact table"; sensitivity="MEDIUM"; pii="PARTIAL"; retention="7 years" }
)

$dataCatalog | Export-Csv $dataCatalogFile -NoTypeInformation -Encoding UTF8

# -----------------------------
# PII Classification
# -----------------------------
$piiClassification = @(
    [pscustomobject]@{ dataset="beneficiaries"; column_name="full_name"; classification="PII"; sensitivity="HIGH"; protection="Mask in analytics views"; allowed_roles="case_worker, data_engineer" }
    [pscustomobject]@{ dataset="beneficiaries"; column_name="national_id"; classification="SENSITIVE_PII"; sensitivity="CRITICAL"; protection="Hash/mask; never expose in dashboards"; allowed_roles="authorized_case_reviewer" }
    [pscustomobject]@{ dataset="beneficiaries"; column_name="phone"; classification="PII"; sensitivity="HIGH"; protection="Mask except last 4 digits"; allowed_roles="case_worker" }
    [pscustomobject]@{ dataset="beneficiaries"; column_name="address"; classification="PII"; sensitivity="HIGH"; protection="Generalize to governorate/city in analytics"; allowed_roles="case_worker" }
    [pscustomobject]@{ dataset="beneficiaries"; column_name="monthly_income"; classification="FINANCIAL_SENSITIVE"; sensitivity="HIGH"; protection="Aggregate for analytics"; allowed_roles="case_worker, analyst_restricted" }
    [pscustomobject]@{ dataset="beneficiary_documents"; column_name="document_url"; classification="SENSITIVE_DOCUMENT"; sensitivity="CRITICAL"; protection="Restricted access; audit every access"; allowed_roles="authorized_case_reviewer" }
    [pscustomobject]@{ dataset="donors"; column_name="donor_name"; classification="PII"; sensitivity="HIGH"; protection="Mask in public reports"; allowed_roles="fundraising_team" }
    [pscustomobject]@{ dataset="donors"; column_name="email"; classification="PII"; sensitivity="HIGH"; protection="Mask in analytics"; allowed_roles="fundraising_team" }
    [pscustomobject]@{ dataset="donations"; column_name="donation_amount"; classification="FINANCIAL"; sensitivity="MEDIUM"; protection="Aggregate in dashboards"; allowed_roles="finance_team, bi_team" }
    [pscustomobject]@{ dataset="applications"; column_name="case_description"; classification="SENSITIVE_CONTEXT"; sensitivity="HIGH"; protection="Restrict free-text access"; allowed_roles="case_worker, case_reviewer" }
)

$piiClassification | Export-Csv $classFile -NoTypeInformation -Encoding UTF8

# -----------------------------
# Data Lineage
# -----------------------------
$dataLineage = @(
    [pscustomobject]@{ step_order=1; source="charity_*_operational SQL Server"; process="CDC enabled tables"; target="SQL Server CDC change tables"; owner="data_engineering_team" }
    [pscustomobject]@{ step_order=2; source="SQL Server CDC"; process="Debezium SQL Server connectors"; target="Kafka CDC topics"; owner="data_engineering_team" }
    [pscustomobject]@{ step_order=3; source="Kafka CDC topics"; process="Schema Registry governance"; target="charity-cdc-event-envelope-value schema"; owner="data_platform_team" }
    [pscustomobject]@{ step_order=4; source="Kafka CDC topics"; process="Spark DE-8 ingestion"; target="HDFS Bronze kafka_events"; owner="data_engineering_team" }
    [pscustomobject]@{ step_order=5; source="HDFS Bronze"; process="Spark DE-9 cleansing and standardization"; target="HDFS Silver tables"; owner="data_engineering_team" }
    [pscustomobject]@{ step_order=6; source="HDFS Silver"; process="Spark DE-10 dimensional modeling"; target="HDFS Gold dimensions and facts"; owner="analytics_engineering_team" }
    [pscustomobject]@{ step_order=7; source="HDFS Gold"; process="Spark DE-11 JDBC load"; target="SQL Server DWH gold schema"; owner="data_engineering_team" }
    [pscustomobject]@{ step_order=8; source="Silver, Gold, DWH"; process="DE-13 data quality checks"; target="Data quality results"; owner="data_quality_team" }
    [pscustomobject]@{ step_order=9; source="Platform services and outputs"; process="DE-15 observability collector"; target="Monitoring reports in HDFS"; owner="platform_operations_team" }
)

$dataLineage | Export-Csv $lineageFile -NoTypeInformation -Encoding UTF8

# -----------------------------
# Retention Policy
# -----------------------------
$retentionPolicy = @(
    [pscustomobject]@{ layer="bronze"; dataset="raw CDC events"; retention_period="90 days"; reason="Raw immutable events are kept temporarily for replay and audit"; action_after_retention="archive or purge" }
    [pscustomobject]@{ layer="silver"; dataset="cleansed operational entities"; retention_period="3 years"; reason="Operational analysis and cross-charity history"; action_after_retention="archive" }
    [pscustomobject]@{ layer="gold"; dataset="analytics dimensions and facts"; retention_period="5 years"; reason="Long-term analytics and trend analysis"; action_after_retention="archive" }
    [pscustomobject]@{ layer="dwh"; dataset="gold schema tables"; retention_period="5 to 7 years"; reason="Business reporting and financial audit"; action_after_retention="archive" }
    [pscustomobject]@{ layer="documents"; dataset="beneficiary documents"; retention_period="5 years or legal requirement"; reason="Case verification and compliance"; action_after_retention="secure deletion" }
    [pscustomobject]@{ layer="observability"; dataset="monitoring and quality reports"; retention_period="1 year"; reason="Operational audit and troubleshooting"; action_after_retention="archive" }
)

$retentionPolicy | Export-Csv $retentionFile -NoTypeInformation -Encoding UTF8

# -----------------------------
# Access Control Policy
# -----------------------------
$accessPolicy = @(
    [pscustomobject]@{ role="beneficiary"; access_scope="Own application status only"; sensitive_access="NO"; notes="Cannot view other beneficiaries" }
    [pscustomobject]@{ role="donor"; access_scope="Anonymized public cases and donation flows"; sensitive_access="NO"; notes="No beneficiary identity exposure" }
    [pscustomobject]@{ role="case_worker"; access_scope="Assigned applications and beneficiary profiles"; sensitive_access="YES"; notes="Access should be audited" }
    [pscustomobject]@{ role="organization_admin"; access_scope="Organization-level operations and reports"; sensitive_access="LIMITED"; notes="Restricted to own organization" }
    [pscustomobject]@{ role="data_engineer"; access_scope="Pipeline, lake, schema, and DWH maintenance"; sensitive_access="CONTROLLED"; notes="No unnecessary document content access" }
    [pscustomobject]@{ role="bi_analyst"; access_scope="Gold/DWH analytical tables"; sensitive_access="MASKED"; notes="PII should be masked or aggregated" }
    [pscustomobject]@{ role="platform_admin"; access_scope="System and infrastructure administration"; sensitive_access="CONTROLLED"; notes="Privileged access must be logged" }
)

$accessPolicy | Export-Csv $accessFile -NoTypeInformation -Encoding UTF8

# -----------------------------
# Governance JSON Summary
# -----------------------------
$summary = [pscustomobject]@{
    run_id = $runId
    generated_at = $generatedAt
    governance_domains = @("data_catalog", "pii_classification", "lineage", "retention", "access_control")
    data_catalog_records = $dataCatalog.Count
    pii_classification_records = $piiClassification.Count
    lineage_steps = $dataLineage.Count
    retention_rules = $retentionPolicy.Count
    access_roles = $accessPolicy.Count
    files = @{
        data_catalog = $dataCatalogFile
        pii_classification = $classFile
        lineage = $lineageFile
        retention_policy = $retentionFile
        access_policy = $accessFile
        report = $governanceReportFile
    }
}

$summary | ConvertTo-Json -Depth 10 | Set-Content $governanceJsonFile -Encoding UTF8

# -----------------------------
# Markdown Governance Report
# -----------------------------
$md = @()
$md += "# DE-16 Data Governance Report"
$md += ""
$md += "**Run ID:** $runId"
$md += ""
$md += "**Generated At:** $generatedAt"
$md += ""
$md += "## Governance Scope"
$md += ""
$md += "This phase defines governance controls for the Unified Charity Platform data ecosystem, covering source systems, Kafka CDC events, HDFS Bronze/Silver/Gold layers, SQL Server DWH, data quality results, and observability outputs."
$md += ""
$md += "## Governance Deliverables"
$md += ""
$md += "- Data Catalog records: $($dataCatalog.Count)"
$md += "- PII Classification records: $($piiClassification.Count)"
$md += "- Data Lineage steps: $($dataLineage.Count)"
$md += "- Retention policy rules: $($retentionPolicy.Count)"
$md += "- Access control roles: $($accessPolicy.Count)"
$md += ""
$md += "## Key Governance Decisions"
$md += ""
$md += "- Beneficiary and donor attributes are classified as high-sensitivity PII."
$md += "- National ID and document metadata are treated as critical sensitive data."
$md += "- Donor and beneficiary identities must not be exposed in public dashboards."
$md += "- Gold and DWH analytics should use masked, aggregated, or role-restricted views."
$md += "- Raw Bronze CDC events are retained temporarily for replay and audit."
$md += "- Data quality and observability reports are archived in HDFS for auditability."
$md += ""
$md += "## Data Lineage Summary"
$md += ""
$md += "Operational SQL Server databases flow through CDC and Debezium into Kafka, governed by Schema Registry, ingested into HDFS Bronze, transformed into Silver, modeled into Gold, loaded into SQL Server DWH, validated through data quality checks, and monitored by the observability framework."
$md += ""
$md += "## Defense Statement"
$md += ""
$md += "The project implements a practical data governance framework by documenting the data catalog, sensitive data classification, lineage, ownership, retention, and access control policies. These artifacts support compliance, auditability, security, and responsible analytics across the complete data engineering pipeline."
$md += ""
$md += "## Generated Files"
$md += ""
$md += "- catalog/ucp_data_catalog.csv"
$md += "- classification/ucp_pii_classification.csv"
$md += "- lineage/ucp_data_lineage.csv"
$md += "- policies/ucp_retention_policy.csv"
$md += "- policies/ucp_access_control_policy.csv"
$md += "- results/de16_data_governance_latest.json"

$md | Set-Content $governanceReportFile -Encoding UTF8

# -----------------------------
# Archive to HDFS
# -----------------------------
Write-Host "Archiving governance artifacts into HDFS..."

docker exec ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/gold/governance/de16 2>$null
docker exec ucp_hdfs_namenode hdfs dfs -chmod -R 777 /charity_data_lake/gold/governance 2>$null

$filesToArchive = @(
    $dataCatalogFile,
    $classFile,
    $lineageFile,
    $retentionFile,
    $accessFile,
    $governanceJsonFile,
    $governanceReportFile
)

foreach ($file in $filesToArchive) {
    $fileName = Split-Path $file -Leaf
    docker cp $file "ucp_hdfs_namenode:/tmp/$fileName" 2>$null
    docker exec ucp_hdfs_namenode hdfs dfs -put -f "/tmp/$fileName" "/charity_data_lake/gold/governance/de16/$fileName" 2>$null
}

Write-Host ""
Write-Host "DE-16 DATA GOVERNANCE SUMMARY"
Write-Host "Data catalog records: $($dataCatalog.Count)"
Write-Host "PII classification records: $($piiClassification.Count)"
Write-Host "Lineage steps: $($dataLineage.Count)"
Write-Host "Retention rules: $($retentionPolicy.Count)"
Write-Host "Access roles: $($accessPolicy.Count)"
Write-Host "Governance report: $governanceReportFile"
Write-Host "HDFS archive: /charity_data_lake/gold/governance/de16"
Write-Host ""
Write-Host "DE-16 completed."
