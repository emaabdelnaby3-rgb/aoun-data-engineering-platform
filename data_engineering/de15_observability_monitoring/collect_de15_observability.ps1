$ErrorActionPreference = "Continue"

Write-Host "Starting DE-15 Observability / Monitoring..."

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$resultsDir = Join-Path $PSScriptRoot "results"
$reportsDir = Join-Path $PSScriptRoot "reports"

New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null

$runId = Get-Date -Format "yyyyMMdd_HHmmss"
$checkedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$csvFile = Join-Path $resultsDir "de15_observability_latest.csv"
$jsonFile = Join-Path $resultsDir "de15_observability_latest.json"
$mdFile = Join-Path $reportsDir "DE15_OBSERVABILITY_HEALTH_REPORT.md"

$metrics = New-Object System.Collections.Generic.List[object]

function Add-Metric {
    param(
        [string]$Component,
        [string]$MetricName,
        [string]$Status,
        [string]$Value,
        [string]$Details
    )

    $metrics.Add([pscustomobject]@{
        run_id = $runId
        checked_at = $checkedAt
        component = $Component
        metric_name = $MetricName
        status = $Status
        value = $Value
        details = $Details
    }) | Out-Null
}

# -----------------------------
# Docker container monitoring
# -----------------------------
Write-Host "Checking Docker containers..."

$requiredContainers = @(
    "ucp_sqlserver",
    "ucp_zookeeper",
    "ucp_kafka",
    "ucp_debezium_connect",
    "ucp_schema_registry",
    "ucp_hdfs_namenode",
    "ucp_hdfs_datanode",
    "ucp_spark_master",
    "ucp_spark_worker",
    "ucp_airflow_postgres",
    "ucp_airflow_webserver",
    "ucp_airflow_scheduler"
)

$runningContainers = docker ps --format "{{.Names}}" 2>$null

foreach ($container in $requiredContainers) {
    if ($runningContainers -contains $container) {
        Add-Metric "docker" $container "PASS" "running" "$container is running"
    } else {
        Add-Metric "docker" $container "FAIL" "not_running" "$container is not running"
    }
}

# -----------------------------
# Schema Registry monitoring
# -----------------------------
Write-Host "Checking Schema Registry..."

$schemaSubject = "charity-cdc-event-envelope-value"
$subjects = curl.exe -s --max-time 10 http://127.0.0.1:8081/subjects 2>$null

if ($subjects -match $schemaSubject) {
    Add-Metric "schema_registry" "registered_subject" "PASS" $schemaSubject "Schema subject exists"
} else {
    Add-Metric "schema_registry" "registered_subject" "FAIL" "missing" "Schema subject is missing or API is unreachable"
}

# -----------------------------
# Airflow monitoring
# -----------------------------
Write-Host "Checking Airflow..."

$airflowHealthRaw = curl.exe -s --max-time 10 http://127.0.0.1:8088/health 2>$null

try {
    $airflowHealth = $airflowHealthRaw | ConvertFrom-Json

    if ($airflowHealth.metadatabase.status -eq "healthy") {
        Add-Metric "airflow" "metadatabase_health" "PASS" "healthy" "Airflow metadata database is healthy"
    } else {
        Add-Metric "airflow" "metadatabase_health" "FAIL" "$($airflowHealth.metadatabase.status)" "Airflow metadata database is not healthy"
    }

    if ($airflowHealth.scheduler.status -eq "healthy") {
        Add-Metric "airflow" "scheduler_health" "PASS" "healthy" "Airflow scheduler is healthy"
    } else {
        Add-Metric "airflow" "scheduler_health" "FAIL" "$($airflowHealth.scheduler.status)" "Airflow scheduler is not healthy"
    }
} catch {
    Add-Metric "airflow" "health_endpoint" "FAIL" "unreachable" "Could not parse Airflow health endpoint"
}

$dagRuns = docker exec ucp_airflow_scheduler airflow dags list-runs -d ucp_de_pipeline_orchestration 2>$null
$dagRunsText = $dagRuns -join "`n"

if ($dagRunsText -match "success") {
    Add-Metric "airflow" "latest_successful_dag_run" "PASS" "success_found" "At least one successful DAG run exists"
} elseif ($dagRunsText -match "running") {
    Add-Metric "airflow" "latest_successful_dag_run" "WARN" "running" "DAG has a running execution but no success detected yet"
} else {
    Add-Metric "airflow" "latest_successful_dag_run" "WARN" "no_success_found" "No successful DAG run detected yet"
}

# -----------------------------
# HDFS monitoring
# -----------------------------
Write-Host "Checking HDFS data lake folders..."

$hdfsFolders = @(
    "/charity_data_lake/bronze",
    "/charity_data_lake/silver",
    "/charity_data_lake/gold",
    "/charity_data_lake/silver/data_quality_issues",
    "/charity_data_lake/gold/dimensions",
    "/charity_data_lake/gold/facts"
)

foreach ($folder in $hdfsFolders) {
    docker exec ucp_hdfs_namenode hdfs dfs -test -d $folder 2>$null

    if ($LASTEXITCODE -eq 0) {
        Add-Metric "hdfs" $folder "PASS" "exists" "$folder exists"
    } else {
        Add-Metric "hdfs" $folder "FAIL" "missing" "$folder is missing"
    }
}

# -----------------------------
# SQL Server DWH monitoring
# -----------------------------
Write-Host "Checking SQL Server DWH row counts..."

$dwhTables = @(
    "charity_dwh.gold.dim_organization",
    "charity_dwh.gold.dim_beneficiary",
    "charity_dwh.gold.dim_donor",
    "charity_dwh.gold.fact_applications",
    "charity_dwh.gold.fact_cases",
    "charity_dwh.gold.fact_donations",
    "charity_dwh.gold.fact_inventory_transactions"
)

foreach ($table in $dwhTables) {
    $query = "SET NOCOUNT ON; SELECT COUNT(*) FROM $table;"
    $result = docker exec ucp_sqlserver /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "ChangeMe_StrongPassword_2026!" -Q $query -h -1 -W 2>$null

    $rowCount = ($result | Where-Object { $_.Trim() -match "^\d+$" } | Select-Object -First 1).Trim()

    if ($rowCount -and [int]$rowCount -gt 0) {
        Add-Metric "sqlserver_dwh" $table "PASS" $rowCount "$table contains rows"
    } else {
        Add-Metric "sqlserver_dwh" $table "FAIL" "0" "$table is empty or unreadable"
    }
}

# -----------------------------
# DE-13 Data Quality monitoring
# -----------------------------
Write-Host "Checking DE-13 Data Quality results..."

$de13Csv = Join-Path $projectRoot "data_engineering\de13_data_quality\results\de13_latest_results.csv"

if (Test-Path $de13Csv) {
    $dqRows = Import-Csv $de13Csv

    $totalChecks = @($dqRows).Count
    $passedChecks = @($dqRows | Where-Object { $_.status -eq "PASS" }).Count
    $failedChecks = @($dqRows | Where-Object { $_.status -eq "FAIL" }).Count
    $warnChecks = @($dqRows | Where-Object { $_.status -eq "WARN" }).Count

    Add-Metric "data_quality" "total_checks" "PASS" "$totalChecks" "Total DE-13 checks"
    Add-Metric "data_quality" "passed_checks" "PASS" "$passedChecks" "Passed DE-13 checks"

    if ($failedChecks -eq 0) {
        Add-Metric "data_quality" "failed_checks" "PASS" "0" "No failed DE-13 data quality checks"
    } else {
        Add-Metric "data_quality" "failed_checks" "FAIL" "$failedChecks" "Some DE-13 data quality checks failed"
    }

    if ($warnChecks -eq 0) {
        Add-Metric "data_quality" "warning_checks" "PASS" "0" "No warning DE-13 data quality checks"
    } else {
        Add-Metric "data_quality" "warning_checks" "WARN" "$warnChecks" "Some DE-13 data quality warnings exist"
    }
} else {
    Add-Metric "data_quality" "de13_result_file" "FAIL" "missing" "DE-13 result CSV is missing"
}

# -----------------------------
# Overall health score
# -----------------------------
$totalMetrics = $metrics.Count
$passMetrics = @($metrics | Where-Object { $_.status -eq "PASS" }).Count
$failMetrics = @($metrics | Where-Object { $_.status -eq "FAIL" }).Count
$warnMetrics = @($metrics | Where-Object { $_.status -eq "WARN" }).Count

if ($totalMetrics -gt 0) {
    $healthScore = [math]::Round(($passMetrics / $totalMetrics) * 100, 2)
} else {
    $healthScore = 0
}

$overallStatus = "PASS"
if ($failMetrics -gt 0) {
    $overallStatus = "FAIL"
} elseif ($warnMetrics -gt 0) {
    $overallStatus = "WARN"
}

Add-Metric "overall" "ucp_observability_health_score" $overallStatus "$healthScore%" "PASS=$passMetrics, WARN=$warnMetrics, FAIL=$failMetrics, TOTAL=$totalMetrics"

# -----------------------------
# Write reports
# -----------------------------
Write-Host "Writing observability reports..."

$metrics | Export-Csv $csvFile -NoTypeInformation -Encoding UTF8
$metrics | ConvertTo-Json -Depth 10 | Set-Content $jsonFile -Encoding UTF8

$mdLines = @()
$mdLines += "# DE-15 Observability / Monitoring Health Report"
$mdLines += ""
$mdLines += "**Run ID:** $runId"
$mdLines += ""
$mdLines += "**Checked At:** $checkedAt"
$mdLines += ""
$mdLines += "## Summary"
$mdLines += ""
$mdLines += "- Total metrics: $($metrics.Count)"
$mdLines += "- Passed: $(@($metrics | Where-Object { $_.status -eq 'PASS' }).Count)"
$mdLines += "- Warnings: $(@($metrics | Where-Object { $_.status -eq 'WARN' }).Count)"
$mdLines += "- Failed: $(@($metrics | Where-Object { $_.status -eq 'FAIL' }).Count)"
$mdLines += ""
$mdLines += "## Metrics"
$mdLines += ""
$mdLines += "| Component | Metric | Status | Value | Details |"
$mdLines += "|---|---|---|---|---|"

foreach ($m in $metrics) {
    $safeDetails = ($m.details -replace "\|", "/")
    $mdLines += "| $($m.component) | $($m.metric_name) | $($m.status) | $($m.value) | $safeDetails |"
}

$mdLines | Set-Content $mdFile -Encoding UTF8

# -----------------------------
# Archive reports into HDFS
# -----------------------------
Write-Host "Archiving observability reports into HDFS..."

docker exec ucp_hdfs_namenode hdfs dfs -mkdir -p /charity_data_lake/gold/observability/de15 2>$null
docker exec ucp_hdfs_namenode hdfs dfs -chmod -R 777 /charity_data_lake/gold/observability 2>$null

$filesToArchive = @($csvFile, $jsonFile, $mdFile)

foreach ($file in $filesToArchive) {
    $fileName = Split-Path $file -Leaf
    docker cp $file "ucp_hdfs_namenode:/tmp/$fileName" 2>$null
    docker exec ucp_hdfs_namenode hdfs dfs -put -f "/tmp/$fileName" "/charity_data_lake/gold/observability/de15/$fileName" 2>$null
}

Write-Host ""
Write-Host "DE-15 OBSERVABILITY SUMMARY"
Write-Host "Total metrics: $($metrics.Count)"
Write-Host "Passed: $(@($metrics | Where-Object { $_.status -eq 'PASS' }).Count)"
Write-Host "Warnings: $(@($metrics | Where-Object { $_.status -eq 'WARN' }).Count)"
Write-Host "Failed: $(@($metrics | Where-Object { $_.status -eq 'FAIL' }).Count)"
Write-Host "CSV report: $csvFile"
Write-Host "JSON report: $jsonFile"
Write-Host "Markdown report: $mdFile"
Write-Host "HDFS archive: /charity_data_lake/gold/observability/de15"
Write-Host ""
Write-Host "DE-15 completed."

