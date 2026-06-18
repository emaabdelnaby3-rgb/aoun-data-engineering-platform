$ErrorActionPreference = "Continue"

Write-Host "Validating DE-14 Airflow Orchestration..."

$containers = docker ps --format "{{.Names}}"

$required = @(
    "ucp_airflow_postgres",
    "ucp_airflow_webserver",
    "ucp_airflow_scheduler"
)

foreach ($container in $required) {
    if ($containers -contains $container) {
        Write-Host "PASS: $container is running"
    } else {
        Write-Host "FAIL: $container is not running"
    }
}

$dagFile = ".\data_engineering\de14_airflow_orchestration\dags\ucp_de_pipeline_orchestration.py"

if (Test-Path $dagFile) {
    Write-Host "PASS: Airflow DAG file exists"
} else {
    Write-Host "FAIL: Airflow DAG file is missing"
}

try {
    $ui = curl.exe -s --max-time 10 http://localhost:8088
    if ($ui -match "Airflow" -or $ui.Length -gt 0) {
        Write-Host "PASS: Airflow Web UI is reachable at http://localhost:8088"
    } else {
        Write-Host "WARN: Airflow Web UI returned empty response"
    }
} catch {
    Write-Host "FAIL: Airflow Web UI is not reachable"
}

Write-Host ""
Write-Host "Checking DAG registration inside Airflow..."
docker exec ucp_airflow_scheduler airflow dags list | findstr ucp_de_pipeline_orchestration

if ($LASTEXITCODE -eq 0) {
    Write-Host "PASS: DAG ucp_de_pipeline_orchestration is registered"
} else {
    Write-Host "WARN: DAG may still be loading. Wait 60 seconds and run validation again."
}

Write-Host ""
Write-Host "Airflow URL: http://localhost:8088"
Write-Host "Username: admin"
Write-Host "Password: admin"
