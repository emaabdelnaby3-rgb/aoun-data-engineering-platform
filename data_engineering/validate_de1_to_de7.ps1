$ErrorActionPreference = "Continue"

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$script:Results = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param(
        [string]$Area,
        [string]$Check,
        [string]$Status,
        [string]$Details
    )

    $script:Results.Add([pscustomobject]@{
        Area = $Area
        Check = $Check
        Status = $Status
        Details = $Details
    }) | Out-Null
}

function Test-ProjectFile {
    param(
        [string]$RelativePath,
        [string]$Area
    )

    $FullPath = Join-Path $ProjectRoot $RelativePath

    if (Test-Path $FullPath) {
        Add-Check $Area $RelativePath "PASS" "File exists"
    } else {
        Add-Check $Area $RelativePath "FAIL" "File missing"
    }
}

function Invoke-SqlDocker {
    param([string]$Query)

    $Output = docker exec ucp_sqlserver /opt/mssql-tools18/bin/sqlcmd `
        -C `
        -S localhost `
        -U sa `
        -P "ChangeMe_StrongPassword_2026!" `
        -W `
        -h -1 `
        -Q $Query 2>&1

    return @{
        ExitCode = $LASTEXITCODE
        Output = ($Output -join "`n")
    }
}

function Get-FirstNumber {
    param([string]$Text)

    $Match = [regex]::Match($Text, "\b\d+\b")
    if ($Match.Success) {
        return [int]$Match.Value
    }

    return -1
}

Write-Host "Validating Data Engineering setup DE-1 to DE-7..."

# Project-level files
Test-ProjectFile "data_engineering\de1_synthetic_data_generator\generate_synthetic_data.py" "Project Files"
Test-ProjectFile "data_engineering\de3_cdc\sql\01_enable_cdc_source_dbs.sql" "Project Files"
Test-ProjectFile "data_engineering\de4_kafka_debezium\docker-compose.presentation.snapshot.yml" "Project Files"
Test-ProjectFile "data_engineering\de5_debezium_connectors\food_bank_sqlserver_connector.json" "Project Files"
Test-ProjectFile "data_engineering\de5_debezium_connectors\resala_sqlserver_connector.json" "Project Files"
Test-ProjectFile "data_engineering\de5_debezium_connectors\haya_karima_sqlserver_connector.json" "Project Files"
Test-ProjectFile "data_engineering\de6_kafka_tests\kafka_test_commands.md" "Project Files"
Test-ProjectFile "data_engineering\de7_hdfs_data_lake\create_hdfs_folders.ps1" "Project Files"
Test-ProjectFile "data_engineering\de7_hdfs_data_lake\README_DE7_HDFS.md" "Project Files"

# Docker runtime
$RunningContainers = docker ps --format "{{.Names}}"

$RequiredContainers = @(
    "ucp_sqlserver",
    "ucp_minio",
    "ucp_zookeeper",
    "ucp_kafka",
    "ucp_debezium_connect"
)

foreach ($Container in $RequiredContainers) {
    if ($RunningContainers -contains $Container) {
        Add-Check "Docker Runtime" $Container "PASS" "Container is running"
    } else {
        Add-Check "Docker Runtime" $Container "FAIL" "Container is not running"
    }
}

$HdfsContainers = @(
    "ucp_hdfs_namenode",
    "ucp_hdfs_datanode"
)

foreach ($Container in $HdfsContainers) {
    if ($RunningContainers -contains $Container) {
        Add-Check "Docker Runtime" $Container "PASS" "HDFS container is running"
    } else {
        Add-Check "Docker Runtime" $Container "WARN" "HDFS not running yet. This is expected before DE-7."
    }
}

# SQL Server CDC validation using SA
$CdcDbQuery = "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.databases WHERE name IN ('charity_food_bank_operational','charity_resala_operational','charity_haya_karima_operational') AND is_cdc_enabled = 1;"
$CdcDbResult = Invoke-SqlDocker $CdcDbQuery
$CdcDbCount = Get-FirstNumber $CdcDbResult.Output

if ($CdcDbResult.ExitCode -eq 0 -and $CdcDbCount -eq 3) {
    Add-Check "SQL Server CDC" "CDC enabled on 3 source databases" "PASS" "CDC enabled databases count = $CdcDbCount"
} else {
    Add-Check "SQL Server CDC" "CDC enabled on 3 source databases" "FAIL" $CdcDbResult.Output
}

$CdcTablesQuery = "SET NOCOUNT ON; SELECT (SELECT COUNT(*) FROM charity_food_bank_operational.cdc.change_tables) + (SELECT COUNT(*) FROM charity_resala_operational.cdc.change_tables) + (SELECT COUNT(*) FROM charity_haya_karima_operational.cdc.change_tables);"
$CdcTablesResult = Invoke-SqlDocker $CdcTablesQuery
$CdcTablesCount = Get-FirstNumber $CdcTablesResult.Output

if ($CdcTablesResult.ExitCode -eq 0 -and $CdcTablesCount -ge 27) {
    Add-Check "SQL Server CDC" "CDC tables enabled" "PASS" "Enabled CDC tables count = $CdcTablesCount"
} else {
    Add-Check "SQL Server CDC" "CDC tables enabled" "FAIL" $CdcTablesResult.Output
}

# Debezium connector validation
$Connectors = @(
    "food_bank_sqlserver_connector",
    "resala_sqlserver_connector",
    "haya_karima_sqlserver_connector"
)

foreach ($Connector in $Connectors) {
    try {
        $Status = Invoke-RestMethod "http://localhost:8083/connectors/$Connector/status"
        $ConnectorState = $Status.connector.state
        $TaskStates = @($Status.tasks | ForEach-Object { $_.state })

        if ($ConnectorState -eq "RUNNING" -and ($TaskStates -contains "RUNNING")) {
            Add-Check "Debezium Connectors" $Connector "PASS" "Connector and task are RUNNING"
        } else {
            Add-Check "Debezium Connectors" $Connector "FAIL" ($Status | ConvertTo-Json -Depth 10)
        }
    } catch {
        Add-Check "Debezium Connectors" $Connector "FAIL" $_.Exception.Message
    }
}

# Kafka topics validation
$TopicsOutput = docker exec ucp_kafka kafka-topics --bootstrap-server kafka:29092 --list 2>&1

$ExpectedTopics = @(
    "food_bank.charity_food_bank_operational.dbo.source_event_outbox",
    "resala.charity_resala_operational.dbo.source_event_outbox",
    "haya_karima.charity_haya_karima_operational.dbo.source_event_outbox",
    "food_bank.charity_food_bank_operational.dbo.applications",
    "resala.charity_resala_operational.dbo.applications",
    "haya_karima.charity_haya_karima_operational.dbo.applications"
)

foreach ($Topic in $ExpectedTopics) {
    if ($TopicsOutput -contains $Topic) {
        Add-Check "Kafka Topics" $Topic "PASS" "Topic exists"
    } else {
        Add-Check "Kafka Topics" $Topic "FAIL" "Topic missing"
    }
}

# HDFS validation
if ($RunningContainers -contains "ucp_hdfs_namenode") {
    $HdfsFolders = @(
        "/charity_data_lake/bronze",
        "/charity_data_lake/silver",
        "/charity_data_lake/gold",
        "/charity_data_lake/bronze/kafka_events",
        "/charity_data_lake/silver/beneficiaries",
        "/charity_data_lake/gold/dimensions"
    )

    foreach ($Folder in $HdfsFolders) {
        docker exec ucp_hdfs_namenode hdfs dfs -test -d $Folder
        if ($LASTEXITCODE -eq 0) {
            Add-Check "HDFS Data Lake" $Folder "PASS" "Folder exists"
        } else {
            Add-Check "HDFS Data Lake" $Folder "FAIL" "Folder missing"
        }
    }
} else {
    Add-Check "HDFS Data Lake" "HDFS runtime validation" "WARN" "HDFS containers are not running yet. Run DE-7 first."
}

$script:Results | Sort-Object Area, Status, Check | Format-Table -AutoSize

$CsvPath = Join-Path $PSScriptRoot "de_validation_results.csv"
$script:Results | Export-Csv $CsvPath -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "Validation results saved to:"
Write-Host $CsvPath

$PassCount = ($script:Results | Where-Object { $_.Status -eq "PASS" }).Count
$WarnCount = ($script:Results | Where-Object { $_.Status -eq "WARN" }).Count
$FailCount = ($script:Results | Where-Object { $_.Status -eq "FAIL" }).Count

Write-Host ""
Write-Host "Summary:"
Write-Host "PASS: $PassCount"
Write-Host "WARN: $WarnCount"
Write-Host "FAIL: $FailCount"

if ($FailCount -gt 0) {
    exit 1
}

