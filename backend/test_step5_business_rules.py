import requests

BASE_URL = "http://localhost:8000"

# 1) general platform donation
payload = {
    "donor_name": "متبرع تجربة",
    "phone": "01033333333",
    "email": "donor@test.com",
    "amount": 250,
    "currency": "EGP",
    "payment_method_id": "1",
    "donation_target_type": "PLATFORM_GENERAL",
    "idempotency_key": "test-platform-general-001"
}
r = requests.post(BASE_URL + "/api/donations", json=payload, timeout=20)
print("platform general donation:", r.status_code, r.text[:500])

# 2) organization general donation
orgs = requests.get(BASE_URL + "/api/reference/organizations", timeout=20).json()["data"]["organizations"]
if orgs:
    payload["idempotency_key"] = "test-org-general-001"
    payload["donation_target_type"] = "ORGANIZATION_GENERAL"
    payload["organization_id"] = str(orgs[0]["organization_id"])
    r = requests.post(BASE_URL + "/api/donations", json=payload, timeout=20)
    print("organization general donation:", r.status_code, r.text[:500])

# 3) inventory IN transaction
items = requests.get(BASE_URL + "/api/reference/inventory-items", timeout=20).json()["data"]["inventory_items"]
branches = requests.get(BASE_URL + f"/api/reference/branches?organization_id={orgs[0]['organization_id']}", timeout=20).json()["data"]["branches"]

if orgs and items:
    inv = {
        "organization_id": str(orgs[0]["organization_id"]),
        "branch_id": str(branches[0]["branch_id"]) if branches else None,
        "item_id": str(items[0]["item_id"]),
        "transaction_type": "IN",
        "quantity": 10,
        "unit_cost": None,
        "reference_type": "MANUAL_ADJUSTMENT",
        "reference_id": None,
        "notes": "test stock in"
    }
    r = requests.post(BASE_URL + "/api/inventory-transactions", json=inv, timeout=20)
    print("inventory IN:", r.status_code, r.text[:500])
