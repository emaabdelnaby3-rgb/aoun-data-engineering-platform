param(
    [switch]$SeedDemoData,
    [switch]$RunApps,
    [switch]$PauseBetweenSteps,
    [switch]$OpenUrls
)

$ErrorActionPreference = "Continue"
$env:COMPOSE_IGNORE_ORPHANS = "true"
$ProjectRoot = (Get-Location).Path
$LogDir = Join-Path $ProjectRoot "data_engineering\demo_run\logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$RunId = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path $LogDir "DEMO_DE1_DE17_$RunId.log"
$CsvFile = Join-Path $LogDir "DEMO_DE1_DE17_STATUS_$RunId.csv"

$script:CurrentPhase = "BOOT"
$script:Results = @()

function Pause-Demo {
    if ($PauseBetweenSteps) {
        Write-Host ""
        Read-Host "Press ENTER to continue to next phase"
    }
}

function Phase {
    param([string]$Code, [string]$Title)

    $script:CurrentPhase = "$Code - $Title"
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "$Code | $Title" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Add-Content $LogFile "`n============================================================"
    Add-Content $LogFile "$Code | $Title"
    Add-Content $LogFile "============================================================"
}

function Add-Result {
    param(
        [string]$Step,
        [string]$Status,
        [string]$Message
    )

    $script:Results += [pscustomobject]@{
        Time    = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Phase   = $script:CurrentPhase
        Step    = $Step
        Status  = $Status
        Message = $Message
    }
}

function Run-Step {
    param(
        [string]$Name,
        [scriptblock]$Command,
        [bool]$Critical = $false
    )

    Write-Host ""
    Write-Host ">>> $Name" -ForegroundColor Yellow
    Add-Content $LogFile "`n>>> $Name"

    $global:LASTEXITCODE = 0

    try {
        & $Command 2>&1 | Tee-Object -FilePath $LogFile -Append

        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARN/FAIL: $Name finished with exit code $LASTEXITCODE" -ForegroundColor Red
            Add-Result $Name "WARN" "ExitCode=$LASTEXITCODE"

            if ($Critical) {
                throw "$Name failed"
            }
        }
        else {
            Write-Host "PASS: $Name" -ForegroundColor Green
            Add-Result $Name "PASS" "Completed"
        }
    }
    catch {
        Write-Host "ERROR: $Name" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Add-Result $Name "FAIL" $_.Exception.Message

        if ($Critical) {
            throw
        }
    }
}

function Run-PSFile {
    param(
        [string]$RelativePath,
        [bool]$Critical = $false
    )

    $FullPath = Join-Path $ProjectRoot $RelativePath

    if (Test-Path $FullPath) {
        Run-Step $RelativePath {
            powershell -NoProfile -ExecutionPolicy Bypass -File $FullPath
        } $Critical
    }
    else {
        Write-Host "SKIP: $RelativePath not found" -ForegroundColor DarkYellow
        Add-Result $RelativePath "SKIP" "File not found"
    }
}

function Run-FirstScriptLike {
    param(
        [int]$PhaseNumber,
        [string]$Pattern,
        [bool]$Critical = $false
    )

    $folder = Get-ChildItem ".\data_engineering" -Directory -Filter ("de{0}_*" -f $PhaseNumber) -ErrorAction SilentlyContinue | Select-Object -First 1

    if (-not $folder) {
        Add-Result "Find script for DE-$PhaseNumber" "SKIP" "Folder not found"
        Write-Host "SKIP: DE-$PhaseNumber folder not found" -ForegroundColor DarkYellow
        return
    }

    $script = Get-ChildItem $folder.FullName -Recurse -Filter "*.ps1" |
        Where-Object { $_.Name -match $Pattern } |
        Select-Object -First 1

    if ($script) {
        Run-Step $script.FullName {
            powershell -NoProfile -ExecutionPolicy Bypass -File $script.FullName
        } $Critical
    }
    else {
        Add-Result "Find script $Pattern for DE-$PhaseNumber" "SKIP" "Script not found"
        Write-Host "SKIP: No script matching $Pattern in $($folder.Name)" -ForegroundColor DarkYellow
    }
}

function Run-ValidatorsForPhase {
    param([int]$PhaseNumber)

    $folders = Get-ChildItem ".\data_engineering" -Directory -Filter ("de{0}_*" -f $PhaseNumber) -ErrorAction SilentlyContinue

    foreach ($folder in $folders) {
        $validators = Get-ChildItem $folder.FullName -Recurse -Filter "*.ps1" |
            Where-Object { $_.Name -match "validate|check|test" }

        foreach ($v in $validators) {
            Run-Step $v.FullName {
                powershell -NoProfile -ExecutionPolicy Bypass -File $v.FullName
            } $false
        }
    }
}

function SQL {
    param(
        [string]$Name,
        [string]$Database,
        [string]$Query
    )

    Run-Step $Name {
        docker exec ucp_sqlserver /opt/mssql-tools18/bin/sqlcmd `
            -C `
            -S localhost `
            -U sa `
            -P "ChangeMe_StrongPassword_2026!" `
            -d $Database `
            -Q $Query
    } $false
}

Clear-Host

Write-Host "UNIFIED CHARITY PLATFORM - FULL DATA ENGINEERING DEMO" -ForegroundColor Cyan
Write-Host "Running phases DE-1 to DE-17" -ForegroundColor Cyan
Write-Host "Project: $ProjectRoot" -ForegroundColor Gray
Write-Host "Log: $LogFile" -ForegroundColor Gray

Phase "BOOT" "Start Docker Infrastructure"

Run-Step "Docker version" {
    docker version
} $false

if (Test-Path ".\infra\docker-compose.presentation.yml") {
    Run-Step "Start main infrastructure containers" {
        Push-Location ".\infra"
        docker compose -f .\docker-compose.presentation.yml up -d
        Pop-Location
    } $true
}

if (Test-Path ".\infra\docker-compose.airflow.yml") {
    Run-Step "Start Airflow containers" {
        Push-Location ".\infra"
        docker compose -f .\docker-compose.airflow.yml up -d airflow-postgres
        docker compose -f .\docker-compose.airflow.yml up airflow-init
        docker compose -f .\docker-compose.airflow.yml up -d airflow-webserver airflow-scheduler
        Pop-Location
    } $false
}

Run-Step "Show running UCP containers" {
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | findstr /I "ucp_"
} $false

if ($RunApps) {
    Phase "APP" "Start Frontend and Backend"

    if (Test-Path ".\backend") {
        Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$ProjectRoot\backend'; uvicorn app.main:app --reload"
        Add-Result "Start backend" "PASS" "Started in new terminal"
    }

    if (Test-Path ".\frontend") {
        Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$ProjectRoot\frontend'; npm run dev"
        Add-Result "Start frontend" "PASS" "Started in new terminal"
    }

    Start-Sleep -Seconds 8
}

if ($SeedDemoData) {
    Phase "DEMO DATA" "Insert Realistic Operational Demo Data"

    Run-PSFile "data_engineering\demo_operational_seed\seed_demo_story_pack.ps1" $false

    Write-Host "Waiting 60 seconds for CDC/Debezium/Kafka to capture demo changes..." -ForegroundColor Yellow
    Start-Sleep -Seconds 60
}

Pause-Demo

Phase "DE-1" "Synthetic Data Generation"

Run-ValidatorsForPhase 1

SQL "DE-1 Source operational row counts - Food Bank" "charity_food_bank_operational" "
SELECT 'beneficiaries' table_name, COUNT_BIG(*) rows_count FROM dbo.beneficiaries
UNION ALL SELECT 'applications', COUNT_BIG(*) FROM dbo.applications
UNION ALL SELECT 'cases', COUNT_BIG(*) FROM dbo.cases
UNION ALL SELECT 'donors', COUNT_BIG(*) FROM dbo.donors
UNION ALL SELECT 'donations', COUNT_BIG(*) FROM dbo.donations
UNION ALL SELECT 'inventory_transactions', COUNT_BIG(*) FROM dbo.inventory_transactions;
"

SQL "DE-1 Source operational row counts - Resala" "charity_resala_operational" "
SELECT 'beneficiaries' table_name, COUNT_BIG(*) rows_count FROM dbo.beneficiaries
UNION ALL SELECT 'applications', COUNT_BIG(*) FROM dbo.applications
UNION ALL SELECT 'cases', COUNT_BIG(*) FROM dbo.cases
UNION ALL SELECT 'donors', COUNT_BIG(*) FROM dbo.donors
UNION ALL SELECT 'donations', COUNT_BIG(*) FROM dbo.donations
UNION ALL SELECT 'inventory_transactions', COUNT_BIG(*) FROM dbo.inventory_transactions;
"

SQL "DE-1 Source operational row counts - Haya Karima" "charity_haya_karima_operational" "
SELECT 'beneficiaries' table_name, COUNT_BIG(*) rows_count FROM dbo.beneficiaries
UNION ALL SELECT 'applications', COUNT_BIG(*) FROM dbo.applications
UNION ALL SELECT 'cases', COUNT_BIG(*) FROM dbo.cases
UNION ALL SELECT 'donors', COUNT_BIG(*) FROM dbo.donors
UNION ALL SELECT 'donations', COUNT_BIG(*) FROM dbo.donations
UNION ALL SELECT 'inventory_transactions', COUNT_BIG(*) FROM dbo.inventory_transactions;
"

Pause-Demo

Phase "DE-2" "Load Source Operational Databases"

Run-ValidatorsForPhase 2

SQL "DE-2 Verify source databases exist" "master" "
SELECT name AS database_name, create_date
FROM sys.databases
WHERE name IN
(
 'charity_food_bank_operational',
 'charity_resala_operational',
 'charity_haya_karima_operational'
)
ORDER BY name;
"

Pause-Demo

Phase "DE-3" "SQL Server CDC Enabled"

Run-ValidatorsForPhase 3

SQL "DE-3 CDC enabled databases" "master" "
SELECT name AS database_name, is_cdc_enabled
FROM sys.databases
WHERE name IN
(
 'charity_food_bank_operational',
 'charity_resala_operational',
 'charity_haya_karima_operational'
);
"

SQL "DE-3 CDC tracked tables - Food Bank" "charity_food_bank_operational" "
SELECT name AS table_name, is_tracked_by_cdc
FROM sys.tables
WHERE is_tracked_by_cdc = 1
ORDER BY name;
"

SQL "DE-3 CDC tracked tables - Resala" "charity_resala_operational" "
SELECT name AS table_name, is_tracked_by_cdc
FROM sys.tables
WHERE is_tracked_by_cdc = 1
ORDER BY name;
"

SQL "DE-3 CDC tracked tables - Haya Karima" "charity_haya_karima_operational" "
SELECT name AS table_name, is_tracked_by_cdc
FROM sys.tables
WHERE is_tracked_by_cdc = 1
ORDER BY name;
"

Pause-Demo

Phase "DE-4" "Kafka and Debezium Infrastructure"

Run-ValidatorsForPhase 4

Run-Step "DE-4 Kafka and Debezium containers" {
    docker ps --format "table {{.Names}}\t{{.Status}}" | findstr /I "kafka debezium zookeeper"
} $false

Run-Step "DE-4 Kafka topics list" {
    docker exec ucp_kafka kafka-topics --bootstrap-server localhost:9092 --list
} $false

Pause-Demo

Phase "DE-5" "Debezium Source Connectors"

Run-ValidatorsForPhase 5

Run-Step "DE-5 Debezium Connect REST API connectors" {
    curl.exe -s http://127.0.0.1:8083/connectors
} $false

Run-Step "DE-5 Debezium Connect connector status" {
    curl.exe -s http://127.0.0.1:8083/connectors/food-bank-sqlserver-connector/status
    curl.exe -s http://127.0.0.1:8083/connectors/resala-sqlserver-connector/status
    curl.exe -s http://127.0.0.1:8083/connectors/haya-karima-sqlserver-connector/status
} $false

Pause-Demo

Phase "DE-6" "Kafka CDC Events"

Run-ValidatorsForPhase 6

Run-Step "DE-6 Show charity Kafka topics" {
    docker exec ucp_kafka kafka-topics --bootstrap-server localhost:9092 --list | findstr /I "charity dbo food_bank resala haya"
} $false

Pause-Demo

Phase "DE-7" "HDFS Data Lake Folders"

Run-PSFile "data_engineering\de7_hdfs_data_lake\create_hdfs_folders.ps1" $false
Run-ValidatorsForPhase 7

Run-Step "DE-7 Show HDFS Data Lake structure" {
    docker exec ucp_hdfs_namenode hdfs dfs -ls -R /charity_data_lake
} $false

Pause-Demo

Phase "DE-8" "Kafka Debezium to HDFS Bronze"

Run-PSFile "data_engineering\de8_spark_bronze\run_de8_spark_bronze.ps1" $true
Run-PSFile "data_engineering\de8_spark_bronze\validate_de8_bronze.ps1" $false

Run-Step "DE-8 Bronze parquet proof" {
    docker exec ucp_hdfs_namenode hdfs dfs -find /charity_data_lake/bronze/kafka_events -name "*.parquet" | Select-Object -First 20
} $false

Pause-Demo

Phase "DE-9" "Bronze to Silver"

Run-PSFile "data_engineering\de9_spark_silver\run_de9_spark_silver.ps1" $true
Run-PSFile "data_engineering\de9_spark_silver\validate_de9_silver.ps1" $false

Run-Step "DE-9 Silver folders proof" {
    docker exec ucp_hdfs_namenode hdfs dfs -ls /charity_data_lake/silver
} $false

Pause-Demo

Phase "DE-10" "Silver to Gold"

Run-PSFile "data_engineering\de10_spark_gold\run_de10_spark_gold.ps1" $true
Run-PSFile "data_engineering\de10_spark_gold\validate_de10_gold.ps1" $false

Run-Step "DE-10 Gold folders proof" {
    docker exec ucp_hdfs_namenode hdfs dfs -ls -R /charity_data_lake/gold | Select-Object -First 80
} $false

Pause-Demo

Phase "DE-11" "Gold to SQL Server Data Warehouse"

Run-PSFile "data_engineering\de11_gold_to_dwh\run_de11_gold_to_dwh.ps1" $true
Run-PSFile "data_engineering\de11_gold_to_dwh\validate_de11_gold_to_dwh.ps1" $false

SQL "DE-11 DWH Gold row counts" "charity_dwh" "
SELECT 'gold.dim_organization' table_name, COUNT_BIG(*) rows_count FROM gold.dim_organization
UNION ALL SELECT 'gold.dim_beneficiary', COUNT_BIG(*) FROM gold.dim_beneficiary
UNION ALL SELECT 'gold.dim_donor', COUNT_BIG(*) FROM gold.dim_donor
UNION ALL SELECT 'gold.fact_applications', COUNT_BIG(*) FROM gold.fact_applications
UNION ALL SELECT 'gold.fact_cases', COUNT_BIG(*) FROM gold.fact_cases
UNION ALL SELECT 'gold.fact_donations', COUNT_BIG(*) FROM gold.fact_donations
UNION ALL SELECT 'gold.fact_inventory_transactions', COUNT_BIG(*) FROM gold.fact_inventory_transactions;
"

Pause-Demo

Phase "DE-12" "Schema Registry"

Run-FirstScriptLike 12 "register|schema" $false
Run-ValidatorsForPhase 12

Run-Step "DE-12 Schema Registry subjects" {
    curl.exe -s http://127.0.0.1:8081/subjects
} $false

Pause-Demo

Phase "DE-13" "Data Quality Framework"

Run-PSFile "data_engineering\de13_data_quality\run_de13_data_quality.ps1" $true
Run-PSFile "data_engineering\de13_data_quality\validate_de13_data_quality.ps1" $false

Run-Step "DE-13 Data Quality HDFS proof" {
    docker exec ucp_hdfs_namenode hdfs dfs -ls -R /charity_data_lake/silver/data_quality_issues
} $false

Pause-Demo

Phase "DE-14" "Airflow Orchestration"

Run-ValidatorsForPhase 14

Run-Step "DE-14 Airflow DAG list" {
    docker exec ucp_airflow_scheduler airflow dags list | findstr /I "ucp_de_pipeline"
} $false

Run-Step "DE-14 Trigger Airflow DAG" {
    docker exec ucp_airflow_scheduler airflow dags trigger ucp_de_pipeline_orchestration
} $false

Start-Sleep -Seconds 10

Run-Step "DE-14 Airflow DAG recent runs" {
    docker exec ucp_airflow_scheduler airflow dags list-runs -d ucp_de_pipeline_orchestration
} $false

Pause-Demo

Phase "DE-15" "Observability and Monitoring"

Run-PSFile "data_engineering\de15_observability_monitoring\collect_de15_observability.ps1" $true
Run-PSFile "data_engineering\de15_observability_monitoring\validate_de15_observability.ps1" $false

Run-Step "DE-15 Observability reports" {
    dir .\data_engineering\de15_observability_monitoring\results
    dir .\data_engineering\de15_observability_monitoring\reports
} $false

Pause-Demo

Phase "DE-16" "Data Governance"

Run-PSFile "data_engineering\de16_data_governance\generate_de16_data_governance.ps1" $true
Run-PSFile "data_engineering\de16_data_governance\validate_de16_data_governance.ps1" $false

Run-Step "DE-16 Governance artifacts" {
    dir .\data_engineering\de16_data_governance\catalog
    dir .\data_engineering\de16_data_governance\classification
    dir .\data_engineering\de16_data_governance\lineage
    dir .\data_engineering\de16_data_governance\policies
} $false

Pause-Demo

Phase "DE-17" "Power BI Analytics Layer"

Run-PSFile "data_engineering\de17_powerbi_analytics\run_de17_powerbi_analytics.ps1" $true
Run-PSFile "data_engineering\de17_powerbi_analytics\validate_de17_powerbi_analytics.ps1" $false

$RealSql = ".\data_engineering\de17_powerbi_analytics\real_semantic_layer\03_create_real_powerbi_views.sql"

if (Test-Path $RealSql) {
    Run-Step "DE-17 Recreate analytics_real semantic layer" {
        docker cp $RealSql ucp_sqlserver:/tmp/03_create_real_powerbi_views.sql
        docker exec ucp_sqlserver /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "ChangeMe_StrongPassword_2026!" -i /tmp/03_create_real_powerbi_views.sql
    } $false
}

SQL "DE-17 Power BI KPI overview" "charity_dwh" "
SELECT * FROM analytics_real.v_kpi_overview;
"

SQL "DE-17 Power BI analytics_real row counts" "charity_dwh" "
SELECT 'beneficiaries' table_name, COUNT_BIG(*) rows_count FROM analytics_real.v_dim_beneficiary
UNION ALL SELECT 'donors', COUNT_BIG(*) FROM analytics_real.v_dim_donor
UNION ALL SELECT 'applications', COUNT_BIG(*) FROM analytics_real.v_fact_applications
UNION ALL SELECT 'cases', COUNT_BIG(*) FROM analytics_real.v_fact_cases
UNION ALL SELECT 'donations', COUNT_BIG(*) FROM analytics_real.v_fact_donations
UNION ALL SELECT 'inventory_transactions', COUNT_BIG(*) FROM analytics_real.v_fact_inventory_transactions;
"

SQL "DE-17 Demo fraud summary if available" "charity_dwh" "
IF OBJECT_ID('analytics_real.v_demo_fraud_summary','V') IS NOT NULL
    SELECT * FROM analytics_real.v_demo_fraud_summary ORDER BY severity, alert_type;
ELSE
    SELECT 'analytics_real.v_demo_fraud_summary not found. Run with -SeedDemoData to create demo fraud views.' AS message;
"

SQL "DE-17 Demo fraud alerts sample if available" "charity_dwh" "
IF OBJECT_ID('analytics_real.v_demo_fraud_alerts','V') IS NOT NULL
    SELECT TOP 30 * FROM analytics_real.v_demo_fraud_alerts ORDER BY severity, alert_type;
ELSE
    SELECT 'analytics_real.v_demo_fraud_alerts not found. Run with -SeedDemoData to create demo fraud views.' AS message;
"

Phase "FINAL" "Demo Summary"

$script:Results | Export-Csv $CsvFile -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "FULL DEMO FINISHED" -ForegroundColor Green
Write-Host "Log file: $LogFile" -ForegroundColor Cyan
Write-Host "Status CSV: $CsvFile" -ForegroundColor Cyan

Write-Host ""
Write-Host "Useful demo URLs:" -ForegroundColor Yellow
Write-Host "Frontend:        http://localhost:5173"
Write-Host "Backend Docs:    http://localhost:8000/docs"
Write-Host "Airflow:         http://localhost:8088"
Write-Host "Spark Master:    http://localhost:18080"
Write-Host "Schema Registry: http://127.0.0.1:8081/subjects"
Write-Host "HDFS Namenode:   http://localhost:9871"

if ($OpenUrls) {
    Start-Process "http://localhost:5173"
    Start-Process "http://localhost:8000/docs"
    Start-Process "http://localhost:8088"
    Start-Process "http://localhost:18080"
    Start-Process "http://localhost:9871"
}

Write-Host ""
Write-Host "For Power BI demo: Refresh analytics_real views." -ForegroundColor Yellow
Write-Host "Important views:"
Write-Host "analytics_real.v_kpi_overview"
Write-Host "analytics_real.v_dim_organization"
Write-Host "analytics_real.v_dim_beneficiary"
Write-Host "analytics_real.v_dim_donor"
Write-Host "analytics_real.v_fact_applications"
Write-Host "analytics_real.v_fact_cases"
Write-Host "analytics_real.v_fact_donations"
Write-Host "analytics_real.v_fact_inventory_transactions"
Write-Host "analytics_real.v_demo_fraud_alerts"
Write-Host "analytics_real.v_demo_fraud_summary"





