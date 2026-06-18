$ErrorActionPreference = "Stop"

Write-Host "Registering DE-12 Schema Registry subject - fixed file payload version..."

$baseUrl = "http://127.0.0.1:8081"
$subject = "charity-cdc-event-envelope-value"
$folder = ".\data_engineering\de12_schema_registry"

New-Item -ItemType Directory -Force -Path $folder | Out-Null

Write-Host "Checking Schema Registry API..."
$subjectsBefore = curl.exe -s --max-time 10 "$baseUrl/subjects"
Write-Host "Subjects before: $subjectsBefore"

Write-Host "Setting compatibility..."

$compatibilityFile = "$folder\compatibility_payload.json"
$compatibilityPayload = '{"compatibility":"BACKWARD"}'
[System.IO.File]::WriteAllText($compatibilityFile, $compatibilityPayload, (New-Object System.Text.UTF8Encoding($false)))

curl.exe -s --max-time 10 -X PUT `
  -H "Content-Type: application/vnd.schemaregistry.v1+json" `
  --data-binary "@$compatibilityFile" `
  "$baseUrl/config/$subject"

Write-Host ""
Write-Host "Building valid Schema Registry payload..."

$schema = '{"type":"object","required":["payload"],"properties":{"payload":{"type":"object","required":["source","op"],"properties":{"source":{"type":"object"},"op":{"type":"string","enum":["c","u","d","r"]},"before":{"type":["object","null"]},"after":{"type":["object","null"]},"ts_ms":{"type":["integer","null"]}},"additionalProperties":true}},"additionalProperties":true}'

$escapedSchema = $schema.Replace('\', '\\').Replace('"', '\"')
$registerPayload = '{"schemaType":"JSON","schema":"' + $escapedSchema + '"}'

$registerFile = "$folder\register_payload_fixed.json"
[System.IO.File]::WriteAllText($registerFile, $registerPayload, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Payload file created:"
Write-Host $registerFile

Write-Host ""
Write-Host "Registering schema..."
$result = curl.exe -s --max-time 30 -X POST `
  -H "Content-Type: application/vnd.schemaregistry.v1+json" `
  --data-binary "@$registerFile" `
  "$baseUrl/subjects/$subject/versions"

Write-Host ""
Write-Host "Register result:"
Write-Host $result

Write-Host ""
Write-Host "Subjects after:"
curl.exe -s --max-time 10 "$baseUrl/subjects"

Write-Host ""
Write-Host "DE-12 schema registration completed."
