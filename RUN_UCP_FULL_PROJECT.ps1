param(
    [switch]$SkipFrontendBackend,
    [switch]$SkipAirflowTrigger
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ProjectRoot

$LogDir = Join-Path $ProjectRoot "data_engineering\master_run_logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$RunId = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path $LogDir "ucp_full_project_run_$RunId.log"

Start-Transcript -Path $LogFile -Force | Out-Null

function Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "============================================================"
    Write-Host $Title
    Write-Host "============================================================"
}

function Run-Cmd {
    param(
        [string]$Title,
        [scriptblock]$Command,
        [switch]$AllowFail
    )

    Section $Title

    try {
        & $Command
        if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
            if ($AllowFail) {
                Write-Host "WARN: $Title finished with exit code $LASTEXITCODE"
            } else {
                throw "$Title failed with exit code $LASTEXITCODE"
            }
        }
        Write-Host "PASS: $Title"
    } catch {
        if ($AllowFail) {
            Write-Host "WARN: $Title failed but continuing..."
            Write-Host $_
        } else {
            Write-Host "FAIL: $Title"
            Write-Host $_
            Stop-Transcript | Out-Null
            exit 1
        }
    }
}

function Run-PSFile {
    param(
        [string]$Title,
        [string]$Path,
        [switch]$AllowMissing,
        [switch]$AllowFail
    )

    if (Test-Path $Path) {
        Run-Cmd $Title {
            powershell -ExecutionPolicy Bypass -File $Path
        } -AllowFail:$AllowFail
    } else {
        if ($AllowMissing) {
            Write-Host "WARN: Missing optional file: $Path"
        } else {
            throw "Required file missing: $Path"
        }
    }
}

Section "UCP FULL PROJECT MASTER RUN"
Write-Host "Project root: $ProjectRoot"
Write-Host "Run ID: $RunId"
Write-Host "Log file: $LogFile"

Run-Cmd "Preflight: Docker is available" {
    docker --version
}

Run-Cmd "Preflight: Docker containers before start" {
    docker ps
} -AllowFail

Run-Cmd "Start core Docker infrastructure" {
    Push-Location ".\infra"
    docker compose -f .\docker-compose.presentation.yml up -d
    Pop-Location
}

Start-Sleep -Seconds 20

Run-Cmd "Start Airflow services" {
    Push-Location ".\infra"
    docker compose -f .\docker-compose.airflow.yml up -d airflow-postgres
    docker compose -f .\docker-compose.airflow.yml up airflow-init
    docker compose -f .\docker-compose.airflow.yml up -d airflow-webserver airflow-scheduler
    Pop-Location
}

Start-Sleep -Seconds 20

Run-Cmd "Check required Docker containers" {
    docker ps --format "{{.Names}}"

    $required = @(
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

    $running = docker ps --format "{{.Names}}"

    foreach ($c in $required) {
        if ($running -contains $c) {
            Write-Host "PASS: $c running"
        } else {
            throw "$c is not running"
        }
    }
}

if (-not $SkipFrontendBackend) {
    Run-Cmd "Start Backend API in new PowerShell window" {
        $backendPath = Join-Path $ProjectRoot "backend"
        Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$backendPath'; uvicorn app.main:app --reload"
    } -AllowFail

    Run-Cmd "Start Frontend React app in new PowerShell window" {
        $frontendPath = Join-Path $ProjectRoot "frontend"
        Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$frontendPath'; npm run dev"
    } -AllowFail

    Start-Sleep -Seconds 10
}

Run-PSFile "DE-7 Create HDFS Data Lake folders" ".\data_engineering\de7_hdfs_data_lake\create_hdfs_folders.ps1" -AllowMissing -AllowFail

Run-PSFile "DE-1 to DE-7 Validation" ".\data_engineering\validate_de1_to_de7.ps1"

Run-PSFile "DE-8 Kafka/Debezium to Bronze" ".\data_engineering\de8_spark_bronze\run_de8_spark_bronze.ps1"
Run-PSFile "DE-8 Validation" ".\data_engineering\de8_spark_bronze\validate_de8_bronze.ps1"

Run-PSFile "DE-9 Bronze to Silver" ".\data_engineering\de9_spark_silver\run_de9_spark_silver.ps1"
Run-PSFile "DE-9 Validation" ".\data_engineering\de9_spark_silver\validate_de9_silver.ps1"

Run-PSFile "DE-10 Silver to Gold" ".\data_engineering\de10_spark_gold\run_de10_spark_gold.ps1"
Run-PSFile "DE-10 Validation" ".\data_engineering\de10_spark_gold\validate_de10_gold.ps1"

Run-PSFile "DE-11 Gold to SQL Server DWH" ".\data_engineering\de11_gold_to_dwh\run_de11_gold_to_dwh.ps1"
Run-PSFile "DE-11 Validation" ".\data_engineering\de11_gold_to_dwh\validate_de11_gold_to_dwh.ps1"

Run-PSFile "DE-12 Schema Registry Register Subject" ".\data_engineering\de12_schema_registry\register_schema_registry_subjects.ps1"
Run-PSFile "DE-12 Validation" ".\data_engineering\de12_schema_registry\validate_de12_schema_registry.ps1"

Run-PSFile "DE-13 Data Quality Checks" ".\data_engineering\de13_data_quality\run_de13_data_quality.ps1"
Run-PSFile "DE-13 Validation" ".\data_engineering\de13_data_quality\validate_de13_data_quality.ps1"

Run-PSFile "DE-14 Airflow Validation" ".\data_engineering\de14_airflow_orchestration\validate_de14_airflow.ps1"

if (-not $SkipAirflowTrigger) {
    Run-Cmd "DE-14 Trigger Airflow DAG" {
        docker exec ucp_airflow_scheduler airflow dags trigger ucp_de_pipeline_orchestration
        Start-Sleep -Seconds 15
        docker exec ucp_airflow_scheduler airflow dags list-runs -d ucp_de_pipeline_orchestration
    } -AllowFail
}

Run-PSFile "DE-15 Observability Collector" ".\data_engineering\de15_observability_monitoring\collect_de15_observability.ps1"
Run-PSFile "DE-15 Validation" ".\data_engineering\de15_observability_monitoring\validate_de15_observability.ps1"

Run-PSFile "DE-16 Data Governance Generator" ".\data_engineering\de16_data_governance\generate_de16_data_governance.ps1"
Run-PSFile "DE-16 Validation" ".\data_engineering\de16_data_governance\validate_de16_data_governance.ps1"

Run-PSFile "DE-17 Power BI Analytics Views" ".\data_engineering\de17_powerbi_analytics\run_de17_powerbi_analytics.ps1"
Run-PSFile "DE-17 Validation" ".\data_engineering\de17_powerbi_analytics\validate_de17_powerbi_analytics.ps1"

Section "FINAL PROJECT HEALTH CHECK"

Run-Cmd "Backend health check" {
    curl.exe -s --max-time 10 http://127.0.0.1:8000/docs | Out-Null
    Write-Host "Backend docs reachable: http://127.0.0.1:8000/docs"
} -AllowFail

Run-Cmd "Frontend health check" {
    curl.exe -s --max-time 10 http://127.0.0.1:5173 | Out-Null
    Write-Host "Frontend reachable: http://127.0.0.1:5173"
} -AllowFail

Run-Cmd "Airflow health check" {
    curl.exe -s --max-time 10 http://127.0.0.1:8088/health
}

Run-Cmd "Schema Registry health check" {
    curl.exe -s --max-time 10 http://127.0.0.1:8081/subjects
}

Section "UCP FULL PROJECT RUN COMPLETED SUCCESSFULLY"

Write-Host "Frontend: http://localhost:5173"
Write-Host "Backend API Docs: http://localhost:8000/docs"
Write-Host "Airflow: http://localhost:8088"
Write-Host "Airflow username: admin"
Write-Host "Airflow password: admin"
Write-Host "Schema Registry: http://localhost:8081/subjects"
Write-Host "Spark UI: http://localhost:18080"
Write-Host "HDFS UI: http://localhost:9871"
Write-Host "Power BI SQL Server: localhost,1433"
Write-Host "Power BI Database: charity_dwh"
Write-Host "Power BI Schema: analytics"
Write-Host "Log file: $LogFile"

Stop-Transcript | Out-Null
exit 0
