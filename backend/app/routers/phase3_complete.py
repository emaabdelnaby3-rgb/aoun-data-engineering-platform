from __future__ import annotations

import json
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Optional

from fastapi import APIRouter, Body, HTTPException, Query
from fastapi.encoders import jsonable_encoder

from app.business_logic import fetch_all_dicts, fetch_one_dict
from app.database import get_connection, save_application_event, save_application_review_event, save_donation_event

router = APIRouter()


# -----------------------------------------------------------------------------
# Generic helpers
# -----------------------------------------------------------------------------

def _json_safe(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, list):
        return [_json_safe(v) for v in value]
    if isinstance(value, dict):
        return {k: _json_safe(v) for k, v in value.items()}
    return value


def _ok(data: Any = None, message: str = "ØªÙ… Ø¨Ù†Ø¬Ø§Ø­") -> dict:
    return jsonable_encoder({"success": True, "message": message, "data": _json_safe(data or {})})


def _fail(exc: Exception, status_code: int = 400) -> None:
    raise HTTPException(status_code=status_code, detail=str(exc))


def _now_month() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m")


def _bool(value: Any) -> int:
    if isinstance(value, bool):
        return 1 if value else 0
    if value is None:
        return 0
    return 1 if str(value).strip().lower() in {"1", "true", "yes", "y", "Ù†Ø¹Ù…", "Ø§Ù‡", "Ø£Ù‡"} else 0


def _next_code(cursor, table: str, column: str, prefix: str, digits: int = 5) -> str:
    cursor.execute(
        f"""
        SELECT ISNULL(MAX(TRY_CONVERT(INT, RIGHT({column}, ?))), 0) + 1
        FROM dbo.{table}
        WHERE {column} LIKE ?;
        """,
        digits,
        f"{prefix}-%",
    )
    return f"{prefix}-{int(cursor.fetchone()[0]):0{digits}d}"


def _validate_required(payload: dict, fields: list[str]) -> None:
    missing = [field for field in fields if payload.get(field) in (None, "")]
    if missing:
        raise ValueError("Ø­Ù‚ÙˆÙ„ Ù…Ø·Ù„ÙˆØ¨Ø© Ù†Ø§Ù‚ØµØ©: " + ", ".join(missing))


def _validate_amount(value: Any, label: str = "Ø§Ù„Ù…Ø¨Ù„Øº") -> float:
    try:
        amount = float(value)
    except Exception as exc:
        raise ValueError(f"{label} ÙŠØ¬Ø¨ Ø£Ù† ÙŠÙƒÙˆÙ† Ø±Ù‚Ù… ØµØ­ÙŠØ­.") from exc
    if amount <= 0:
        raise ValueError(f"{label} ÙŠØ¬Ø¨ Ø£Ù† ÙŠÙƒÙˆÙ† Ø£ÙƒØ¨Ø± Ù…Ù† ØµÙØ±.")
    return amount


def _resolve_case_id(cursor, value: Any) -> Optional[int]:
    if value in (None, ""):
        return None
    cursor.execute(
        """
        SELECT TOP 1 case_id
        FROM dbo.charity_cases
        WHERE case_id = TRY_CONVERT(INT, ?) OR case_code = ?;
        """,
        value,
        str(value),
    )
    row = cursor.fetchone()
    return int(row[0]) if row else None


def _resolve_payment_method_id(cursor, value: Any = None) -> int:
    if value not in (None, ""):
        cursor.execute(
            """
            SELECT TOP 1 payment_method_id
            FROM dbo.payment_methods
            WHERE payment_method_id = TRY_CONVERT(INT, ?)
               OR payment_method_code = ?
               OR method_name_ar = ?
               OR method_name_en = ?;
            """,
            value,
            str(value),
            str(value),
            str(value),
        )
        row = cursor.fetchone()
        if row:
            return int(row[0])
    cursor.execute("SELECT TOP 1 payment_method_id FROM dbo.payment_methods WHERE is_active = 1 ORDER BY payment_method_id;")
    row = cursor.fetchone()
    if not row:
        raise ValueError("Ù„Ø§ ØªÙˆØ¬Ø¯ Ø·Ø±Ù‚ Ø¯ÙØ¹ Ù…Ø³Ø¬Ù„Ø©.")
    return int(row[0])


def _support_type_select(alias: str = "st") -> str:
    return f"{alias}.support_name_ar AS support_type_name_ar"


# -----------------------------------------------------------------------------
# Health + reference + auth
# -----------------------------------------------------------------------------

@router.get("/health")
def health():
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT DB_NAME() AS db_name, SYSUTCDATETIME() AS server_time;")
            db_info = fetch_one_dict(cursor)
            cursor.execute("SELECT COUNT(*) AS cases_count FROM dbo.charity_cases;")
            counts = fetch_one_dict(cursor)
        return _ok({"phase": "Phase 3 Complete Integration", "database": db_info, "counts": counts})
    except Exception as exc:
        _fail(exc, 503)


@router.get("/healthcheck")
def healthcheck():
    checks: list[dict] = []
    def add(name: str, status: str, details: str = ""):
        checks.append({"check_name": name, "status": status, "details": details})
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            required_tables = [
                "organizations", "branches", "platform_users", "beneficiary_profiles", "beneficiary_applications",
                "charity_cases", "beneficiary_documents", "donations", "donor_favorites", "support_disbursements",
                "case_priority_scores", "eligibility_checks", "fraud_alerts"
            ]
            for table in required_tables:
                cursor.execute("SELECT OBJECT_ID(?) AS object_id;", f"dbo.{table}")
                add(f"unified table {table}", "PASS" if fetch_one_dict(cursor)["object_id"] else "FAIL")
            for obj in ["v_public_donor_cases", "v_beneficiary_support_profiles"]:
                cursor.execute("SELECT OBJECT_ID(?) AS object_id;", f"dbo.{obj}")
                add(f"unified view {obj}", "PASS" if fetch_one_dict(cursor)["object_id"] else "FAIL")
            for obj in [
                "charity_dwh.dbo.dim_time", "charity_dwh.dbo.dim_organization", "charity_dwh.dbo.fact_applications",
                "charity_dwh.dbo.fact_donations", "charity_dwh.dbo.v_powerbi_government_overview", "charity_dwh.dbo.v_powerbi_donations_overview"
            ]:
                cursor.execute("SELECT OBJECT_ID(?) AS object_id;", obj)
                add(f"DWH object {obj}", "PASS" if fetch_one_dict(cursor)["object_id"] else "FAIL")
        summary = {
            "total": len(checks),
            "pass": sum(1 for c in checks if c["status"] == "PASS"),
            "fail": sum(1 for c in checks if c["status"] == "FAIL"),
        }
        return _ok({"summary": summary, "checks": checks})
    except Exception as exc:
        _fail(exc, 503)


@router.get("/reference-data")
def reference_data():
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT organization_id, organization_code, organization_name_ar, organization_name_en FROM dbo.organizations WHERE is_active = 1 ORDER BY organization_id;")
            organizations = fetch_all_dicts(cursor)
            cursor.execute("SELECT support_type_id, support_code, support_name_ar, support_name_en FROM dbo.support_types WHERE is_active = 1 ORDER BY support_type_id;")
            support_types = fetch_all_dicts(cursor)
            cursor.execute("SELECT governorate_id, governorate_name_ar, governorate_name_en FROM dbo.governorates WHERE is_active = 1 ORDER BY governorate_id;")
            governorates = fetch_all_dicts(cursor)
            cursor.execute("SELECT city_id, governorate_id, city_name_ar, city_name_en FROM dbo.cities WHERE is_active = 1 ORDER BY city_id;")
            cities = fetch_all_dicts(cursor)
            cursor.execute("SELECT payment_method_id, payment_method_code, method_name_ar FROM dbo.payment_methods WHERE is_active = 1 ORDER BY payment_method_id;")
            payment_methods = fetch_all_dicts(cursor)
            cursor.execute("SELECT document_type_id, document_type_code, document_type_name_ar, is_required_by_default FROM dbo.document_types WHERE is_active = 1 ORDER BY document_type_id;")
            document_types = fetch_all_dicts(cursor)
        demo_users = [
            {"label": "Ø£Ø¯Ù…Ù† Ø§Ù„Ø­ÙƒÙˆÙ…Ø©", "identifier": "gov@test.com", "password": "demo-password", "role_code": "GOV_ADMIN"},
            {"label": "Ø£Ø¯Ù…Ù† Ø¨Ù†Ùƒ Ø§Ù„Ø·Ø¹Ø§Ù…", "identifier": "food.admin@test.com", "password": "demo-password", "role_code": "CHARITY_ADMIN"},
            {"label": "Ø£Ø¯Ù…Ù† Ø±Ø³Ø§Ù„Ø©", "identifier": "resala.admin@test.com", "password": "demo-password", "role_code": "CHARITY_ADMIN"},
            {"label": "Ø£Ø¯Ù…Ù† Ø­ÙŠØ§Ø© ÙƒØ±ÙŠÙ…Ø©", "identifier": "haya.admin@test.com", "password": "demo-password", "role_code": "CHARITY_ADMIN"},
            {"label": "Ù…Ø³ØªÙÙŠØ¯ ØªØ¬Ø±ÙŠØ¨ÙŠ", "identifier": "ahmed@test.com", "password": "demo-password", "role_code": "BENEFICIARY"},
            {"label": "Ù…ØªØ¨Ø±Ø¹ ØªØ¬Ø±ÙŠØ¨ÙŠ", "identifier": "donor@test.com", "password": "demo-password", "role_code": "DONOR"},
        ]
        return _ok({
            "organizations": organizations,
            "support_types": support_types,
            "governorates": governorates,
            "cities": cities,
            "payment_methods": payment_methods,
            "document_types": document_types,
            "demo_users": demo_users,
        })
    except Exception as exc:
        _fail(exc)


@router.post("/auth/login")
def login(payload: dict = Body(...)):
    try:
        identifier = str(payload.get("identifier") or payload.get("email") or payload.get("phone") or payload.get("national_id") or "").strip()
        password = str(payload.get("password") or "").strip()
        if not identifier:
            raise ValueError("Ø£Ø¯Ø®Ù„ÙŠ Ø§Ù„Ø¨Ø±ÙŠØ¯ Ø£Ùˆ Ø§Ù„Ù‡Ø§ØªÙ Ø£Ùˆ Ø§Ù„Ø±Ù‚Ù… Ø§Ù„Ù‚ÙˆÙ…ÙŠ.")
        if password and password != "123456":
            raise ValueError("ÙƒÙ„Ù…Ø© Ø§Ù„Ù…Ø±ÙˆØ± Ø§Ù„ØªØ¬Ø±ÙŠØ¨ÙŠØ© Ù‡ÙŠ 123456.")

        # Donor can work without platform user because donation records store donor name/phone/email directly.
        if identifier.lower() in {"donor@test.com", "01077000001", "donor"}:
            return _ok({
                "user_id": None,
                "role_code": "DONOR",
                "full_name": "Ù…ØªØ¨Ø±Ø¹ ØªØ¬Ø±ÙŠØ¨ÙŠ",
                "phone": "01077000001",
                "email": "donor@test.com",
                "organization_id": None,
                "organization_name_ar": None,
                "national_id": None,
            }, "ØªÙ… ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¯Ø®ÙˆÙ„ ÙƒÙ…ØªØ¨Ø±Ø¹")

        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT TOP 1
                    u.user_id, u.full_name, u.phone, u.email, u.organization_id, u.branch_id,
                    r.role_code, r.role_name_ar, o.organization_name_ar,
                    bp.beneficiary_id, bp.national_id
                FROM dbo.platform_users u
                JOIN dbo.roles r ON r.role_id = u.role_id
                LEFT JOIN dbo.organizations o ON o.organization_id = u.organization_id
                LEFT JOIN dbo.beneficiary_profiles bp ON bp.user_id = u.user_id
                WHERE u.email = ? OR u.phone = ? OR bp.national_id = ? OR u.user_code = ?
                ORDER BY u.user_id;
                """,
                identifier,
                identifier,
                identifier,
                identifier,
            )
            user = fetch_one_dict(cursor)
        if not user:
            raise ValueError("Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù… ØºÙŠØ± Ù…ÙˆØ¬ÙˆØ¯ ÙÙŠ Ù‚Ø§Ø¹Ø¯Ø© Ø§Ù„Ø¨ÙŠØ§Ù†Ø§Øª Ø§Ù„ØªØ¬Ø±ÙŠØ¨ÙŠØ©.")
        return _ok(user, "ØªÙ… ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¯Ø®ÙˆÙ„")
    except Exception as exc:
        _fail(exc)


# -----------------------------------------------------------------------------
# Beneficiary portal
# -----------------------------------------------------------------------------

@router.get("/beneficiary/dashboard/{national_id}")
def beneficiary_dashboard(national_id: str):
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM dbo.beneficiary_profiles WHERE national_id = ?;", national_id)
            profile = fetch_one_dict(cursor)
            if not profile:
                raise ValueError("Ø§Ù„Ù…Ø³ØªÙÙŠØ¯ ØºÙŠØ± Ù…ÙˆØ¬ÙˆØ¯.")
            beneficiary_id = int(profile["beneficiary_id"])
            cursor.execute("SELECT COUNT(*) AS applications_count FROM dbo.beneficiary_applications WHERE beneficiary_id = ?;", beneficiary_id)
            applications_count = fetch_one_dict(cursor)
            cursor.execute("SELECT COUNT(*) AS documents_count FROM dbo.beneficiary_documents WHERE beneficiary_id = ?;", beneficiary_id)
            documents_count = fetch_one_dict(cursor)
            cursor.execute("SELECT COUNT(*) AS cases_count FROM dbo.charity_cases WHERE beneficiary_id = ?;", beneficiary_id)
            cases_count = fetch_one_dict(cursor)
            cursor.execute("SELECT TOP 1 * FROM dbo.v_beneficiary_support_profiles WHERE beneficiary_id = ?;", beneficiary_id)
            support_profile = fetch_one_dict(cursor)
        return _ok({"profile": profile, "stats": {**applications_count, **documents_count, **cases_count}, "support_profile": support_profile})
    except Exception as exc:
        _fail(exc)


@router.post("/beneficiary/applications")
def submit_application(payload: dict = Body(...)):
    try:
        _validate_required(payload, ["full_name", "phone", "national_id", "support_type_id", "requested_amount"])
        if len(str(payload.get("phone"))) < 10:
            raise ValueError("Ø±Ù‚Ù… Ø§Ù„Ù‡Ø§ØªÙ ØºÙŠØ± ØµØ­ÙŠØ­.")
        _validate_amount(payload.get("requested_amount"), "Ø§Ù„Ù…Ø¨Ù„Øº Ø§Ù„Ù…Ø·Ù„ÙˆØ¨")

        event = {"event_type": "BENEFICIARY_APPLICATION_SUBMITTED", "source_system": "phase3_arabic_frontend", "payload": payload}
        result = save_application_event(payload, event)
        application_id = int(result["application_id"])
        with get_connection() as conn:
            cursor = conn.cursor()
            # Extra business fields are optional and created by the phase 3 SQL patch.
            cursor.execute(
                """
                UPDATE dbo.beneficiary_applications
                SET children_count = TRY_CONVERT(INT, ?),
                    has_chronic_disease = TRY_CONVERT(BIT, ?),
                    has_disability = TRY_CONVERT(BIT, ?),
                    is_widow_or_single_mother = TRY_CONVERT(BIT, ?),
                    rent_amount = TRY_CONVERT(DECIMAL(18,2), ?),
                    emergency_level = ?,
                    public_case_description = ?
                WHERE application_id = ?
                  AND COL_LENGTH('dbo.beneficiary_applications', 'children_count') IS NOT NULL;
                """,
                payload.get("children_count"),
                _bool(payload.get("has_chronic_disease")),
                _bool(payload.get("has_disability")),
                _bool(payload.get("is_widow_or_single_mother")),
                payload.get("rent_amount"),
                payload.get("emergency_level") or "MEDIUM",
                payload.get("public_case_description") or payload.get("case_description"),
                application_id,
            )
            cursor.execute("EXEC dbo.sp_phase3_recalculate_priority @application_id = ?;", application_id)
            cursor.execute("EXEC dbo.sp_phase3_record_eligibility @beneficiary_id = ?, @application_id = ?, @case_id = NULL, @organization_id = ?;", result["beneficiary_id"], application_id, result["organization_id"])
            conn.commit()
        return _ok(result, "ØªÙ… ØªÙ‚Ø¯ÙŠÙ… Ø§Ù„Ø·Ù„Ø¨ ÙˆØ­Ø³Ø§Ø¨ Ø§Ù„Ø£ÙˆÙ„ÙˆÙŠØ© ÙˆØ§Ù„Ø§Ø³ØªØ­Ù‚Ø§Ù‚")
    except Exception as exc:
        _fail(exc)


@router.get("/beneficiary/{national_id}/applications")
def beneficiary_applications(national_id: str):
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT
                    ba.application_id, ba.application_code, ba.application_status, ba.priority_level,
                    ba.requested_amount, ba.submitted_at, ba.reviewed_at, ba.admin_notes,
                    o.organization_name_ar, st.support_name_ar AS support_type_name_ar,
                    COALESCE(ps.priority_score, 0) AS priority_score,
                    COALESCE(ec.eligibility_status, N'UNKNOWN') AS eligibility_status,
                    ec.amount_received_this_month, ec.reason AS eligibility_reason
                FROM dbo.beneficiary_applications ba
                JOIN dbo.beneficiary_profiles bp ON bp.beneficiary_id = ba.beneficiary_id
                JOIN dbo.organizations o ON o.organization_id = ba.organization_id
                JOIN dbo.support_types st ON st.support_type_id = ba.support_type_id
                OUTER APPLY (
                    SELECT TOP 1 priority_score FROM dbo.case_priority_scores ps
                    WHERE ps.application_id = ba.application_id
                    ORDER BY ps.calculated_at DESC
                ) ps
                OUTER APPLY (
                    SELECT TOP 1 eligibility_status, amount_received_this_month, reason FROM dbo.eligibility_checks ec
                    WHERE ec.application_id = ba.application_id
                    ORDER BY ec.checked_at DESC
                ) ec
                WHERE bp.national_id = ?
                ORDER BY ba.submitted_at DESC;
                """,
                national_id,
            )
            rows = fetch_all_dicts(cursor)
        return _ok(rows)
    except Exception as exc:
        _fail(exc)


@router.get("/beneficiary/{national_id}/documents")
def beneficiary_documents(national_id: str):
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT
                    d.document_id, d.document_code, d.application_id, d.case_id, dt.document_type_name_ar,
                    d.original_file_name, d.content_type, d.file_size_kb, d.file_url, d.storage_path,
                    d.document_status, d.uploaded_at
                FROM dbo.beneficiary_documents d
                JOIN dbo.beneficiary_profiles bp ON bp.beneficiary_id = d.beneficiary_id
                JOIN dbo.document_types dt ON dt.document_type_id = d.document_type_id
                WHERE bp.national_id = ?
                ORDER BY d.uploaded_at DESC;
                """,
                national_id,
            )
            rows = fetch_all_dicts(cursor)
        return _ok(rows)
    except Exception as exc:
        _fail(exc)


@router.get("/beneficiary/{national_id}/support-profile")
def beneficiary_support_profile(national_id: str):
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM dbo.v_beneficiary_support_profiles WHERE national_id = ?;", national_id)
            profile = fetch_one_dict(cursor)
            if not profile:
                raise ValueError("Ø§Ù„Ù…Ø³ØªÙÙŠØ¯ ØºÙŠØ± Ù…ÙˆØ¬ÙˆØ¯.")
            cursor.execute(
                """
                SELECT TOP 30 sd.support_code, sd.support_month, sd.support_source, sd.amount_value,
                    sd.item_description, sd.quantity, sd.disbursement_status, sd.disbursed_at,
                    o.organization_name_ar, st.support_name_ar AS support_type_name_ar
                FROM dbo.support_disbursements sd
                JOIN dbo.beneficiary_profiles bp ON bp.beneficiary_id = sd.beneficiary_id
                JOIN dbo.organizations o ON o.organization_id = sd.organization_id
                JOIN dbo.support_types st ON st.support_type_id = sd.support_type_id
                WHERE bp.national_id = ?
                ORDER BY sd.disbursed_at DESC;
                """,
                national_id,
            )
            support_history = fetch_all_dicts(cursor)
            cursor.execute(
                """
                SELECT TOP 30 fa.alert_code, fa.alert_type, fa.severity, fa.risk_score, fa.alert_status, fa.description, fa.created_at AS created_at
                FROM dbo.fraud_alerts fa
                JOIN dbo.beneficiary_profiles bp ON bp.beneficiary_id = fa.beneficiary_id
                WHERE bp.national_id = ?
                ORDER BY fa.created_at DESC;
                """,
                national_id,
            )
            fraud_alerts = fetch_all_dicts(cursor)
        return _ok({"profile": profile, "support_history": support_history, "fraud_alerts": fraud_alerts})
    except Exception as exc:
        _fail(exc)


# -----------------------------------------------------------------------------
# Donor portal
# -----------------------------------------------------------------------------

@router.get("/donor/cases")
def donor_cases(organization_id: Optional[int] = Query(None), only_available: bool = Query(False), search: str = Query("")):
    try:
        filters = []
        params: list[Any] = []
        if organization_id:
            filters.append("organization_id = ?")
            params.append(organization_id)
        if only_available:
            filters.append("can_donate = 1")
        if search:
            filters.append("(case_title LIKE ? OR case_description LIKE ? OR public_display_name LIKE ? OR support_type_name_ar LIKE ?)")
            params.extend([f"%{search}%", f"%{search}%", f"%{search}%", f"%{search}%"])
        where = "WHERE " + " AND ".join(filters) if filters else ""
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(f"SELECT * FROM dbo.v_public_donor_cases {where} ORDER BY can_donate DESC, priority_score DESC, published_at DESC;", *params)
            rows = fetch_all_dicts(cursor)
        return _ok(rows)
    except Exception as exc:
        _fail(exc)


@router.get("/donor/favorites")
def donor_favorites(donor_phone: Optional[str] = Query(None), donor_user_id: Optional[int] = Query(None)):
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT f.favorite_id, f.created_at AS favorite_created_at, v.*
                FROM dbo.donor_favorites f
                JOIN dbo.v_public_donor_cases v ON v.case_id = f.case_id
                WHERE f.is_active = 1
                  AND ((? IS NOT NULL AND f.donor_phone = ?) OR (? IS NOT NULL AND f.donor_user_id = ?))
                ORDER BY f.created_at DESC;
                """,
                donor_phone,
                donor_phone,
                donor_user_id,
                donor_user_id,
            )
            rows = fetch_all_dicts(cursor)
        return _ok(rows)
    except Exception as exc:
        _fail(exc)


@router.post("/donor/favorites")
def add_favorite(payload: dict = Body(...)):
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            case_id = _resolve_case_id(cursor, payload.get("case_id") or payload.get("case_code"))
            if not case_id:
                raise ValueError("Ø§Ù„Ø­Ø§Ù„Ø© ØºÙŠØ± Ù…ÙˆØ¬ÙˆØ¯Ø©.")
            donor_phone = payload.get("donor_phone") or payload.get("phone") or "01077000001"
            donor_user_id = payload.get("donor_user_id")
            cursor.execute(
                """
                IF EXISTS (SELECT 1 FROM dbo.donor_favorites WHERE case_id = ? AND is_active = 1 AND donor_phone = ?)
                    UPDATE dbo.donor_favorites SET is_active = 1 WHERE case_id = ? AND donor_phone = ?;
                ELSE
                    INSERT INTO dbo.donor_favorites (donor_user_id, donor_phone, case_id) VALUES (TRY_CONVERT(INT, ?), ?, ?);
                """,
                case_id,
                donor_phone,
                case_id,
                donor_phone,
                donor_user_id,
                donor_phone,
                case_id,
            )
            conn.commit()
        return _ok({"case_id": case_id}, "ØªÙ…Øª Ø¥Ø¶Ø§ÙØ© Ø§Ù„Ø­Ø§Ù„Ø© Ù„Ù„Ù…ÙØ¶Ù„Ø©")
    except Exception as exc:
        _fail(exc)


@router.delete("/donor/favorites/{case_id}")
def remove_favorite(case_id: int, donor_phone: str = Query(...)):
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("UPDATE dbo.donor_favorites SET is_active = 0 WHERE case_id = ? AND donor_phone = ?;", case_id, donor_phone)
            conn.commit()
        return _ok({"case_id": case_id}, "ØªÙ… Ø­Ø°Ù Ø§Ù„Ø­Ø§Ù„Ø© Ù…Ù† Ø§Ù„Ù…ÙØ¶Ù„Ø©")
    except Exception as exc:
        _fail(exc)


@router.post("/donor/donations")
def create_donation(payload: dict = Body(...)):
    try:
        _validate_required(payload, ["amount"])
        amount = _validate_amount(payload.get("amount"), "Ù‚ÙŠÙ…Ø© Ø§Ù„ØªØ¨Ø±Ø¹")
        case_value = payload.get("case_id") or payload.get("case_code")
        if case_value:
            with get_connection() as conn:
                cursor = conn.cursor()
                case_id = _resolve_case_id(cursor, case_value)
                if not case_id:
                    raise ValueError("Ø§Ù„Ø­Ø§Ù„Ø© ØºÙŠØ± Ù…ÙˆØ¬ÙˆØ¯Ø©.")
                cursor.execute("SELECT can_donate, remaining_amount FROM dbo.v_public_donor_cases WHERE case_id = ?;", case_id)
                c = fetch_one_dict(cursor)
                if not c or not c.get("can_donate"):
                    raise ValueError("Ù‡Ø°Ù‡ Ø§Ù„Ø­Ø§Ù„Ø© ØºÙŠØ± Ù…ØªØ§Ø­Ø© Ù„Ù„ØªØ¨Ø±Ø¹ Ù‡Ø°Ø§ Ø§Ù„Ø´Ù‡Ø±.")
                if amount > float(c.get("remaining_amount") or 0):
                    amount = float(c.get("remaining_amount") or amount)
                payload["case_id"] = case_id
        event = {"event_type": "DONATION_CREATED", "source_system": "phase3_arabic_frontend", "payload": payload}
        result = save_donation_event(payload, event)
        if result.get("case_id"):
            with get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("EXEC dbo.sp_phase3_close_case_if_funded @case_id = ?;", int(result["case_id"]))
                conn.commit()
        return _ok(result, "ØªÙ… ØªØ³Ø¬ÙŠÙ„ Ø§Ù„ØªØ¨Ø±Ø¹ ÙˆØªØ­Ø¯ÙŠØ« Ø­Ø§Ù„Ø© Ø§Ù„Ø­Ø§Ù„Ø©")
    except Exception as exc:
        _fail(exc)


@router.get("/donor/donations")
def donor_donations(donor_phone: Optional[str] = Query(None), donor_email: Optional[str] = Query(None)):
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT TOP 100 d.donation_id, d.donation_code, d.donor_name, d.donor_phone, d.donor_email,
                    d.amount, d.currency, d.donation_status, d.payment_status, d.created_at,
                    o.organization_name_ar, c.case_code, c.case_title
                FROM dbo.donations d
                LEFT JOIN dbo.organizations o ON o.organization_id = d.organization_id
                LEFT JOIN dbo.charity_cases c ON c.case_id = d.case_id
                WHERE (? IS NULL OR d.donor_phone = ?) AND (? IS NULL OR d.donor_email = ?)
                ORDER BY d.created_at DESC;
                """,
                donor_phone,
                donor_phone,
                donor_email,
                donor_email,
            )
            rows = fetch_all_dicts(cursor)
        return _ok(rows)
    except Exception as exc:
        _fail(exc)


# -----------------------------------------------------------------------------
# Charity admin portal
# -----------------------------------------------------------------------------

@router.get("/admin/dashboard")
def admin_dashboard(organization_id: int = Query(...)):
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT
                    (SELECT COUNT(*) FROM dbo.beneficiary_applications WHERE organization_id = ?) AS total_applications,
                    (SELECT COUNT(*) FROM dbo.beneficiary_applications WHERE organization_id = ? AND application_status IN (N'SUBMITTED', N'ASSIGNED', N'UNDER_REVIEW')) AS pending_applications,
                    (SELECT COUNT(*) FROM dbo.charity_cases WHERE organization_id = ? AND case_status IN (N'OPEN', N'PUBLISHED')) AS open_cases,
                    (SELECT COUNT(*) FROM dbo.v_public_donor_cases WHERE organization_id = ? AND can_donate = 1) AS donor_visible_cases,
                    (SELECT COUNT(*) FROM dbo.fraud_alerts WHERE organization_id = ? AND alert_status IN (N'OPEN', N'UNDER_REVIEW')) AS open_fraud_alerts,
                    (SELECT COALESCE(SUM(amount), 0) FROM dbo.donations WHERE organization_id = ? AND donation_status = N'COMPLETED' AND payment_status = N'SUCCESS') AS total_donations;
                """,
                organization_id,
                organization_id,
                organization_id,
                organization_id,
                organization_id,
                organization_id,
            )
            stats = fetch_one_dict(cursor)
        return _ok(stats)
    except Exception as exc:
        _fail(exc)


@router.get("/admin/applications")
def admin_applications(organization_id: Optional[int] = Query(None)):
    try:
        params: list[Any] = []
        scope = ""
        if organization_id:
            scope = "WHERE ba.organization_id = ?"
            params.append(organization_id)
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                f"""
                SELECT
                    ba.application_id, ba.application_code, bp.full_name, bp.national_id, bp.phone,
                    o.organization_name_ar, st.support_name_ar AS support_type_name_ar,
                    ba.requested_amount, ba.application_status, ba.priority_level, ba.submitted_at, ba.reviewed_at,
                    COALESCE(ps.priority_score, 0) AS priority_score,
                    COALESCE(ec.eligibility_status, N'UNKNOWN') AS eligibility_status,
                    ec.reason AS eligibility_reason
                FROM dbo.beneficiary_applications ba
                JOIN dbo.beneficiary_profiles bp ON bp.beneficiary_id = ba.beneficiary_id
                JOIN dbo.organizations o ON o.organization_id = ba.organization_id
                JOIN dbo.support_types st ON st.support_type_id = ba.support_type_id
                OUTER APPLY (
                    SELECT TOP 1 priority_score FROM dbo.case_priority_scores ps WHERE ps.application_id = ba.application_id ORDER BY ps.calculated_at DESC
                ) ps
                OUTER APPLY (
                    SELECT TOP 1 eligibility_status, reason FROM dbo.eligibility_checks ec WHERE ec.application_id = ba.application_id ORDER BY ec.checked_at DESC
                ) ec
                {scope}
                ORDER BY COALESCE(ps.priority_score, 0) DESC, ba.submitted_at DESC;
                """,
                *params,
            )
            rows = fetch_all_dicts(cursor)
        return _ok(rows)
    except Exception as exc:
        _fail(exc)


@router.post("/admin/applications/{application_code}/review")
def review_application(application_code: str, payload: dict = Body(...)):
    try:
        decision = (payload.get("decision") or "").upper()
        if decision not in {"APPROVED", "REJECTED", "UNDER_REVIEW"}:
            raise ValueError("Ø§Ù„Ù‚Ø±Ø§Ø± ÙŠØ¬Ø¨ Ø£Ù† ÙŠÙƒÙˆÙ† APPROVED Ø£Ùˆ REJECTED Ø£Ùˆ UNDER_REVIEW.")
        if decision == "REJECTED" and not payload.get("notes"):
            raise ValueError("Ø³Ø¨Ø¨ Ø§Ù„Ø±ÙØ¶ Ù…Ø·Ù„ÙˆØ¨.")
        event = {"event_type": "APPLICATION_REVIEWED", "source_system": "phase3_arabic_frontend", "payload": {"application_code": application_code, **payload}}
        result = save_application_review_event(application_code, payload, event)
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT application_id, beneficiary_id, organization_id, application_status FROM dbo.beneficiary_applications WHERE application_code = ?;", application_code)
            app = fetch_one_dict(cursor)
            if app:
                cursor.execute(
                    """
                    INSERT INTO dbo.admin_reviews (application_id, beneficiary_id, organization_id, reviewer_user_id, review_action, review_notes, created_case_id)
                    VALUES (?, ?, ?, TRY_CONVERT(INT, ?), ?, ?, TRY_CONVERT(INT, ?));
                    """,
                    app["application_id"], app["beneficiary_id"], app["organization_id"], payload.get("reviewer_user_id"), decision, payload.get("notes"), result.get("created_case", {}).get("case_id") if result.get("created_case") else None,
                )
                cursor.execute("EXEC dbo.sp_phase3_recalculate_priority @application_id = ?;", int(app["application_id"]))
                if result.get("created_case"):
                    cursor.execute("EXEC dbo.sp_phase3_recalculate_priority @case_id = ?;", int(result["created_case"]["case_id"]))
                conn.commit()
        return _ok(result, "ØªÙ… Ø­ÙØ¸ Ù‚Ø±Ø§Ø± Ø§Ù„Ù…Ø±Ø§Ø¬Ø¹Ø©")
    except Exception as exc:
        _fail(exc)


@router.get("/admin/cases")
def admin_cases(organization_id: Optional[int] = Query(None)):
    try:
        where = "WHERE c.organization_id = ?" if organization_id else ""
        params = [organization_id] if organization_id else []
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                f"""
                SELECT c.case_id, c.case_code, c.case_title, c.case_description, c.required_amount, c.collected_amount,
                    CASE WHEN c.required_amount - c.collected_amount < 0 THEN 0 ELSE c.required_amount - c.collected_amount END AS remaining_amount,
                    c.case_status, c.priority_level, c.published_at, c.created_at,
                    bp.full_name, bp.national_id, o.organization_name_ar, st.support_name_ar AS support_type_name_ar,
                    COALESCE(v.can_donate, CAST(0 AS BIT)) AS can_donate,
                    COALESCE(v.eligibility_label_ar, N'') AS eligibility_label_ar,
                    COALESCE(v.priority_score, 0) AS priority_score
                FROM dbo.charity_cases c
                JOIN dbo.beneficiary_profiles bp ON bp.beneficiary_id = c.beneficiary_id
                JOIN dbo.organizations o ON o.organization_id = c.organization_id
                JOIN dbo.support_types st ON st.support_type_id = c.support_type_id
                LEFT JOIN dbo.v_public_donor_cases v ON v.case_id = c.case_id
                {where}
                ORDER BY c.created_at DESC;
                """,
                *params,
            )
            rows = fetch_all_dicts(cursor)
        return _ok(rows)
    except Exception as exc:
        _fail(exc)


@router.post("/admin/cases")
def create_case(payload: dict = Body(...)):
    try:
        _validate_required(payload, ["application_code", "case_title", "required_amount"])
        amount = _validate_amount(payload.get("required_amount"), "Ø§Ù„Ù…Ø¨Ù„Øº Ø§Ù„Ù…Ø·Ù„ÙˆØ¨")
        application_code = payload.get("application_code")
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT application_id, beneficiary_id, organization_id, branch_id, support_type_id, priority_level
                FROM dbo.beneficiary_applications
                WHERE application_code = ?;
                """,
                application_code,
            )
            app = fetch_one_dict(cursor)
            if not app:
                raise ValueError("Ø§Ù„Ø·Ù„Ø¨ ØºÙŠØ± Ù…ÙˆØ¬ÙˆØ¯.")
            case_code = _next_code(cursor, "charity_cases", "case_code", "CASE")
            status = "PUBLISHED" if _bool(payload.get("publish_now")) else "OPEN"
            cursor.execute(
                """
                INSERT INTO dbo.charity_cases
                (case_code, application_id, beneficiary_id, organization_id, branch_id, support_type_id, case_title, case_description, required_amount, collected_amount, case_status, priority_level, published_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, CASE WHEN ? IN (N'PUBLISHED', N'OPEN') THEN SYSUTCDATETIME() ELSE NULL END);
                """,
                case_code,
                app["application_id"], app["beneficiary_id"], app["organization_id"], app.get("branch_id"), app["support_type_id"],
                payload.get("case_title"), payload.get("case_description") or "", amount, status, payload.get("priority_level") or app.get("priority_level") or "MEDIUM", status,
            )
            cursor.execute("SELECT case_id FROM dbo.charity_cases WHERE case_code = ?;", case_code)
            case_id = int(cursor.fetchone()[0])
            cursor.execute("EXEC dbo.sp_phase3_recalculate_priority @case_id = ?;", case_id)
            conn.commit()
        return _ok({"case_id": case_id, "case_code": case_code}, "ØªÙ… Ø¥Ù†Ø´Ø§Ø¡ Ø§Ù„Ø­Ø§Ù„Ø©")
    except Exception as exc:
        _fail(exc)


@router.patch("/admin/cases/{case_id}")
def update_case(case_id: int, payload: dict = Body(...)):
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            updates = []
            params: list[Any] = []
            allowed = {
                "case_title": "case_title", "case_description": "case_description", "required_amount": "required_amount",
                "case_status": "case_status", "priority_level": "priority_level", "is_public": "is_public",
                "donation_enabled": "donation_enabled", "documents_verified": "documents_verified", "is_monthly_case": "is_monthly_case",
                "eligibility_status": "eligibility_status", "public_display_name": "public_display_name",
            }
            for key, column in allowed.items():
                if key in payload:
                    updates.append(f"{column} = ?")
                    params.append(payload[key])
            if not updates:
                return _ok({"case_id": case_id}, "Ù„Ø§ ØªÙˆØ¬Ø¯ ØªØ¹Ø¯ÙŠÙ„Ø§Øª")
            if payload.get("case_status") in {"PUBLISHED", "OPEN"}:
                updates.append("published_at = COALESCE(published_at, SYSUTCDATETIME())")
            params.append(case_id)
            cursor.execute(f"UPDATE dbo.charity_cases SET {', '.join(updates)} WHERE case_id = ?;", *params)
            cursor.execute("EXEC dbo.sp_phase3_recalculate_priority @case_id = ?;", case_id)
            conn.commit()
        return _ok({"case_id": case_id}, "ØªÙ… ØªØ­Ø¯ÙŠØ« Ø§Ù„Ø­Ø§Ù„Ø©")
    except Exception as exc:
        _fail(exc)


@router.get("/admin/fraud-alerts")
def fraud_alerts(organization_id: Optional[int] = Query(None)):
    try:
        where = "WHERE fa.organization_id = ?" if organization_id else ""
        params = [organization_id] if organization_id else []
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                f"""
                SELECT TOP 100 fa.fraud_alert_id, fa.alert_code, fa.alert_type, fa.severity, fa.risk_score, fa.alert_status,
                    fa.description, fa.created_at, o.organization_name_ar, bp.full_name, bp.national_id
                FROM dbo.fraud_alerts fa
                LEFT JOIN dbo.organizations o ON o.organization_id = fa.organization_id
                LEFT JOIN dbo.beneficiary_profiles bp ON bp.beneficiary_id = fa.beneficiary_id
                {where}
                ORDER BY CASE fa.severity WHEN N'CRITICAL' THEN 1 WHEN N'HIGH' THEN 2 WHEN N'MEDIUM' THEN 3 ELSE 4 END, fa.created_at DESC;
                """,
                *params,
            )
            rows = fetch_all_dicts(cursor)
        return _ok(rows)
    except Exception as exc:
        _fail(exc)


@router.get("/admin/support-profiles")
def admin_support_profiles(organization_id: Optional[int] = Query(None), search: str = Query(""), only_not_eligible: bool = Query(False)):
    try:
        filters = []
        params: list[Any] = []
        if organization_id:
            filters.append("(EXISTS (SELECT 1 FROM dbo.beneficiary_applications a WHERE a.beneficiary_id = v.beneficiary_id AND a.organization_id = ?) OR EXISTS (SELECT 1 FROM dbo.support_disbursements s WHERE s.beneficiary_id = v.beneficiary_id AND s.organization_id = ?))")
            params.extend([organization_id, organization_id])
        if search:
            filters.append("(v.full_name LIKE ? OR v.national_id LIKE ? OR v.phone LIKE ?)")
            params.extend([f"%{search}%", f"%{search}%", f"%{search}%"])
        if only_not_eligible:
            filters.append("v.monthly_eligibility_status <> N'ELIGIBLE'")
        where = "WHERE " + " AND ".join(filters) if filters else ""
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(f"SELECT * FROM dbo.v_beneficiary_support_profiles v {where} ORDER BY amount_received_this_month DESC, full_name;", *params)
            rows = fetch_all_dicts(cursor)
        return _ok(rows)
    except Exception as exc:
        _fail(exc)


@router.post("/admin/support-disbursements")
def manual_support(payload: dict = Body(...)):
    try:
        _validate_required(payload, ["national_id", "organization_id", "support_type_id"])
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT beneficiary_id FROM dbo.beneficiary_profiles WHERE national_id = ?;", payload.get("national_id"))
            row = fetch_one_dict(cursor)
            if not row:
                raise ValueError("Ø§Ù„Ù…Ø³ØªÙÙŠØ¯ ØºÙŠØ± Ù…ÙˆØ¬ÙˆØ¯.")
            support_code = _next_code(cursor, "support_disbursements", "support_code", "SUP")
            cursor.execute(
                """
                INSERT INTO dbo.support_disbursements
                (support_code, beneficiary_id, organization_id, branch_id, application_id, case_id, support_type_id, support_month, support_source, amount_value, item_description, quantity, notes)
                VALUES (?, ?, TRY_CONVERT(INT, ?), TRY_CONVERT(INT, ?), TRY_CONVERT(INT, ?), TRY_CONVERT(INT, ?), TRY_CONVERT(INT, ?), ?, N'MANUAL', TRY_CONVERT(DECIMAL(18,2), ?), ?, TRY_CONVERT(DECIMAL(18,2), ?), ?);
                """,
                support_code,
                row["beneficiary_id"],
                payload.get("organization_id"), payload.get("branch_id"), payload.get("application_id"), payload.get("case_id"), payload.get("support_type_id"),
                payload.get("support_month") or _now_month(), payload.get("amount_value") or 0, payload.get("item_description"), payload.get("quantity"), payload.get("notes"),
            )
            cursor.execute("EXEC dbo.sp_phase3_record_eligibility @beneficiary_id = ?, @application_id = NULL, @case_id = NULL, @organization_id = ?;", row["beneficiary_id"], payload.get("organization_id"))
            conn.commit()
        return _ok({"support_code": support_code}, "ØªÙ… ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¯Ø¹Ù… Ø§Ù„ÙŠØ¯ÙˆÙŠ")
    except Exception as exc:
        _fail(exc)


# -----------------------------------------------------------------------------
# Beneficiary 360 + Government + DWH
# -----------------------------------------------------------------------------

@router.get("/beneficiaries/search")
def search_beneficiaries(q: str = Query(""), organization_id: Optional[int] = Query(None)):
    try:
        filters = []
        params: list[Any] = []
        if q:
            filters.append("(bp.full_name LIKE ? OR bp.national_id LIKE ? OR bp.phone LIKE ?)")
            params.extend([f"%{q}%", f"%{q}%", f"%{q}%"])
        if organization_id:
            filters.append("EXISTS (SELECT 1 FROM dbo.beneficiary_org_registrations r WHERE r.beneficiary_id = bp.beneficiary_id AND r.organization_id = ?)")
            params.append(organization_id)
        where = "WHERE " + " AND ".join(filters) if filters else ""
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                f"""
                SELECT TOP 50 bp.beneficiary_id, bp.beneficiary_code, bp.full_name, bp.national_id, bp.phone,
                    bp.family_size, bp.monthly_income, g.governorate_name_ar, c.city_name_ar
                FROM dbo.beneficiary_profiles bp
                LEFT JOIN dbo.governorates g ON g.governorate_id = bp.governorate_id
                LEFT JOIN dbo.cities c ON c.city_id = bp.city_id
                {where}
                ORDER BY bp.full_name;
                """,
                *params,
            )
            rows = fetch_all_dicts(cursor)
        return _ok(rows)
    except Exception as exc:
        _fail(exc)


@router.get("/beneficiaries/360")
def beneficiary_360(national_id: str = Query(...)):
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT TOP 1 * FROM dbo.v_beneficiary_support_profiles WHERE national_id = ?;", national_id)
            profile = fetch_one_dict(cursor)
            if not profile:
                raise ValueError("Ø§Ù„Ù…Ø³ØªÙÙŠØ¯ ØºÙŠØ± Ù…ÙˆØ¬ÙˆØ¯.")
            bid = profile["beneficiary_id"]
            cursor.execute(
                """
                SELECT a.application_code, a.application_status, a.requested_amount, a.priority_level, a.submitted_at,
                    o.organization_name_ar, st.support_name_ar AS support_type_name_ar
                FROM dbo.beneficiary_applications a
                JOIN dbo.organizations o ON o.organization_id = a.organization_id
                JOIN dbo.support_types st ON st.support_type_id = a.support_type_id
                WHERE a.beneficiary_id = ? ORDER BY a.submitted_at DESC;
                """,
                bid,
            )
            applications = fetch_all_dicts(cursor)
            cursor.execute(
                """
                SELECT c.case_code, c.case_title, c.case_status, c.required_amount, c.collected_amount, c.priority_level,
                    o.organization_name_ar, st.support_name_ar AS support_type_name_ar
                FROM dbo.charity_cases c
                JOIN dbo.organizations o ON o.organization_id = c.organization_id
                JOIN dbo.support_types st ON st.support_type_id = c.support_type_id
                WHERE c.beneficiary_id = ? ORDER BY c.created_at DESC;
                """,
                bid,
            )
            cases = fetch_all_dicts(cursor)
            cursor.execute(
                """
                SELECT sd.support_code, sd.support_month, sd.amount_value, sd.item_description, sd.support_source,
                    o.organization_name_ar, st.support_name_ar AS support_type_name_ar
                FROM dbo.support_disbursements sd
                JOIN dbo.organizations o ON o.organization_id = sd.organization_id
                JOIN dbo.support_types st ON st.support_type_id = sd.support_type_id
                WHERE sd.beneficiary_id = ? ORDER BY sd.disbursed_at DESC;
                """,
                bid,
            )
            support_history = fetch_all_dicts(cursor)
            cursor.execute("SELECT alert_code, alert_type, severity, risk_score, alert_status, description, created_at FROM dbo.fraud_alerts WHERE beneficiary_id = ? ORDER BY created_at DESC;", bid)
            fraud_alerts = fetch_all_dicts(cursor)
        return _ok({"profile": profile, "applications": applications, "cases": cases, "support_history": support_history, "fraud_alerts": fraud_alerts})
    except Exception as exc:
        _fail(exc)


@router.get("/government/dashboard")
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

@router.get("/government/dwh-overview")
def dwh_overview():
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT TOP 100 * FROM charity_dwh.dbo.v_powerbi_government_overview ORDER BY year_number DESC, month_number DESC;")
            government_overview = fetch_all_dicts(cursor)
            cursor.execute("SELECT TOP 100 * FROM charity_dwh.dbo.v_powerbi_donations_overview ORDER BY year_number DESC, month_number DESC;")
            donations_overview = fetch_all_dicts(cursor)
            cursor.execute(
                """
                SELECT 'dim_time' AS object_name, COUNT(*) AS rows_count FROM charity_dwh.dbo.dim_time
                UNION ALL SELECT 'dim_organization', COUNT(*) FROM charity_dwh.dbo.dim_organization
                UNION ALL SELECT 'fact_applications', COUNT(*) FROM charity_dwh.dbo.fact_applications
                UNION ALL SELECT 'fact_donations', COUNT(*) FROM charity_dwh.dbo.fact_donations;
                """
            )
            row_counts = fetch_all_dicts(cursor)
        return _ok({"government_overview": government_overview, "donations_overview": donations_overview, "row_counts": row_counts})
    except Exception as exc:
        _fail(exc)

