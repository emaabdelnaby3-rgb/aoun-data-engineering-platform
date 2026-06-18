import re
from pathlib import Path

target = Path("backend/app/routers/phase3_complete.py")

if not target.exists():
    raise SystemExit("Cannot find backend/app/routers/phase3_complete.py")

text = target.read_text(encoding="utf-8")
backup = target.with_suffix(target.suffix + ".aoun_readonly_backup")
backup.write_text(text, encoding="utf-8")

replacement = r'''@router.get("/government/dashboard")
def government_dashboard():
    conn = get_connection()

    def safe_scalar(cursor, query, params=None, default=0):
        try:
            cursor.execute(query, params or [])
            row = cursor.fetchone()
            if not row or row[0] is None:
                return default
            return row[0]
        except Exception:
            try:
                conn.rollback()
            except Exception:
                pass
            return default

    try:
        cursor = conn.cursor()

        stats = {
            "organizations_count": safe_scalar(cursor, "SELECT COUNT(*) FROM dbo.organizations", default=0),
            "beneficiaries_count": safe_scalar(cursor, "SELECT COUNT(*) FROM dbo.beneficiary_profiles", default=0),
            "applications_count": safe_scalar(cursor, "SELECT COUNT(*) FROM dbo.beneficiary_applications", default=0),
            "cases_count": safe_scalar(cursor, "SELECT COUNT(*) FROM dbo.charity_cases", default=0),
            "donor_visible_cases": safe_scalar(cursor, "SELECT COUNT(*) FROM dbo.charity_cases WHERE case_status IN (N'OPEN', N'PUBLISHED')", default=0),
            "total_donations": safe_scalar(cursor, "SELECT COALESCE(SUM(amount), 0) FROM dbo.donations", default=0),
        }

        if not stats["total_donations"]:
            stats["total_donations"] = safe_scalar(cursor, "SELECT COALESCE(SUM(donation_amount), 0) FROM dbo.donations", default=0)

        cursor.execute("""
            SELECT
                organization_id,
                organization_code,
                organization_name_ar,
                organization_name_en
            FROM dbo.organizations
            ORDER BY organization_id;
        """)

        cols = [c[0] for c in cursor.description]
        base_orgs = [dict(zip(cols, row)) for row in cursor.fetchall()]
        organization_cards = []

        for org in base_orgs:
            org_id = org.get("organization_id")

            applications_count = safe_scalar(
                cursor,
                "SELECT COUNT(*) FROM dbo.beneficiary_applications WHERE organization_id = ?",
                [org_id],
                0
            )

            cases_count = safe_scalar(
                cursor,
                "SELECT COUNT(*) FROM dbo.charity_cases WHERE organization_id = ?",
                [org_id],
                0
            )

            open_cases = safe_scalar(
                cursor,
                "SELECT COUNT(*) FROM dbo.charity_cases WHERE organization_id = ? AND case_status IN (N'OPEN', N'PUBLISHED')",
                [org_id],
                0
            )

            completed_cases = safe_scalar(
                cursor,
                "SELECT COUNT(*) FROM dbo.charity_cases WHERE organization_id = ? AND case_status IN (N'FUNDED', N'CLOSED', N'COMPLETED')",
                [org_id],
                0
            )

            required_amount = safe_scalar(
                cursor,
                "SELECT COALESCE(SUM(required_amount), 0) FROM dbo.charity_cases WHERE organization_id = ?",
                [org_id],
                0
            )

            if not required_amount:
                required_amount = safe_scalar(
                    cursor,
                    "SELECT COALESCE(SUM(target_amount), 0) FROM dbo.charity_cases WHERE organization_id = ?",
                    [org_id],
                    0
                )

            collected_amount = safe_scalar(
                cursor,
                "SELECT COALESCE(SUM(collected_amount), 0) FROM dbo.charity_cases WHERE organization_id = ?",
                [org_id],
                0
            )

            total_donations = safe_scalar(
                cursor,
                "SELECT COALESCE(SUM(amount), 0) FROM dbo.donations WHERE organization_id = ?",
                [org_id],
                0
            )

            if not total_donations:
                total_donations = safe_scalar(
                    cursor,
                    "SELECT COALESCE(SUM(donation_amount), 0) FROM dbo.donations WHERE organization_id = ?",
                    [org_id],
                    0
                )

            organization_cards.append({
                **org,
                "applications_count": int(applications_count or 0),
                "cases_count": int(cases_count or 0),
                "open_cases": int(open_cases or 0),
                "completed_cases": int(completed_cases or 0),
                "required_amount": float(required_amount or 0),
                "collected_amount": float(collected_amount or 0),
                "total_donations": float(total_donations or 0),
            })

        return _ok({
            "stats": stats,
            "organizations": organization_cards,
            "organization_cards": organization_cards
        })

    finally:
        try:
            conn.close()
        except Exception:
            pass
'''

pattern = r'@router\.get\("/government/dashboard"\)\s*def government_dashboard\(\):.*?(?=\n@router\.(?:get|post|put|delete)\(|\Z)'

new_text, count = re.subn(pattern, replacement, text, flags=re.S)

if count == 0:
    raise SystemExit('Could not find @router.get("/government/dashboard") in phase3_complete.py')

target.write_text(new_text, encoding="utf-8")

print("OK: Backend government dashboard patched successfully.")
print("OK: Backup saved as backend/app/routers/phase3_complete.py.aoun_readonly_backup")
