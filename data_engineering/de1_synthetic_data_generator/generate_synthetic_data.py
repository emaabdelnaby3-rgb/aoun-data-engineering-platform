"""
DE-1 Synthetic Charity Data Generator
Unified Charity Platform

Purpose
-------
Generate realistic synthetic operational source data for 3 simulated charity
systems before starting CDC/Debezium/Kafka.

Outputs
-------
1) CSV files for each source DB under output/csv/<db_name>/
2) One SQL load script: output/01_load_synthetic_source_data.sql

The SQL script loads the 3 operational source databases:
- charity_food_bank_operational
- charity_resala_operational
- charity_haya_karima_operational

Run example
-----------
python generate_synthetic_data.py --beneficiaries-per-org 1000 --months 12 --output-dir output

Then run this file in SSMS on master:
output/01_load_synthetic_source_data.sql
"""

from __future__ import annotations

import argparse
import csv
import json
import random
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, date
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple


ORGS = [
    {
        "code": "FOOD_BANK",
        "db": "charity_food_bank_operational",
        "prefix": "FB",
        "name": "Food Bank System",
        "branch_prefix_ar": "فرع بنك الطعام",
    },
    {
        "code": "RESALA",
        "db": "charity_resala_operational",
        "prefix": "RES",
        "name": "Resala System",
        "branch_prefix_ar": "فرع رسالة",
    },
    {
        "code": "HAYA_KARIMA",
        "db": "charity_haya_karima_operational",
        "prefix": "HK",
        "name": "Haya Karima System",
        "branch_prefix_ar": "فرع حياة كريمة",
    },
]

GOVERNORATES_CITIES = {
    "Cairo": ["Nasr City", "Helwan", "Maadi", "Shubra", "New Cairo"],
    "Giza": ["Dokki", "Haram", "Faisal", "October", "Sheikh Zayed"],
    "Alexandria": ["Sidi Gaber", "Miami", "Borg El Arab", "Mandara"],
    "Dakahlia": ["Mansoura", "Talkha", "Mit Ghamr"],
    "Sharqia": ["Zagazig", "Belbeis", "10th Ramadan"],
    "Qalyubia": ["Banha", "Shubra El Kheima", "Qalyub"],
    "Gharbia": ["Tanta", "Mahalla", "Kafr El Zayat"],
    "Monufia": ["Shebin El Kom", "Menouf", "Ashmoun"],
    "Minya": ["Minya", "Mallawi", "Samalut"],
    "Assiut": ["Assiut", "Dairut", "Abnoub"],
    "Sohag": ["Sohag", "Tahta", "Gerga"],
    "Aswan": ["Aswan", "Kom Ombo", "Edfu"],
}

FIRST_NAMES_MALE = [
    "Ahmed", "Mohamed", "Mahmoud", "Omar", "Youssef", "Mostafa", "Hassan", "Ali", "Khaled", "Karim",
    "Tarek", "Amr", "Hany", "Sameh", "Ibrahim", "Mina", "Fady", "Sherif", "Islam", "Ayman",
]
FIRST_NAMES_FEMALE = [
    "Fatma", "Mariam", "Sara", "Nour", "Aya", "Hana", "Rana", "Doaa", "Dina", "Yasmin",
    "Reem", "Mai", "Nada", "Laila", "Salma", "Nermin", "Mona", "Eman", "Heba", "Esraa",
]
LAST_NAMES = [
    "Ali", "Hassan", "Ibrahim", "Mahmoud", "Saleh", "Farouk", "Sayed", "Abdelrahman", "Kamal", "Fathy",
    "Gaber", "Mostafa", "Samir", "Younis", "Nour", "Mansour", "Abdallah", "Rashad", "Zaki", "Fouad",
]

SUPPORT_TYPES = [
    "Food Support", "Medical Support", "Monthly Cash Support", "Education Support", "Housing Support",
    "Debt Relief", "Winter Blanket", "Ramadan Box", "Orphan Support", "Emergency Aid",
]
APPLICATION_STATUSES = ["SUBMITTED", "UNDER_REVIEW", "APPROVED", "REJECTED", "MISSING_DOCUMENTS"]
CASE_STATUSES = ["OPEN", "PUBLISHED", "FUNDED", "CLOSED"]
PAYMENT_METHODS = ["Cash", "Visa", "Bank Transfer", "Fawry", "Vodafone Cash"]
EMPLOYMENT_STATUSES = ["Unemployed", "Daily Worker", "Part Time", "Retired", "Housewife", "Unable to Work"]
DOCUMENT_TYPES = ["National ID", "Income Proof", "Medical Report", "Family Certificate", "Rent Contract"]
INVENTORY_ITEMS = [
    ("RICE", "Rice Bag", "Food", "kg", 35),
    ("OIL", "Oil Bottle", "Food", "bottle", 70),
    ("SUGAR", "Sugar Bag", "Food", "kg", 32),
    ("BLANKET", "Winter Blanket", "Clothes", "piece", 180),
    ("MED_BOX", "Medical Box", "Medical", "box", 250),
    ("SCHOOL_BAG", "School Bag", "Education", "piece", 300),
]


def sql_str(value: Any) -> str:
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, datetime):
        return "N'" + value.isoformat(sep=" ")[:19].replace("'", "''") + "'"
    if isinstance(value, date):
        return "N'" + value.isoformat().replace("'", "''") + "'"
    s = str(value).replace("'", "''")
    return "N'" + s + "'"


def rand_date(months_back: int) -> datetime:
    days_back = random.randint(0, months_back * 30)
    seconds = random.randint(0, 86400)
    return datetime.now() - timedelta(days=days_back, seconds=seconds)


def random_phone(valid: bool = True) -> str:
    if valid:
        prefix = random.choice(["010", "011", "012", "015"])
        return prefix + "".join(str(random.randint(0, 9)) for _ in range(8))
    return random.choice(["12345", "0200000000", "01ABCDEF", "999999999"])


def random_national_id(valid: bool = True) -> str:
    if not valid:
        return random.choice([
            "".join(str(random.randint(0, 9)) for _ in range(12)),
            "".join(str(random.randint(0, 9)) for _ in range(15)),
            "29A0101123456",
        ])
    century = random.choice(["2", "3"])
    yy = random.randint(55, 99) if century == "2" else random.randint(0, 7)
    mm = random.randint(1, 12)
    dd = random.randint(1, 28)
    gov = random.randint(1, 27)
    serial = random.randint(10000, 99999)
    return f"{century}{yy:02d}{mm:02d}{dd:02d}{gov:02d}{serial:05d}"


def full_name(gender: str) -> str:
    first = random.choice(FIRST_NAMES_FEMALE if gender == "Female" else FIRST_NAMES_MALE)
    return f"{first} {random.choice(LAST_NAMES)} {random.choice(LAST_NAMES)}"


def write_csv(path: Path, rows: List[Dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def insert_sql(table: str, rows: List[Dict[str, Any]], identity_col: Optional[str] = None) -> str:
    if not rows:
        return ""
    cols = list(rows[0].keys())
    lines = []
    if identity_col and identity_col in cols:
        lines.append(f"SET IDENTITY_INSERT {table} ON;")
    # Use one INSERT per row for readability and compatibility.
    for r in rows:
        values = ", ".join(sql_str(r.get(c)) for c in cols)
        lines.append(f"INSERT INTO {table} ({', '.join(cols)}) VALUES ({values});")
    if identity_col and identity_col in cols:
        lines.append(f"SET IDENTITY_INSERT {table} OFF;")
    return "\n".join(lines)


@dataclass
class OrgData:
    branches: List[Dict[str, Any]]
    staff_users: List[Dict[str, Any]]
    beneficiaries: List[Dict[str, Any]]
    applications: List[Dict[str, Any]]
    cases: List[Dict[str, Any]]
    donors: List[Dict[str, Any]]
    donations: List[Dict[str, Any]]
    inventory_items: List[Dict[str, Any]]
    inventory_transactions: List[Dict[str, Any]]
    beneficiary_documents: List[Dict[str, Any]]
    source_event_outbox: List[Dict[str, Any]]


def generate_for_org(org: Dict[str, str], n: int, months: int, duplicate_ids: List[str], dirty_ratio: float) -> OrgData:
    prefix = org["prefix"]
    branches: List[Dict[str, Any]] = []
    staff_users: List[Dict[str, Any]] = []
    beneficiaries: List[Dict[str, Any]] = []
    applications: List[Dict[str, Any]] = []
    cases: List[Dict[str, Any]] = []
    donors: List[Dict[str, Any]] = []
    donations: List[Dict[str, Any]] = []
    inventory_items: List[Dict[str, Any]] = []
    inventory_transactions: List[Dict[str, Any]] = []
    beneficiary_documents: List[Dict[str, Any]] = []
    outbox: List[Dict[str, Any]] = []

    govs = list(GOVERNORATES_CITIES.keys())
    selected_govs = random.sample(govs, min(6, len(govs)))

    for i in range(1, 7):
        gov = selected_govs[i - 1]
        city = random.choice(GOVERNORATES_CITIES[gov])
        branches.append({
            "source_branch_id": i,
            "branch_code": f"{prefix}-BR-{i:03d}",
            "branch_name": f"{org['branch_prefix_ar']} {city}",
            "governorate_name": gov,
            "city_name": city,
            "address": f"{random.randint(1, 99)} Main Street, {city}",
            "phone": random_phone(True),
            "is_active": 1,
            "created_at": rand_date(months),
            "updated_at": None,
        })

    staff_id = 1
    for b in branches:
        for _ in range(2):
            staff_users.append({
                "source_user_id": staff_id,
                "user_code": f"{prefix}-USR-{staff_id:04d}",
                "source_branch_id": b["source_branch_id"],
                "full_name": full_name(random.choice(["Male", "Female"])),
                "email": f"staff{staff_id}.{prefix.lower()}@example.com",
                "phone": random_phone(True),
                "role_code": random.choice(["CHARITY_STAFF", "CHARITY_ADMIN", "CASE_REVIEWER"]),
                "is_active": 1,
                "created_at": rand_date(months),
                "updated_at": None,
            })
            staff_id += 1

    for item_id, (code, name, category, unit, cost) in enumerate(INVENTORY_ITEMS, start=1):
        inventory_items.append({
            "source_item_id": item_id,
            "item_code": f"{prefix}-{code}",
            "item_name": name,
            "item_category": category,
            "unit": unit,
            "default_unit_cost": cost,
            "is_active": 1,
            "updated_at": None,
        })

    duplicate_count = max(1, int(n * 0.06))
    org_duplicate_ids = random.sample(duplicate_ids, min(duplicate_count, len(duplicate_ids)))

    for i in range(1, n + 1):
        gender = random.choice(["Male", "Female"])
        gov = random.choice(selected_govs)
        city = random.choice(GOVERNORATES_CITIES[gov])
        is_dirty = random.random() < dirty_ratio
        nid = org_duplicate_ids[i - 1] if i <= len(org_duplicate_ids) else random_national_id(valid=not is_dirty)
        bdate_year = random.randint(1955, 2005)
        beneficiaries.append({
            "source_beneficiary_id": i,
            "national_id": nid,
            "full_name": full_name(gender),
            "gender": gender,
            "birth_date": date(bdate_year, random.randint(1, 12), random.randint(1, 28)),
            "phone": random_phone(valid=not is_dirty),
            "email": None if random.random() < 0.8 else f"beneficiary{i}.{prefix.lower()}@example.com",
            "governorate_name": gov,
            "city_name": city,
            "address": f"{random.randint(1, 120)} {random.choice(['Nile', 'Tahrir', 'School', 'Market'])} Street",
            "family_size": random.choices([1, 2, 3, 4, 5, 6, 7, 8], weights=[5, 10, 15, 18, 18, 14, 10, 10])[0],
            "monthly_income": random.choice([0, 500, 800, 1200, 1800, 2500, 3500, 4500]),
            "employment_status": random.choice(EMPLOYMENT_STATUSES),
            "created_at": rand_date(months),
            "updated_at": None,
        })

    application_id = 1
    case_id = 1
    document_id = 1
    for b in beneficiaries:
        app_count = random.choices([1, 2, 3], weights=[70, 25, 5])[0]
        for _ in range(app_count):
            support = random.choice(SUPPORT_TYPES)
            requested = random.choice([800, 1200, 2000, 3500, 5000, 8000, 12000])
            status = random.choices(APPLICATION_STATUSES, weights=[20, 20, 38, 15, 7])[0]
            submitted = rand_date(months)
            branch_id = random.choice(branches)["source_branch_id"]
            priority = "CRITICAL" if requested >= 8000 or b["family_size"] >= 7 else random.choice(["LOW", "MEDIUM", "HIGH"])
            applications.append({
                "source_application_id": application_id,
                "application_code": f"{prefix}-APP-{application_id:06d}",
                "source_beneficiary_id": b["source_beneficiary_id"],
                "source_branch_id": branch_id,
                "support_type_name": support,
                "requested_amount": requested,
                "application_status": status,
                "priority_level": priority,
                "submitted_at": submitted,
                "reviewed_at": submitted + timedelta(days=random.randint(1, 14)) if status in ["APPROVED", "REJECTED"] else None,
                "staff_notes": random.choice([None, "Needs home visit", "Documents pending", "Urgent family support", "Verified by branch"]),
                "updated_at": None,
            })
            outbox.append(event(prefix, "APPLICATION_CREATED", "applications", application_id, applications[-1]))

            # Documents for each application
            for doc_type in random.sample(DOCUMENT_TYPES, random.randint(1, 3)):
                beneficiary_documents.append({
                    "source_document_id": document_id,
                    "source_beneficiary_id": b["source_beneficiary_id"],
                    "source_application_id": application_id,
                    "document_type_name": doc_type,
                    "file_name": f"{prefix.lower()}_{b['source_beneficiary_id']}_{document_id}.pdf",
                    "object_store_key": f"source-documents/{prefix}/{b['source_beneficiary_id']}/{document_id}.pdf",
                    "file_url": f"minio://charity-documents/source-documents/{prefix}/{b['source_beneficiary_id']}/{document_id}.pdf",
                    "verification_status": random.choice(["PENDING", "VERIFIED", "REJECTED"]),
                    "uploaded_at": submitted + timedelta(hours=random.randint(1, 48)),
                    "updated_at": None,
                })
                outbox.append(event(prefix, "DOCUMENT_UPLOADED", "beneficiary_documents", document_id, beneficiary_documents[-1]))
                document_id += 1

            if status == "APPROVED" and random.random() < 0.75:
                target = requested
                collected = round(random.uniform(0, target), 2)
                case_status = "FUNDED" if collected >= target * 0.95 else random.choice(["OPEN", "PUBLISHED"])
                if case_status == "FUNDED":
                    collected = target
                cases.append({
                    "source_case_id": case_id,
                    "case_code": f"{prefix}-CASE-{case_id:06d}",
                    "source_application_id": application_id,
                    "source_beneficiary_id": b["source_beneficiary_id"],
                    "source_branch_id": branch_id,
                    "case_title": f"{support} case for beneficiary {b['source_beneficiary_id']}",
                    "support_type_name": support,
                    "case_status": case_status,
                    "target_amount": target,
                    "collected_amount": collected,
                    "opened_at": submitted + timedelta(days=random.randint(1, 5)),
                    "closed_at": submitted + timedelta(days=random.randint(6, 40)) if case_status in ["FUNDED", "CLOSED"] else None,
                    "updated_at": None,
                })
                outbox.append(event(prefix, "CASE_CREATED", "cases", case_id, cases[-1]))
                case_id += 1
            application_id += 1

    donor_count = max(50, int(n * 0.35))
    for i in range(1, donor_count + 1):
        donors.append({
            "source_donor_id": i,
            "donor_code": f"{prefix}-DONOR-{i:06d}",
            "donor_name": full_name(random.choice(["Male", "Female"])),
            "phone": random_phone(True),
            "email": None if random.random() < 0.4 else f"donor{i}.{prefix.lower()}@example.com",
            "donor_category": random.choice(["Individual", "Corporate", "Monthly Donor", "Anonymous"]),
            "created_at": rand_date(months),
            "updated_at": None,
        })

    donation_id = 1
    open_cases = [c for c in cases if c["case_status"] in ["OPEN", "PUBLISHED", "FUNDED"]]
    donation_count = max(100, int(len(open_cases) * 2.2)) if open_cases else 0
    for _ in range(donation_count):
        c = random.choice(open_cases)
        donor = random.choice(donors)
        donated_at = c["opened_at"] + timedelta(days=random.randint(0, 60), hours=random.randint(0, 23))
        donations.append({
            "source_donation_id": donation_id,
            "donation_code": f"{prefix}-DON-{donation_id:08d}",
            "source_donor_id": donor["source_donor_id"],
            "source_case_id": c["source_case_id"],
            "source_branch_id": c["source_branch_id"],
            "amount": random.choice([100, 150, 200, 250, 500, 750, 1000, 1500, 2000]),
            "payment_method_name": random.choice(PAYMENT_METHODS),
            "donation_status": random.choice(["COMPLETED", "COMPLETED", "COMPLETED", "REFUNDED"]),
            "donated_at": donated_at,
            "notes": None,
            "updated_at": None,
        })
        outbox.append(event(prefix, "DONATION_CREATED", "donations", donation_id, donations[-1]))
        donation_id += 1

    inv_id = 1
    for c in random.sample(cases, min(len(cases), max(30, int(len(cases) * 0.45)))):
        item = random.choice(inventory_items)
        qty = random.randint(1, 5)
        inventory_transactions.append({
            "source_inventory_transaction_id": inv_id,
            "transaction_code": f"{prefix}-INV-{inv_id:08d}",
            "source_branch_id": c["source_branch_id"],
            "source_item_id": item["source_item_id"],
            "source_case_id": c["source_case_id"],
            "transaction_type": random.choice(["OUT", "OUT", "IN"]),
            "quantity": qty,
            "unit_cost": item["default_unit_cost"],
            "transaction_date": c["opened_at"] + timedelta(days=random.randint(0, 20)),
            "notes": None,
            "updated_at": None,
        })
        outbox.append(event(prefix, "INVENTORY_TRANSACTION_CREATED", "inventory_transactions", inv_id, inventory_transactions[-1]))
        inv_id += 1

    return OrgData(branches, staff_users, beneficiaries, applications, cases, donors, donations, inventory_items, inventory_transactions, beneficiary_documents, outbox)


def event(prefix: str, event_type: str, entity_name: str, entity_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
    # Keep payload compact and JSON serializable.
    payload2 = {}
    for k, v in payload.items():
        if isinstance(v, (datetime, date)):
            payload2[k] = v.isoformat()
        else:
            payload2[k] = v
    return {
        "source_event_id": 0,  # filled later
        "event_uuid": str(uuid.uuid4()),
        "event_type": event_type,
        "entity_name": entity_name,
        "entity_id": str(entity_id),
        "payload_json": json.dumps({"source": prefix, "payload": payload2}, ensure_ascii=False),
        "event_status": "PENDING",
        "created_at": datetime.now() - timedelta(minutes=random.randint(0, 50000)),
        "published_at": None,
    }


def write_org_csv(base: Path, org: Dict[str, str], data: OrgData) -> None:
    db_dir = base / "csv" / org["db"]
    for name, rows in data.__dict__.items():
        write_csv(db_dir / f"{name}.csv", rows)


def assign_outbox_ids(data: OrgData) -> None:
    for i, e in enumerate(data.source_event_outbox, start=1):
        e["source_event_id"] = i


def build_sql_for_org(org: Dict[str, str], data: OrgData) -> str:
    db = org["db"]
    chunks = [
        f"\n/* ===================== LOAD {org['code']} SOURCE DATA ===================== */",
        f"USE {db};",
        "GO",
        "DELETE FROM dbo.source_event_outbox;",
        "DELETE FROM dbo.beneficiary_documents;",
        "DELETE FROM dbo.inventory_transactions;",
        "DELETE FROM dbo.donations;",
        "DELETE FROM dbo.donors;",
        "DELETE FROM dbo.cases;",
        "DELETE FROM dbo.applications;",
        "DELETE FROM dbo.beneficiaries;",
        "DELETE FROM dbo.staff_users;",
        "DELETE FROM dbo.inventory_items;",
        "DELETE FROM dbo.branches;",
        "GO",
        "DBCC CHECKIDENT ('dbo.branches', RESEED, 0);",
        "DBCC CHECKIDENT ('dbo.staff_users', RESEED, 0);",
        "DBCC CHECKIDENT ('dbo.beneficiaries', RESEED, 0);",
        "DBCC CHECKIDENT ('dbo.applications', RESEED, 0);",
        "DBCC CHECKIDENT ('dbo.cases', RESEED, 0);",
        "DBCC CHECKIDENT ('dbo.donors', RESEED, 0);",
        "DBCC CHECKIDENT ('dbo.donations', RESEED, 0);",
        "DBCC CHECKIDENT ('dbo.inventory_items', RESEED, 0);",
        "DBCC CHECKIDENT ('dbo.inventory_transactions', RESEED, 0);",
        "DBCC CHECKIDENT ('dbo.beneficiary_documents', RESEED, 0);",
        "DBCC CHECKIDENT ('dbo.source_event_outbox', RESEED, 0);",
        "GO",
        insert_sql("dbo.branches", data.branches, "source_branch_id"),
        "GO",
        insert_sql("dbo.staff_users", data.staff_users, "source_user_id"),
        "GO",
        insert_sql("dbo.beneficiaries", data.beneficiaries, "source_beneficiary_id"),
        "GO",
        insert_sql("dbo.inventory_items", data.inventory_items, "source_item_id"),
        "GO",
        insert_sql("dbo.applications", data.applications, "source_application_id"),
        "GO",
        insert_sql("dbo.cases", data.cases, "source_case_id"),
        "GO",
        insert_sql("dbo.donors", data.donors, "source_donor_id"),
        "GO",
        insert_sql("dbo.donations", data.donations, "source_donation_id"),
        "GO",
        insert_sql("dbo.inventory_transactions", data.inventory_transactions, "source_inventory_transaction_id"),
        "GO",
        insert_sql("dbo.beneficiary_documents", data.beneficiary_documents, "source_document_id"),
        "GO",
        insert_sql("dbo.source_event_outbox", data.source_event_outbox, "source_event_id"),
        "GO",
        f"PRINT 'Loaded synthetic data into {db}';",
        "GO",
    ]
    return "\n".join(chunks)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate synthetic charity operational source data.")
    parser.add_argument("--beneficiaries-per-org", type=int, default=500, help="Number of beneficiaries per charity DB.")
    parser.add_argument("--months", type=int, default=12, help="Historical range in months.")
    parser.add_argument("--dirty-ratio", type=float, default=0.035, help="Ratio of deliberately dirty rows for data quality tests.")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--output-dir", type=Path, default=Path("output"))
    args = parser.parse_args()

    if args.beneficiaries_per_org < 20:
        raise ValueError("Use at least 20 beneficiaries per org to generate meaningful relationships.")

    random.seed(args.seed)
    args.output_dir.mkdir(parents=True, exist_ok=True)

    # Duplicates shared across orgs for cross-organization fraud/beneficiary 360 scenarios.
    duplicate_pool = [random_national_id(True) for _ in range(max(30, int(args.beneficiaries_per_org * 0.1)))]

    sql_parts = [
        "/*",
        "DE-1 Synthetic Charity Data Load Script",
        "Run on: master",
        "Generated by data_engineering/de1_synthetic_data_generator/generate_synthetic_data.py",
        "*/",
        "SET NOCOUNT ON;",
        "GO",
    ]

    summary = []
    for org in ORGS:
        data = generate_for_org(org, args.beneficiaries_per_org, args.months, duplicate_pool, args.dirty_ratio)
        assign_outbox_ids(data)
        write_org_csv(args.output_dir, org, data)
        sql_parts.append(build_sql_for_org(org, data))
        summary.append({
            "source_db": org["db"],
            "beneficiaries": len(data.beneficiaries),
            "applications": len(data.applications),
            "cases": len(data.cases),
            "donors": len(data.donors),
            "donations": len(data.donations),
            "inventory_transactions": len(data.inventory_transactions),
            "documents": len(data.beneficiary_documents),
            "outbox_events": len(data.source_event_outbox),
        })

    sql_parts.append("\n/* ===================== FINAL VERIFICATION ===================== */")
    for org in ORGS:
        db = org["db"]
        sql_parts.append(f"USE {db};")
        sql_parts.append("GO")
        sql_parts.append("SELECT DB_NAME() AS source_db, 'beneficiaries' AS table_name, COUNT(*) AS rows_count FROM dbo.beneficiaries UNION ALL")
        sql_parts.append("SELECT DB_NAME(), 'applications', COUNT(*) FROM dbo.applications UNION ALL")
        sql_parts.append("SELECT DB_NAME(), 'cases', COUNT(*) FROM dbo.cases UNION ALL")
        sql_parts.append("SELECT DB_NAME(), 'donations', COUNT(*) FROM dbo.donations UNION ALL")
        sql_parts.append("SELECT DB_NAME(), 'inventory_transactions', COUNT(*) FROM dbo.inventory_transactions UNION ALL")
        sql_parts.append("SELECT DB_NAME(), 'beneficiary_documents', COUNT(*) FROM dbo.beneficiary_documents UNION ALL")
        sql_parts.append("SELECT DB_NAME(), 'source_event_outbox', COUNT(*) FROM dbo.source_event_outbox;")
        sql_parts.append("GO")

    (args.output_dir / "01_load_synthetic_source_data.sql").write_text("\n".join(sql_parts), encoding="utf-8-sig")
    (args.output_dir / "generation_summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")

    print("DE-1 synthetic data generated successfully.")
    print(f"Output folder: {args.output_dir.resolve()}")
    for row in summary:
        print(row)
    print("Next: run output/01_load_synthetic_source_data.sql in SSMS on master.")


if __name__ == "__main__":
    main()
