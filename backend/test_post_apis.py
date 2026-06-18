import json
import time
from typing import Any

import requests


BASE_URL = "http://localhost:8000"


def pretty(obj: Any) -> str:
    return json.dumps(obj, ensure_ascii=False, indent=2, default=str)


def print_result(name: str, response: requests.Response) -> dict:
    print(f"\n{name}")
    print("-" * len(name))
    print("status:", response.status_code)

    try:
        data = response.json()
        print(pretty(data)[:3000])
        return data
    except Exception:
        print(response.text[:3000])
        return {}


def post_json(endpoint: str, payload: dict, name: str) -> dict:
    response = requests.post(BASE_URL + endpoint, json=payload, timeout=30)
    return print_result(name, response)


def get_json(endpoint: str, name: str) -> dict:
    response = requests.get(BASE_URL + endpoint, timeout=30)
    return print_result(name, response)


def extract(data: dict, *paths, default=None):
    for path in paths:
        cur = data
        ok = True
        for key in path:
            if isinstance(cur, dict) and key in cur:
                cur = cur[key]
            else:
                ok = False
                break
        if ok and cur not in (None, ""):
            return cur
    return default


def main():
    suffix = str(int(time.time()))

    print("Unified Charity Platform — POST API smoke test")
    print("BASE_URL:", BASE_URL)

    application_payload = {
        "full_name": f"تجربة POST مستفيد {suffix}",
        "national_id": "29901011234567",
        "phone": "01012345678",
        "email": f"post.beneficiary.{suffix}@test.com",
        "gender": "Female",
        "birth_date": "1999-01-01",
        "governorate": "القاهرة",
        "city": "مدينة نصر",
        "address": "عنوان تجريبي من POST test",
        "family_size": 4,
        "monthly_income": 1200,
        "employment_status": "لا تعمل",
        "support_requested": "دعم طبي",
        "requested_amount": 5000,
        "priority_level": "HIGH",
        "notes": "POST smoke test application",
    }

    app_data = post_json(
        "/api/beneficiary-applications",
        application_payload,
        "1) POST /api/beneficiary-applications",
    )

    application_code = extract(
        app_data,
        ("data", "application_code"),
        ("data", "payload", "application_code"),
        ("data", "sql_result", "application_code"),
    )
    application_id = extract(
        app_data,
        ("data", "application_id"),
        ("data", "payload", "application_id"),
        ("data", "sql_result", "application_id"),
    )

    print("\nExtracted application_code:", application_code)
    print("Extracted application_id:", application_id)

    if not application_code and not application_id:
        print("\n❌ Could not extract application_code/application_id. Stop here.")
        return

    review_payload = {
        "decision": "APPROVED",
        "notes": "Approved from POST smoke test",
        "create_case": True,
        "required_amount": 5000,
        "priority_level": "HIGH",
        "case_title": f"حالة اختبار POST {suffix}",
        "case_description": "Case created from review endpoint by POST smoke test",
    }

    review_endpoint_candidates = []
    if application_code:
        review_endpoint_candidates.append(f"/api/beneficiary-applications/{application_code}/review")
    if application_id:
        review_endpoint_candidates.append(f"/api/beneficiary-applications/{application_id}/review")

    review_data = {}
    case_code = None
    case_id = None

    for endpoint in review_endpoint_candidates:
        response = requests.post(BASE_URL + endpoint, json=review_payload, timeout=30)
        data = print_result(f"2) POST {endpoint}", response)
        if response.status_code < 400:
            review_data = data
            case_code = extract(
                review_data,
                ("data", "created_case", "case_code"),
                ("data", "case_code"),
                ("data", "payload", "case_code"),
                ("data", "payload", "created_case", "case_code"),
                ("data", "sql_result", "created_case", "case_code"),
            )
            case_id = extract(
                review_data,
                ("data", "created_case", "case_id"),
                ("data", "case_id"),
                ("data", "payload", "case_id"),
                ("data", "payload", "created_case", "case_id"),
                ("data", "sql_result", "created_case", "case_id"),
            )
            break

    print("\nExtracted case_code from review:", case_code)
    print("Extracted case_id from review:", case_id)

    if not case_code and not case_id:
        case_payload = {
            "application_id": application_code or application_id,
            "application_code": application_code,
            "title": f"حالة اختبار POST مباشرة {suffix}",
            "description": "Direct case creation from POST smoke test",
            "required_amount": 5000,
            "priority_level": "HIGH",
        }
        case_data = post_json("/api/cases", case_payload, "3) POST /api/cases")
        case_code = extract(
            case_data,
            ("data", "case_code"),
            ("data", "payload", "case_code"),
            ("data", "sql_result", "case_code"),
        )
        case_id = extract(
            case_data,
            ("data", "case_id"),
            ("data", "payload", "case_id"),
            ("data", "sql_result", "case_id"),
        )
    else:
        print("\n✅ Review endpoint already created a case, so direct POST /api/cases is skipped to avoid duplicate cases.")

    print("\nFinal case_code:", case_code)
    print("Final case_id:", case_id)

    if case_code or case_id:
        donation_payload = {
            "donor_name": f"متبرع POST {suffix}",
            "phone": "01087654321",
            "email": f"post.donor.{suffix}@test.com",
            "amount": 500,
            "currency": "EGP",
            "payment_method_id": "1",
            "campaign_name": "POST smoke test campaign",
            "donation_target_type": "CASE",
            "case_id": str(case_code or case_id),
            "idempotency_key": f"POST-DON-CASE-{suffix}",
            "general_notes": "CASE donation from POST smoke test",
        }
        post_json("/api/donations", donation_payload, "4) POST /api/donations CASE")
    else:
        print("\n⚠️ Skipped CASE donation because no case was created.")

    platform_donation_payload = {
        "donor_name": f"متبرع عام POST {suffix}",
        "phone": "01088888888",
        "email": f"post.platform.donor.{suffix}@test.com",
        "amount": 250,
        "currency": "EGP",
        "payment_method_id": "1",
        "campaign_name": "تبرع عام POST",
        "donation_target_type": "PLATFORM_GENERAL",
        "idempotency_key": f"POST-DON-PLATFORM-{suffix}",
        "general_notes": "Platform general donation from POST smoke test",
    }
    post_json("/api/donations", platform_donation_payload, "5) POST /api/donations PLATFORM_GENERAL")

    inventory_in_payload = {
        "organization_id": "1",
        "branch_id": "1",
        "item_id": "1",
        "transaction_type": "IN",
        "quantity": 5,
        "unit_cost": 100,
        "reference_type": "MANUAL_ADJUSTMENT",
        "reference_id": f"POST-IN-{suffix}",
        "notes": "POST smoke test stock IN",
    }
    post_json("/api/inventory-transactions", inventory_in_payload, "6) POST /api/inventory-transactions IN")

    if case_code or case_id:
        inventory_out_payload = {
            "organization_id": "1",
            "branch_id": "1",
            "item_id": "1",
            "transaction_type": "OUT",
            "quantity": 1,
            "unit_cost": 100,
            "case_id": str(case_code or case_id),
            "reference_type": "CASE",
            "reference_id": str(case_code or case_id),
            "notes": "POST smoke test stock OUT linked to case",
        }
        post_json("/api/inventory-transactions", inventory_out_payload, "7) POST /api/inventory-transactions OUT")
    else:
        print("\n⚠️ Skipped inventory OUT because no case was created.")

    get_json("/api/events/outbox", "8) GET /api/events/outbox")
    get_json("/api/applications", "9) GET /api/applications after POST")
    get_json("/api/cases", "10) GET /api/cases after POST")
    get_json("/api/donations", "11) GET /api/donations after POST")
    get_json("/api/inventory-transactions", "12) GET /api/inventory-transactions after POST")

    print("\nDone.")


if __name__ == "__main__":
    main()
