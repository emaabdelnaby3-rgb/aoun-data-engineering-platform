from __future__ import annotations

import json
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Optional

from fastapi import APIRouter, Body, HTTPException, Query
from fastapi.encoders import jsonable_encoder

from app.business_logic import fetch_all_dicts, fetch_one_dict
from app.database import (
    get_connection,
    save_application_event,
    save_application_review_event,
    save_donation_event,
)

router = APIRouter()


def _json_safe(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (datetime,)):
        return value.isoformat()
    if isinstance(value, list):
        return [_json_safe(v) for v in value]
    if isinstance(value, dict):
        return {k: _json_safe(v) for k, v in value.items()}
    return value


def _ok(data: Any = None, message: str = "تم بنجاح") -> dict:
    return jsonable_encoder({"success": True, "message": message, "data": _json_safe(data or {})})


def _raise(exc: Exception) -> None:
    raise HTTPException(status_code=400, detail=str(exc))


def _now_month() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m")


def _bool(value: Any) -> int:
    if isinstance(value, bool):
        return 1 if value else 0
    if value is None:
        return 0
    return 1 if str(value).strip().lower() in {"1", "true", "yes", "y", "نعم", "اه", "أه"} else 0


def _priority_level(score: int) -> str:
    if score >= 61:
        return "CRITICAL"
    if score >= 41:
        return "HIGH"
    if score >= 21:
        return "MEDIUM"
    return "LOW"


def _priority_level_ar(level: str) -> str:
    return {
        "CRITICAL": "حرجة",
        "HIGH": "عالية",
        "MEDIUM": "متوسطة",
        "LOW": "منخفضة",
    }.get(level, level)


def _next_code(cursor, table: str, column: str, prefix: str) -> str:
    cursor.execute(
        f"""
        SELECT ISNULL(MAX(TRY_CONVERT(INT, RIGHT({column}, 5))), 0) + 1
        FROM dbo.{table}
        WHERE {column} LIKE ?;
        """,
        f"{prefix}-%",
    )
    return f"{prefix}-{int(cursor.fetchone()[0]):05d}"


def _resolve_case_id(cursor, case_value: Any) -> Optional[int]:
    if case_value in (None, ""):
        return None
    cursor.execute(
        """
        SELECT TOP 1 case_id
        FROM dbo.charity_cases
        WHERE case_id = TRY_CONVERT(INT, ?)
           OR case_code = ?;
        """,
        case_value,
        str(case_value),
    )
    row = cursor.fetchone()
    return int(row[0]) if row else None


def _resolve_donor_user_id(cursor, payload: dict) -> Optional[int]:
    donor_user_id = payload.get("donor_user_id") or payload.get("user_id")
    if donor_user_id:
        return int(donor_user_id)

    donor_phone = payload.get("donor_phone") or payload.get("phone")
    donor_email = payload.get("donor_email") or payload.get("email")
    if not donor_phone and not donor_email:
        return None

    cursor.execute(
        """
        SELECT TOP 1 user_id
        FROM dbo.platform_users
        WHERE (? IS NOT NULL AND phone = ?)
           OR (? IS NOT NULL AND email = ?)
        ORDER BY user_id;
        """,
        donor_phone,
        donor_phone,
        donor_email,
        donor_email,
    )
    row = cursor.fetchone()
    return int(row[0]) if row else None


def _calculate_priority_from_row(row: dict, support_count: int = 0, high_fraud_count: int = 0) -> tuple[int, str, dict]:
    details: dict[str, Any] = {}
    score = 0

    family_size = int(row.get("family_size") or 0)
    children_count = int(row.get("children_count") or 0)
    monthly_income = float(row.get("monthly_income") or 999999)
    has_chronic_disease = _bool(row.get("has_chronic_disease"))
    has_disability = _bool(row.get("has_disability"))
    is_widow_or_single_mother = _bool(row.get("is_widow_or_single_mother"))
    rent_amount = float(row.get("rent_amount") or 0)
    emergency_level = str(row.get("emergency_level") or "").upper()

    if family_size >= 5:
        score += 5
        details["family_size"] = "+5 family size >= 5"
    if children_count > 3:
        score += 5
        details["children_count"] = "+5 more than 3 children"
    if monthly_income <= 1500:
        score += 8
        details["low_income"] = "+8 monthly income <= 1500"
    if monthly_income <= 800:
        score += 5
        details["very_low_income"] = "+5 monthly income <= 800"
    if has_chronic_disease:
        score += 10
        details["chronic_disease"] = "+10 chronic disease"
    if has_disability:
        score += 10
        details["disability"] = "+10 disability"
    if is_widow_or_single_mother:
        score += 8
        details["widow_or_single_mother"] = "+8 widow/single mother"
    if rent_amount >= 1500:
        score += 5
        details["rent_burden"] = "+5 rent burden"
    if emergency_level in {"HIGH", "CRITICAL", "عالي", "حرج"}:
        score += 15
        details["emergency"] = "+15 high emergency"
    elif emergency_level in {"MEDIUM", "متوسط"}:
        score += 7
        details["emergency"] = "+7 medium emergency"
    if support_count > 0:
        score -= 10
        details["support_this_month"] = "-10 already received support this month"
    if high_fraud_count > 0:
        score -= 30
        details["high_fraud"] = "-30 high/critical fraud alert"

    score = max(score, 0)
    level = _priority_level(score)
    details["final_score"] = score
    details["priority_level"] = level
    details["priority_level_ar"] = _priority_level_ar(level)
    return score, level, details


def _recalculate_priority(cursor, application_id: Optional[int] = None, case_id: Optional[int] = None) -> Optional[dict]:
    if application_id:
        cursor.execute(
            """
            SELECT TOP 1
                ba.application_id,
                cc.case_id,
                ba.beneficiary_id,
                ba.organization_id,
                bp.family_size,
                bp.monthly_income,
                ba.children_count,
                ba.has_chronic_disease,
                ba.has_disability,
                ba.is_widow_or_single_mother,
                ba.rent_amount,
                ba.emergency_level
            FROM dbo.beneficiary_applications ba
            JOIN dbo.beneficiary_profiles bp ON bp.beneficiary_id = ba.beneficiary_id
            LEFT JOIN dbo.charity_cases cc ON cc.application_id = ba.application_id
            WHERE ba.application_id = ?;
            """,
            application_id,
        )
    elif case_id:
        cursor.execute(
            """
            SELECT TOP 1
                ba.application_id,
                cc.case_id,
                cc.beneficiary_id,
                cc.organization_id,
                bp.family_size,
                bp.monthly_income,
                ba.children_count,
                ba.has_chronic_disease,
                ba.has_disability,
                ba.is_widow_or_single_mother,
                ba.rent_amount,
                ba.emergency_level
            FROM dbo.charity_cases cc
            JOIN dbo.beneficiary_profiles bp ON bp.beneficiary_id = cc.beneficiary_id
            LEFT JOIN dbo.beneficiary_applications ba ON ba.application_id = cc.application_id
            WHERE cc.case_id = ?;
            """,
            case_id,
        )
    else:
        return None

    row = fetch_one_dict(cursor)
    if not row:
        return None

    current_month = _now_month()
    cursor.execute(
        """
        SELECT COUNT(*) AS support_count
        FROM dbo.support_disbursements
        WHERE beneficiary_id = ? AND support_month = ? AND disbursement_status = N'COMPLETED';
        """,
        row["beneficiary_id"],
        current_month,
    )
    support_count = int((fetch_one_dict(cursor) or {}).get("support_count") or 0)

    cursor.execute(
        """
        SELECT COUNT(*) AS high_fraud_count
        FROM dbo.fraud_alerts
        WHERE beneficiary_id = ?
          AND alert_status IN (N'OPEN', N'UNDER_REVIEW')
          AND severity IN (N'HIGH', N'CRITICAL');
        """,
        row["beneficiary_id"],
    )
    high_fraud_count = int((fetch_one_dict(cursor) or {}).get("high_fraud_count") or 0)

    score, level, details = _calculate_priority_from_row(row, support_count, high_fraud_count)

    cursor.execute(
        """
        INSERT INTO dbo.case_priority_scores
        (application_id, case_id, beneficiary_id, organization_id, priority_score, priority_level, scoring_details)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """,
        row.get("application_id"),
        row.get("case_id"),
        row["beneficiary_id"],
        row["organization_id"],
        score,
        level,
        json.dumps(details, ensure_ascii=False),
    )

    if row.get("application_id"):
        cursor.execute(
            """
            UPDATE dbo.beneficiary_applications
            SET priority_level = ?
            WHERE application_id = ?;
            """,
            level,
            row["application_id"],
        )

    if row.get("case_id"):
        cursor.execute(
            """
            UPDATE dbo.charity_cases
            SET priority_level = ?
            WHERE case_id = ?;
            """,
            level,
            row["case_id"],
        )

    return {"priority_score": score, "priority_level": level, "priority_level_ar": _priority_level_ar(level), "details": details}


def _record_eligibility(cursor, beneficiary_id: int, application_id: Optional[int], case_id: Optional[int], organization_id: Optional[int]) -> dict:
    month = _now_month()
    cursor.execute(
        """
        SELECT COUNT(*) AS support_count, COALESCE(SUM(amount_value), 0) AS amount_received
        FROM dbo.support_disbursements
        WHERE beneficiary_id = ? AND support_month = ? AND disbursement_status = N'COMPLETED';
        """,
        beneficiary_id,
        month,
    )
    support = fetch_one_dict(cursor) or {}
    support_count = int(support.get("support_count") or 0)
    amount_received = float(support.get("amount_received") or 0)

    cursor.execute(
        """
        SELECT COUNT(*) AS fraud_count
        FROM dbo.fraud_alerts
        WHERE beneficiary_id = ?
          AND severity IN (N'HIGH', N'CRITICAL')
          AND alert_status IN (N'OPEN', N'UNDER_REVIEW');
        """,
        beneficiary_id,
    )
    fraud_count = int((fetch_one_dict(cursor) or {}).get("fraud_count") or 0)

    if fraud_count > 0:
        status = "MANUAL_REVIEW"
        reason = "يوجد تنبيه احتيال عالي/حرج، يحتاج مراجعة يدوية."
    elif support_count > 0:
        status = "NOT_ELIGIBLE_THIS_MONTH"
        reason = "المستفيد حصل على دعم بالفعل خلال هذا الشهر."
    else:
        status = "ELIGIBLE"
        reason = "لم يحصل على دعم هذا الشهر ولا توجد تنبيهات حرجة."

    cursor.execute(
        """
        INSERT INTO dbo.eligibility_checks
        (beneficiary_id, application_id, case_id, organization_id, check_month, eligibility_status, amount_received_this_month, support_count_this_month, reason)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """,
        beneficiary_id,
        application_id,
        case_id,
        organization_id,
        month,
        status,
        amount_received,
        support_count,
        reason,
    )
    return {
        "check_month": month,
        "eligibility_status": status,
        "eligibility_label_ar": "مستحق هذا الشهر" if status == "ELIGIBLE" else "غير مستحق هذا الشهر" if status == "NOT_ELIGIBLE_THIS_MONTH" else "مراجعة يدوية",
        "amount_received_this_month": amount_received,
        "support_count_this_month": support_count,
        "reason": reason,
    }


def _create_support_disbursement_if_funded(cursor, case_id: int) -> Optional[dict]:
    cursor.execute(
        """
        SELECT
            c.case_id, c.case_code, c.beneficiary_id, c.organization_id, c.branch_id,
            c.application_id, c.support_type_id, c.required_amount, c.collected_amount,
            c.case_status
        FROM dbo.charity_cases c
        WHERE c.case_id = ?;
        """,
        case_id,
    )
    c = fetch_one_dict(cursor)
    if not c:
        return None

    collected = float(c.get("collected_amount") or 0)
    required = float(c.get("required_amount") or 0)
    if required <= 0 or collected < required:
        return None

    month = _now_month()
    cursor.execute(
        """
        SELECT TOP 1 support_disbursement_id, support_code
        FROM dbo.support_disbursements
        WHERE case_id = ? AND support_month = ? AND support_source = N'DONATION';
        """,
        case_id,
        month,
    )
    existing = fetch_one_dict(cursor)
    if existing:
        return existing

    support_code = _next_code(cursor, "support_disbursements", "support_code", "SUP")
    cursor.execute(
        """
        INSERT INTO dbo.support_disbursements
        (support_code, beneficiary_id, organization_id, branch_id, application_id, case_id, support_type_id, support_month, support_source, amount_value, item_description, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, N'DONATION', ?, N'دعم مالي مكتمل من المتبرعين', N'تم تسجيل الدعم تلقائياً عند اكتمال مبلغ الحالة.');
        """,
        support_code,
        c["beneficiary_id"],
        c["organization_id"],
        c.get("branch_id"),
        c.get("application_id"),
        c["case_id"],
        c["support_type_id"],
        month,
        collected,
    )
    cursor.execute(
        """
        UPDATE dbo.charity_cases
        SET case_status = N'CLOSED',
            eligibility_status = N'NOT_ELIGIBLE_THIS_MONTH',
            donation_enabled = 0,
            closed_at = COALESCE(closed_at, SYSUTCDATETIME())
        WHERE case_id = ?;
        """,
        case_id,
    )
    return {"support_code": support_code, "support_month": month, "amount_value": collected}


@router.get("/health")
def phase2_health():
    return _ok({"phase": "Phase 2", "status": "database + backend business APIs ready"})


@router.post("/beneficiary/applications")
def submit_beneficiary_application(payload: dict = Body(...)):
    """Beneficiary applies, uploads business fields, then the system calculates priority + eligibility."""
    try:
        event = {
            "event_type": "BENEFICIARY_APPLICATION_SUBMITTED",
            "source_system": "arabic_frontend_phase2",
            "payload": payload,
        }
        result = save_application_event(payload, event)
        application_id = int(result["application_id"])

        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                UPDATE dbo.beneficiary_applications
                SET children_count = TRY_CONVERT(INT, ?),
                    has_chronic_disease = ?,
                    has_disability = ?,
                    is_widow_or_single_mother = ?,
                    rent_amount = TRY_CONVERT(DECIMAL(18,2), ?),
                    emergency_level = ?,
                    monthly_support_limit = TRY_CONVERT(DECIMAL(18,2), ?),
                    public_case_description = ?,
                    internal_review_notes = ?
                WHERE application_id = ?;
                """,
                payload.get("children_count"),
                _bool(payload.get("has_chronic_disease")),
                _bool(payload.get("has_disability")),
                _bool(payload.get("is_widow_or_single_mother")),
                payload.get("rent_amount"),
                payload.get("emergency_level"),
                payload.get("monthly_support_limit"),
                payload.get("public_case_description") or payload.get("case_description"),
                payload.get("internal_review_notes"),
                application_id,
            )
            priority = _recalculate_priority(cursor, application_id=application_id)
            eligibility = _record_eligibility(
                cursor,
                int(result["beneficiary_id"]),
                application_id,
                None,
                int(result["organization_id"]),
            )
            conn.commit()

        result["priority"] = priority
        result["eligibility"] = eligibility
        return _ok(result, "تم تقديم الطلب وحساب الأولوية والأهلية")
    except Exception as exc:
        _raise(exc)


@router.get("/beneficiary/{national_id}/applications")
def beneficiary_application_tracking(national_id: str):
    """Application tracking page for beneficiary."""
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT
                    ba.application_code,
                    ba.application_status,
                    ba.priority_level,
                    ba.requested_amount,
                    ba.submitted_at,
                    ba.reviewed_at,
                    o.organization_name_ar,
                    st.support_name_ar AS support_type_name_ar,
                    ba.admin_notes
                FROM dbo.beneficiary_applications ba
                JOIN dbo.beneficiary_profiles bp ON bp.beneficiary_id = ba.beneficiary_id
                JOIN dbo.organizations o ON o.organization_id = ba.organization_id
                JOIN dbo.support_types st ON st.support_type_id = ba.support_type_id
                WHERE bp.national_id = ?
                ORDER BY ba.submitted_at DESC;
                """,
                national_id,
            )
            rows = fetch_all_dicts(cursor)
        return _ok(rows)
    except Exception as exc:
        _raise(exc)


@router.post("/admin/applications/{application_code}/review")
def admin_review_application(application_code: str, payload: dict = Body(...)):
    """Charity admin approves/rejects/under-review and optionally creates a case."""
    try:
        event = {
            "event_type": "BENEFICIARY_APPLICATION_REVIEWED",
            "source_system": "arabic_frontend_phase2",
            "payload": {"application_code": application_code, **payload},
        }
        result = save_application_review_event(application_code, payload, event)

        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT application_id, beneficiary_id, organization_id, application_status
                FROM dbo.beneficiary_applications
                WHERE application_code = ?;
                """,
                application_code,
            )
            app = fetch_one_dict(cursor)
            if app:
                cursor.execute(
                    """
                    INSERT INTO dbo.admin_reviews
                    (application_id, beneficiary_id, organization_id, reviewer_user_id, review_action, review_notes, created_case_id)
                    VALUES (?, ?, ?, TRY_CONVERT(INT, ?), ?, ?, TRY_CONVERT(INT, ?));
                    """,
                    app["application_id"],
                    app["beneficiary_id"],
                    app["organization_id"],
                    payload.get("reviewer_user_id"),
                    payload.get("decision"),
                    payload.get("notes"),
                    result.get("created_case", {}).get("case_id") if result.get("created_case") else None,
                )
                cursor.execute(
                    """
                    INSERT INTO dbo.application_status_history
                    (application_id, old_status, new_status, changed_by_user_id, change_reason)
                    VALUES (?, NULL, ?, TRY_CONVERT(INT, ?), ?);
                    """,
                    app["application_id"],
                    app["application_status"],
                    payload.get("reviewer_user_id"),
                    payload.get("notes"),
                )
                priority = _recalculate_priority(cursor, application_id=int(app["application_id"]))
                if result.get("created_case"):
                    case_id = int(result["created_case"]["case_id"])
                    public_name = payload.get("public_display_name") or f"مستفيد رقم {app['beneficiary_id']}"
                    cursor.execute(
                        """
                        UPDATE dbo.charity_cases
                        SET is_public = 1,
                            donation_enabled = 1,
                            eligibility_status = N'ELIGIBLE',
                            public_display_name = COALESCE(?, public_display_name),
                            documents_verified = COALESCE(TRY_CONVERT(BIT, ?), documents_verified),
                            is_monthly_case = COALESCE(TRY_CONVERT(BIT, ?), is_monthly_case)
                        WHERE case_id = ?;
                        """,
                        public_name,
                        _bool(payload.get("documents_verified")),
                        _bool(payload.get("is_monthly_case")),
                        case_id,
                    )
                    _recalculate_priority(cursor, case_id=case_id)
                conn.commit()
                result["priority"] = priority
        return _ok(result, "تم تسجيل قرار الأدمن")
    except Exception as exc:
        _raise(exc)


@router.get("/admin/applications")
def admin_list_applications(organization_id: Optional[int] = Query(None)):
    """Charity admin sees only own organization when organization_id is passed. Government can omit it."""
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
                    ba.application_id,
                    ba.application_code,
                    bp.full_name,
                    bp.national_id,
                    bp.phone,
                    o.organization_name_ar,
                    st.support_name_ar AS support_type_name_ar,
                    ba.requested_amount,
                    ba.application_status,
                    ba.priority_level,
                    ba.submitted_at,
                    ps.priority_score,
                    ec.eligibility_status,
                    ec.reason AS eligibility_reason
                FROM dbo.beneficiary_applications ba
                JOIN dbo.beneficiary_profiles bp ON bp.beneficiary_id = ba.beneficiary_id
                JOIN dbo.organizations o ON o.organization_id = ba.organization_id
                JOIN dbo.support_types st ON st.support_type_id = ba.support_type_id
                OUTER APPLY (
                    SELECT TOP 1 priority_score FROM dbo.case_priority_scores ps
                    WHERE ps.application_id = ba.application_id
                    ORDER BY calculated_at DESC
                ) ps
                OUTER APPLY (
                    SELECT TOP 1 eligibility_status, reason FROM dbo.eligibility_checks ec
                    WHERE ec.application_id = ba.application_id
                    ORDER BY checked_at DESC
                ) ec
                {scope}
                ORDER BY COALESCE(ps.priority_score, 0) DESC, ba.submitted_at DESC;
                """,
                *params,
            )
            rows = fetch_all_dicts(cursor)
        return _ok(rows)
    except Exception as exc:
        _raise(exc)


@router.get("/donor/cases")
def donor_available_cases(
    organization_id: Optional[int] = Query(None),
    only_available: bool = Query(False),
    support_type_id: Optional[int] = Query(None),
):
    """Donor page: public cases without admin-sensitive data."""
    try:
        filters = []
        params: list[Any] = []
        if organization_id:
            filters.append("organization_id = ?")
            params.append(organization_id)
        if support_type_id:
            filters.append("support_type_id = ?")
            params.append(support_type_id)
        if only_available:
            filters.append("can_donate = 1")
        where = "WHERE " + " AND ".join(filters) if filters else ""
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                f"""
                SELECT *
                FROM dbo.v_public_donor_cases
                {where}
                ORDER BY priority_score DESC, published_at DESC;
                """,
                *params,
            )
            rows = fetch_all_dicts(cursor)
        return _ok(rows)
    except Exception as exc:
        _raise(exc)


@router.post("/donor/favorites")
def donor_add_favorite(payload: dict = Body(...)):
    """Donor favorites a monthly/available case."""
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            case_id = _resolve_case_id(cursor, payload.get("case_id") or payload.get("case_code"))
            if not case_id:
                raise ValueError("الحالة غير موجودة.")
            donor_user_id = _resolve_donor_user_id(cursor, payload)
            donor_phone = payload.get("donor_phone") or payload.get("phone")
            cursor.execute(
                """
                SELECT TOP 1 favorite_id
                FROM dbo.donor_favorites
                WHERE case_id = ?
                  AND is_active = 1
                  AND (
                        (? IS NOT NULL AND donor_user_id = ?)
                     OR (? IS NOT NULL AND donor_phone = ?)
                  );
                """,
                case_id,
                donor_user_id,
                donor_user_id,
                donor_phone,
                donor_phone,
            )
            existing = fetch_one_dict(cursor)
            if existing:
                return _ok(existing, "الحالة موجودة بالفعل في المفضلة")
            cursor.execute(
                """
                INSERT INTO dbo.donor_favorites (donor_user_id, donor_phone, case_id)
                VALUES (?, ?, ?);
                """,
                donor_user_id,
                donor_phone,
                case_id,
            )
            cursor.execute("SELECT SCOPE_IDENTITY() AS favorite_id;")
            row = fetch_one_dict(cursor)
            conn.commit()
        return _ok(row, "تمت إضافة الحالة للمفضلة")
    except Exception as exc:
        _raise(exc)


@router.get("/donor/favorites")
def donor_list_favorites(donor_user_id: Optional[int] = Query(None), donor_phone: Optional[str] = Query(None)):
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT
                    f.favorite_id,
                    f.created_at AS favorite_created_at,
                    v.*
                FROM dbo.donor_favorites f
                JOIN dbo.v_public_donor_cases v ON v.case_id = f.case_id
                WHERE f.is_active = 1
                  AND ((? IS NOT NULL AND f.donor_user_id = ?) OR (? IS NOT NULL AND f.donor_phone = ?))
                ORDER BY f.created_at DESC;
                """,
                donor_user_id,
                donor_user_id,
                donor_phone,
                donor_phone,
            )
            rows = fetch_all_dicts(cursor)
        return _ok(rows)
    except Exception as exc:
        _raise(exc)


@router.post("/donor/donations")
def donor_create_donation(payload: dict = Body(...)):
    """Donation endpoint with fully-funded monthly eligibility update."""
    try:
        event = {"event_type": "DONATION_CREATED", "source_system": "arabic_frontend_phase2", "payload": payload}
        result = save_donation_event(payload, event)
        support = None
        if result.get("case_id"):
            with get_connection() as conn:
                cursor = conn.cursor()
                support = _create_support_disbursement_if_funded(cursor, int(result["case_id"]))
                if support:
                    _recalculate_priority(cursor, case_id=int(result["case_id"]))
                conn.commit()
        result["support_disbursement"] = support
        return _ok(result, "تم تسجيل التبرع وتحديث حالة الاستحقاق")
    except Exception as exc:
        _raise(exc)


@router.get("/support-profiles")
def list_support_profiles(
    organization_id: Optional[int] = Query(None),
    only_not_eligible: bool = Query(False),
    search: Optional[str] = Query(None),
):
    """Charity/Government page: support received this month + eligibility + fraud summary."""
    try:
        filters = []
        params: list[Any] = []
        if organization_id:
            filters.append(
                """
                EXISTS (SELECT 1 FROM dbo.beneficiary_org_registrations r WHERE r.beneficiary_id = v.beneficiary_id AND r.organization_id = ?)
                OR EXISTS (SELECT 1 FROM dbo.beneficiary_applications a WHERE a.beneficiary_id = v.beneficiary_id AND a.organization_id = ?)
                OR EXISTS (SELECT 1 FROM dbo.charity_cases c WHERE c.beneficiary_id = v.beneficiary_id AND c.organization_id = ?)
                OR EXISTS (SELECT 1 FROM dbo.support_disbursements s WHERE s.beneficiary_id = v.beneficiary_id AND s.organization_id = ?)
                """
            )
            params.extend([organization_id, organization_id, organization_id, organization_id])
        if only_not_eligible:
            filters.append("v.monthly_eligibility_status <> N'ELIGIBLE'")
        if search:
            filters.append("(v.full_name LIKE ? OR v.national_id LIKE ? OR v.phone LIKE ?)")
            params.extend([f"%{search}%", f"%{search}%", f"%{search}%"])
        where = "WHERE " + " AND ".join(f"({f})" for f in filters) if filters else ""
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                f"""
                SELECT *
                FROM dbo.v_beneficiary_support_profiles v
                {where}
                ORDER BY
                    CASE monthly_eligibility_status WHEN N'MANUAL_REVIEW' THEN 1 WHEN N'NOT_ELIGIBLE_THIS_MONTH' THEN 2 ELSE 3 END,
                    amount_received_this_month DESC,
                    full_name;
                """,
                *params,
            )
            rows = fetch_all_dicts(cursor)
        return _ok(rows)
    except Exception as exc:
        _raise(exc)


@router.get("/beneficiary/{national_id}/support-profile")
def beneficiary_support_profile(national_id: str):
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT *
                FROM dbo.v_beneficiary_support_profiles
                WHERE national_id = ?;
                """,
                national_id,
            )
            profile = fetch_one_dict(cursor)
            if not profile:
                raise ValueError("المستفيد غير موجود.")

            cursor.execute(
                """
                SELECT TOP 20
                    sd.support_month,
                    sd.support_source,
                    sd.amount_value,
                    sd.item_description,
                    sd.quantity,
                    o.organization_name_ar,
                    st.support_name_ar AS support_type_name_ar,
                    sd.disbursed_at
                FROM dbo.support_disbursements sd
                JOIN dbo.organizations o ON o.organization_id = sd.organization_id
                JOIN dbo.support_types st ON st.support_type_id = sd.support_type_id
                JOIN dbo.beneficiary_profiles bp ON bp.beneficiary_id = sd.beneficiary_id
                WHERE bp.national_id = ?
                ORDER BY sd.disbursed_at DESC;
                """,
                national_id,
            )
            support_history = fetch_all_dicts(cursor)

            cursor.execute(
                """
                SELECT TOP 20 alert_type, severity, risk_score, alert_status, description, created_at
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
        _raise(exc)


@router.get("/admin/dashboard")
def charity_admin_dashboard(organization_id: int = Query(...)):
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT
                    (SELECT COUNT(*) FROM dbo.beneficiary_applications WHERE organization_id = ?) AS applications_count,
                    (SELECT COUNT(*) FROM dbo.beneficiary_applications WHERE organization_id = ? AND application_status IN (N'SUBMITTED', N'ASSIGNED', N'UNDER_REVIEW')) AS pending_applications,
                    (SELECT COUNT(*) FROM dbo.charity_cases WHERE organization_id = ? AND case_status IN (N'OPEN', N'PUBLISHED')) AS open_cases,
                    (SELECT COUNT(*) FROM dbo.fraud_alerts WHERE organization_id = ? AND alert_status IN (N'OPEN', N'UNDER_REVIEW')) AS fraud_alerts,
                    (SELECT COALESCE(SUM(amount), 0) FROM dbo.donations WHERE organization_id = ? AND donation_status = N'COMPLETED' AND payment_status = N'SUCCESS') AS total_donations;
                """,
                organization_id,
                organization_id,
                organization_id,
                organization_id,
                organization_id,
            )
            stats = fetch_one_dict(cursor)
        return _ok(stats)
    except Exception as exc:
        _raise(exc)


@router.get("/government/dashboard")
def government_dashboard():
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT
                    (SELECT COUNT(*) FROM dbo.organizations WHERE is_active = 1) AS organizations_count,
                    (SELECT COUNT(*) FROM dbo.beneficiary_profiles WHERE is_active = 1) AS beneficiaries_count,
                    (SELECT COUNT(*) FROM dbo.beneficiary_applications) AS applications_count,
                    (SELECT COUNT(*) FROM dbo.charity_cases WHERE case_status IN (N'OPEN', N'PUBLISHED')) AS open_cases,
                    (SELECT COUNT(*) FROM dbo.v_beneficiary_support_profiles WHERE monthly_eligibility_status <> N'ELIGIBLE') AS not_eligible_this_month,
                    (SELECT COUNT(*) FROM dbo.fraud_alerts WHERE alert_status IN (N'OPEN', N'UNDER_REVIEW')) AS open_fraud_alerts,
                    (SELECT COALESCE(SUM(amount), 0) FROM dbo.donations WHERE donation_status = N'COMPLETED' AND payment_status = N'SUCCESS') AS total_donations;
                """
            )
            stats = fetch_one_dict(cursor)
        return _ok(stats)
    except Exception as exc:
        _raise(exc)


@router.post("/support-disbursements/manual")
def manual_support_disbursement(payload: dict = Body(...)):
    """Admin records non-money support manually, such as food boxes or medicine."""
    try:
        with get_connection() as conn:
            cursor = conn.cursor()
            national_id = payload.get("national_id")
            cursor.execute("SELECT beneficiary_id FROM dbo.beneficiary_profiles WHERE national_id = ?;", national_id)
            row = fetch_one_dict(cursor)
            if not row:
                raise ValueError("المستفيد غير موجود.")
            beneficiary_id = int(row["beneficiary_id"])
            organization_id = int(payload.get("organization_id"))
            support_type_id = int(payload.get("support_type_id"))
            support_code = _next_code(cursor, "support_disbursements", "support_code", "SUP")
            cursor.execute(
                """
                INSERT INTO dbo.support_disbursements
                (support_code, beneficiary_id, organization_id, branch_id, application_id, case_id, support_type_id, support_month, support_source, amount_value, item_description, quantity, notes)
                VALUES (?, ?, ?, TRY_CONVERT(INT, ?), TRY_CONVERT(INT, ?), TRY_CONVERT(INT, ?), ?, ?, N'MANUAL', TRY_CONVERT(DECIMAL(18,2), ?), ?, TRY_CONVERT(DECIMAL(18,2), ?), ?);
                """,
                support_code,
                beneficiary_id,
                organization_id,
                payload.get("branch_id"),
                payload.get("application_id"),
                payload.get("case_id"),
                support_type_id,
                payload.get("support_month") or _now_month(),
                payload.get("amount_value") or 0,
                payload.get("item_description"),
                payload.get("quantity"),
                payload.get("notes"),
            )
            eligibility = _record_eligibility(cursor, beneficiary_id, payload.get("application_id"), payload.get("case_id"), organization_id)
            conn.commit()
        return _ok({"support_code": support_code, "eligibility": eligibility}, "تم تسجيل الدعم للمستفيد")
    except Exception as exc:
        _raise(exc)
