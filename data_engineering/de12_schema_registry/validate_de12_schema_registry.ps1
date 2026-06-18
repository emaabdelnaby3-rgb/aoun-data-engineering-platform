$ErrorActionPreference = "Continue"

Write-Host "Validating DE-12 Schema Registry..."

$baseUrl = "http://127.0.0.1:8081"
$subject = "charity-cdc-event-envelope-value"

$containers = docker ps --format "{{.Names}}"

if ($containers -contains "ucp_schema_registry") {
    Write-Host "PASS: Schema Registry container is running"
} else {
    Write-Host "FAIL: Schema Registry container is not running"
}

$subjects = curl.exe -s "$baseUrl/subjects"

if ($subjects -match "\[") {
    Write-Host "PASS: Schema Registry API is reachable"
    Write-Host "Subjects: $subjects"
} else {
    Write-Host "FAIL: Schema Registry API is not reachable"
}

if ($subjects -match $subject) {
    Write-Host "PASS: $subject subject exists"
} else {
    Write-Host "FAIL: $subject subject is missing"
}

$latest = curl.exe -s "$baseUrl/subjects/$subject/versions/latest"

if ($latest -match '"version"' -and $latest -match '"id"') {
    Write-Host "PASS: Latest schema version is available"
    Write-Host $latest
} else {
    Write-Host "FAIL: Latest schema version is not available"
    Write-Host $latest
}
