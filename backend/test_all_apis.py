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
    "/api/beneficiaries/search",
    "/api/beneficiaries/reports/cross-organization",
    "/api/beneficiaries/reports/duplicates",
    "/api/beneficiaries/dashboard/summary",
]

for endpoint in endpoints:
    url = BASE_URL + endpoint
    try:
        response = requests.get(url, timeout=10)
        print(f"{endpoint} {response.status_code}")

        try:
            data = response.json()
            print("  success:", data.get("success"), "| message:", data.get("message"))
        except Exception:
            print("  response:", response.text[:300])

    except Exception as e:
        print(f"{endpoint} ERROR")
        print(" ", e)

print("Done.")
