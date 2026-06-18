import requests

BASE_URL = "http://localhost:8000"

endpoints = [
    "/api/reference/governorates",
    "/api/reference/cities",
    "/api/reference/organizations",
    "/api/reference/branches",
    "/api/reference/support-types",
    "/api/reference/payment-methods",
    "/api/reference/document-types",
    "/api/reference/inventory-items",
    "/api/reference/open-cases",
    "/api/reference/inventory-stock",
    "/api/reference/fraud-alerts",
    "/api/reference/audit-logs",
]

for endpoint in endpoints:
    response = requests.get(BASE_URL + endpoint, timeout=20)
    print(endpoint, response.status_code)
    if response.ok:
        data = response.json()
        print("  success:", data.get("success"), "| message:", data.get("message"))
    else:
        print("  error:", response.text[:300])
