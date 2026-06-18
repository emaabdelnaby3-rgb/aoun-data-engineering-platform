import requests

BASE_URL = "http://localhost:8000"

endpoints = [
    "/api/organizations",
    "/api/support-types",
    "/api/applications",
    "/api/cases",
    "/api/donations",
    "/api/documents",
    "/api/inventory-transactions",
    "/api/events/outbox",
    "/api/dashboard/government",
    "/api/dashboard/charity-network",
]

for endpoint in endpoints:
    url = BASE_URL + endpoint
    response = requests.get(url, timeout=20)
    print(endpoint, response.status_code)
    if response.ok:
        data = response.json()
        print("  success:", data.get("success"), "| message:", data.get("message"))
    else:
        print("  error:", response.text[:300])
