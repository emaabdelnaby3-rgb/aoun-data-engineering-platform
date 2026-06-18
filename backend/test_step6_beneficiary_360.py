import requests

BASE_URL = "http://localhost:8000"

endpoints = [
    "/api/beneficiaries/search",
    "/api/beneficiaries/reports/cross-organization",
    "/api/beneficiaries/reports/duplicates",
]

for endpoint in endpoints:
    response = requests.get(BASE_URL + endpoint, timeout=30)
    print(endpoint, response.status_code)
    print(response.text[:500])

# Try first beneficiary 360
search = requests.get(BASE_URL + "/api/beneficiaries/search", timeout=30).json()
items = search.get("data", {}).get("beneficiaries", [])
if items:
    bid = items[0]["beneficiary_id"]
    response = requests.get(BASE_URL + f"/api/beneficiaries/360?beneficiary_id={bid}", timeout=30)
    print("/api/beneficiaries/360", response.status_code)
    print(response.text[:700])
else:
    print("No beneficiaries found to test 360.")
