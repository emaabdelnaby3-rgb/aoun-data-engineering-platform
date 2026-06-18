import json
import uuid
from typing import Any, Optional

import pyodbc


# ============================================================
# Generic SQL helpers
# ============================================================

def fetch_one_dict(cursor: pyodbc.Cursor) -> Optional[dict]:
    row = cursor.fetchone()
    if not row:
        return None
    columns = [column[0] for column in cursor.description]
    return dict(zip(columns, row))


def fetch_all_dicts(cursor: pyodbc.Cursor) -> list[dict]:
    columns = [column[0] for column in cursor.description]
    return [dict(zip(columns, row)) for row in cursor.fetchall()]


def to_json(payload: Any) -> str:
    return json.dumps(payload, ensure_ascii=False, default=str)


def _table_exists(cursor: pyodbc.Cursor, table_name: str) -> bool:
    cursor.execute(
        """
        SELECT 1
        FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA = 'dbo'
          AND TABLE_NAME = ?
        """,
        table_name,
    )
    return cursor.fetchone() is not None


def _get_existing_columns(cursor: pyodbc.Cursor, table_name: str) -> set[str]:
    cursor.execute(
        """
        SELECT COLUMN_NAME
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = 'dbo'
          AND TABLE_NAME = ?
        """,
        table_name,
    )
    return {str(row[0]).lower() for row in cursor.fetchall()}


def _insert_dynamic(cursor: pyodbc.Cursor, table_name: str, values: dict) -> None:
    """
    Insert only columns that exist in dbo.<table_name>.
    This protects the app from old-schema/new-schema column differences.
    """
    if not _table_exists(cursor, table_name):
        return

    existing = _get_existing_columns(cursor, table_name)
    final_values = {key: value for key, value in values.items() if key.lower() in existing}

    if not final_values:
        return

    columns_sql = ", ".join(final_values.keys())
    placeholders_sql = ", ".join(["?"] * len(final_values))

    cursor.execute(
        f"INSERT INTO dbo.{table_name} ({columns_sql}) VALUES ({placeholders_sql})",
        *list(final_values.values()),
    )


def _next_alert_code(base_code: str, entity_id: Optional[str] = None) -> str:
    """
    fraud_alerts.alert_code is UNIQUE in the clean DB.
    Keep it short enough for NVARCHAR(50).
    """
    clean_base = str(base_code or "ALERT").upper().replace(" ", "_")[:22]
    clean_entity = str(entity_id or "NA").upper().replace(" ", "_").replace("-", "")[:10]
    suffix = uuid.uuid4().hex[:8].upper()
    return f"{clean_base}-{clean_entity}-{suffix}"[:50]


def _parse_int(value: Any) -> Optional[int]:
    if value is None:
        return None
    try:
        return int(str(value).strip())
    except Exception:
        return None


def _resolve_id_from_code(
    cursor: pyodbc.Cursor,
    table_name: str,
    id_column: str,
    code_column: str,
    value: Optional[str],
) -> Optional[int]:
    if not value or not _table_exists(cursor, table_name):
        return None

    numeric = _parse_int(value)
    if numeric is not None:
        cursor.execute(
            f"SELECT {id_column} FROM dbo.{table_name} WHERE {id_column} = ?",
            numeric,
        )
        row = cursor.fetchone()
        if row:
            return int(row[0])

    cursor.execute(
        f"SELECT {id_column} FROM dbo.{table_name} WHERE {code_column} = ?",
        str(value),
    )
    row = cursor.fetchone()
    return int(row[0]) if row else None


# ============================================================
# Validation helpers
# ============================================================

def validate_national_id(national_id: Optional[str]) -> None:
    if not national_id or not str(national_id).isdigit() or len(str(national_id)) != 14:
        raise ValueError("الرقم القومي يجب أن يكون 14 رقم.")


def validate_phone(phone: Optional[str]) -> None:
    if not phone:
        return
    phone = str(phone)
    if not phone.isdigit() or len(phone) != 11 or not phone.startswith("01"):
        raise ValueError("رقم الهاتف يجب أن يكون 11 رقم ويبدأ بـ 01.")


def validate_positive(value: Any, field_name_ar: str) -> float:
    number = float(value or 0)
    if number <= 0:
        raise ValueError(f"{field_name_ar} يجب أن يكون أكبر من صفر.")
    return number


# ============================================================
# Audit / Fraud
# ============================================================

def create_audit_log(
    cursor: pyodbc.Cursor,
    action_type: str,
    entity_name: str,
    entity_id: Optional[str],
    old_value: Any = None,
    new_value: Any = None,
    actor_user_id: Optional[int] = None,
) -> None:
    """
    Safe for both old and clean schemas.
    """
    old_json = to_json(old_value) if old_value is not None else None
    new_json = to_json(new_value) if new_value is not None else None

    values = {
        "actor_user_id": actor_user_id,
        "user_id": actor_user_id,
        "performed_by_user_id": actor_user_id,

        "action_type": action_type,
        "action": action_type,
        "operation_type": action_type,

        "entity_name": entity_name,
        "table_name": entity_name,
        "target_table": entity_name,
        "record_type": entity_name,

        "entity_id": entity_id,
        "record_id": entity_id,
        "target_id": entity_id,

        "old_value": old_json,
        "new_value": new_json,
        "old_values": old_json,
        "new_values": new_json,
        "details": new_json,
        "description": f"{action_type} on {entity_name} {entity_id}",
        "source_system": "unified_charity_platform",
    }

    _insert_dynamic(cursor, "audit_logs", values)


def create_fraud_alert(
    cursor: pyodbc.Cursor,
    alert_code: str,
    alert_type: str,
    severity: str,
    entity_name: str,
    entity_id: Optional[str],
    description: str,
    risk_score: int,
    user_id: Optional[int] = None,
    organization_id: Optional[int] = None,
) -> None:
    """
    Clean-schema safe fraud insert.

    Clean DB fraud_alerts columns include:
    alert_code, alert_type, severity, risk_score, alert_status,
    beneficiary_id, application_id, case_id, donation_id,
    inventory_transaction_id, organization_id, description.
    """
    application_id = None
    case_id = None
    donation_id = None
    document_id = None
    inventory_transaction_id = None
    beneficiary_id = None

    if entity_name == "beneficiary_applications":
        application_id = _resolve_id_from_code(
            cursor, "beneficiary_applications", "application_id", "application_code", entity_id
        )
    elif entity_name == "charity_cases":
        case_id = _resolve_id_from_code(cursor, "charity_cases", "case_id", "case_code", entity_id)
    elif entity_name == "donations":
        donation_id = _resolve_id_from_code(cursor, "donations", "donation_id", "donation_code", entity_id)
    elif entity_name == "beneficiary_documents":
        document_id = _resolve_id_from_code(
            cursor, "beneficiary_documents", "document_id", "document_code", entity_id
        )
    elif entity_name == "inventory_transactions":
        inventory_transaction_id = _resolve_id_from_code(
            cursor, "inventory_transactions", "transaction_id", "transaction_code", entity_id
        )

    if application_id:
        cursor.execute(
            "SELECT beneficiary_id FROM dbo.beneficiary_applications WHERE application_id = ?",
            application_id,
        )
        row = cursor.fetchone()
        beneficiary_id = int(row[0]) if row else None

    values = {
        "alert_code": _next_alert_code(alert_code, entity_id),
        "alert_type": alert_type,
        "severity": severity,
        "risk_level": severity,
        "risk_score": float(risk_score),
        "score": float(risk_score),

        "alert_status": "OPEN",
        "status": "OPEN",

        "beneficiary_id": beneficiary_id,
        "application_id": application_id,
        "case_id": case_id,
        "donation_id": donation_id,
        "document_id": document_id,
        "inventory_transaction_id": inventory_transaction_id,
        "organization_id": organization_id,

        # Old/alternative schemas
        "entity_name": entity_name,
        "entity_id": entity_id,
        "related_entity": entity_name,
        "related_entity_id": entity_id,
        "user_id": user_id,
        "actor_user_id": user_id,

        "description": description,
        "alert_description": description,
        "details": description,
    }

    _insert_dynamic(cursor, "fraud_alerts", values)


def insert_fraud_alert(*args, **kwargs) -> None:
    """
    Backward-compatible alias.
    Any old code calling insert_fraud_alert will use the safe implementation.
    """
    create_fraud_alert(*args, **kwargs)


# ============================================================
# Reference resolvers
# ============================================================

def resolve_support_type_id(
    cursor: pyodbc.Cursor,
    support_value: Optional[str],
    support_type_id: Optional[int] = None,
) -> int:
    if support_type_id:
        cursor.execute(
            "SELECT support_type_id FROM dbo.support_types WHERE support_type_id = ? AND is_active = 1",
            int(support_type_id),
        )
        row = cursor.fetchone()
        if row:
            return int(row[0])

    value = support_value or "دعم شهري"
    mappings = {
        "Food Support": "FOOD",
        "Medical Support": "MEDICAL",
        "Educational Support": "EDUCATION",
        "Monthly Support": "MONTHLY",
        "Housing Support": "HOUSING",
        "Emergency Support": "EMERGENCY",
        "دعم غذائي": "FOOD",
        "دعم طبي": "MEDICAL",
        "دعم تعليمي": "EDUCATION",
        "دعم شهري": "MONTHLY",
        "دعم سكن": "HOUSING",
        "دعم طارئ": "EMERGENCY",
    }
    code = mappings.get(value, value)

    cursor.execute(
        """
        SELECT TOP 1 support_type_id
        FROM dbo.support_types
        WHERE support_code = ?
           OR support_name_ar = ?
           OR support_name_en = ?
        ORDER BY support_type_id
        """,
        code,
        value,
        value,
    )
    row = cursor.fetchone()
    if row:
        return int(row[0])

    cursor.execute("SELECT TOP 1 support_type_id FROM dbo.support_types WHERE is_active = 1 ORDER BY support_type_id")
    row = cursor.fetchone()
    if not row:
        raise ValueError("لا توجد أنواع دعم مفعلة في قاعدة البيانات.")
    return int(row[0])


def resolve_payment_method_id(cursor: pyodbc.Cursor, value: Optional[str]) -> int:
    value = str(value or "").strip()
    mappings = {
        "PM_001": "PM-CARD",
        "PM_002": "PM-WALLET",
        "PM_003": "PM-BANK",
        "BANK_CARD": "PM-CARD",
        "E_WALLET": "PM-WALLET",
        "BANK_TRANSFER": "PM-BANK",
        "CASH": "PM-CASH",
        "كاش": "PM-CASH",
    }
    code = mappings.get(value, value)

    cursor.execute(
        """
        SELECT TOP 1 payment_method_id
        FROM dbo.payment_methods
        WHERE payment_method_id = TRY_CONVERT(INT, ?)
           OR payment_method_code = ?
           OR method_name_ar = ?
           OR method_name_en = ?
        ORDER BY payment_method_id
        """,
        value,
        code,
        value,
        value,
    )
    row = cursor.fetchone()
    if row:
        return int(row[0])

    cursor.execute("SELECT TOP 1 payment_method_id FROM dbo.payment_methods WHERE is_active = 1 ORDER BY payment_method_id")
    row = cursor.fetchone()
    if not row:
        raise ValueError("طريقة الدفع غير موجودة في قاعدة البيانات.")
    return int(row[0])


def resolve_inventory_item(cursor: pyodbc.Cursor, item_value: str) -> dict:
    value = str(item_value or "").strip()
    mappings = {
        "item_food_box": "ITEM-FOOD-BOX",
        "FOOD_BOX": "ITEM-FOOD-BOX",
        "item_blanket": "ITEM-BLANKET",
        "BLANKET": "ITEM-BLANKET",
        "item_medicine": "ITEM-MEDICINE",
        "MEDICINE_PACK": "ITEM-MEDICINE",
        "item_school_bag": "ITEM-SCHOOL-BAG",
        "SCHOOL_BAG": "ITEM-SCHOOL-BAG",
    }
    code = mappings.get(value, value)

    cursor.execute(
        """
        SELECT TOP 1 item_id, item_code, item_name_ar, item_name_en, unit, default_unit_cost
        FROM dbo.inventory_items
        WHERE item_id = TRY_CONVERT(INT, ?)
           OR item_code = ?
           OR item_name_ar = ?
           OR item_name_en = ?
        ORDER BY item_id
        """,
        value,
        code,
        value,
        value,
    )
    item = fetch_one_dict(cursor)
    if not item:
        raise ValueError("الصنف غير موجود في قاعدة البيانات.")
    return item


def resolve_branch_for_organization(
    cursor: pyodbc.Cursor,
    organization_id: int,
    branch_value: Optional[str] = None,
    governorate: Optional[str] = None,
) -> Optional[int]:
    if branch_value:
        cursor.execute(
            """
            SELECT TOP 1 branch_id
            FROM dbo.branches
            WHERE organization_id = ?
              AND is_active = 1
              AND (
                    branch_id = TRY_CONVERT(INT, ?)
                    OR branch_code = ?
                    OR branch_name_ar = ?
                    OR branch_name_en = ?
                  )
            ORDER BY branch_id
            """,
            organization_id,
            branch_value,
            branch_value,
            branch_value,
            branch_value,
        )
        row = cursor.fetchone()
        if row:
            return int(row[0])

    if governorate:
        cursor.execute(
            """
            SELECT TOP 1 b.branch_id
            FROM dbo.branches b
            LEFT JOIN dbo.governorates g
                ON b.governorate_id = g.governorate_id
            WHERE b.organization_id = ?
              AND b.is_active = 1
              AND (
                    g.governorate_name_ar = ?
                    OR g.governorate_name_en = ?
                    OR g.governorate_code = ?
                  )
            ORDER BY b.branch_id
            """,
            organization_id,
            governorate,
            governorate,
            governorate,
        )
        row = cursor.fetchone()
        if row:
            return int(row[0])

    cursor.execute(
        """
        SELECT TOP 1 branch_id
        FROM dbo.branches
        WHERE organization_id = ?
          AND is_active = 1
        ORDER BY branch_id
        """,
        organization_id,
    )
    row = cursor.fetchone()
    return int(row[0]) if row else None


# ============================================================
# Business rules
# ============================================================

def auto_assign_organization(
    cursor: pyodbc.Cursor,
    governorate: Optional[str],
    support_type_id: int,
) -> dict:
    """
    Assign to an active organization/branch.
    Prefer a branch in the requested governorate, then lowest current load.
    """
    cursor.execute(
        """
        SELECT TOP 1
            o.organization_id,
            o.organization_name_ar,
            b.branch_id,
            b.branch_name_ar,
            COUNT(a.application_id) AS current_load
        FROM dbo.organizations o
        LEFT JOIN dbo.branches b
            ON o.organization_id = b.organization_id
           AND b.is_active = 1
        LEFT JOIN dbo.governorates g
            ON b.governorate_id = g.governorate_id
        LEFT JOIN dbo.beneficiary_applications a
            ON o.organization_id = a.organization_id
           AND a.application_status IN (N'SUBMITTED', N'ASSIGNED', N'UNDER_REVIEW')
        WHERE o.is_active = 1
        GROUP BY
            o.organization_id,
            o.organization_name_ar,
            b.branch_id,
            b.branch_name_ar,
            g.governorate_name_ar,
            g.governorate_name_en,
            g.governorate_code
        ORDER BY
            CASE
                WHEN ? IS NOT NULL
                 AND (
                        g.governorate_name_ar = ?
                        OR g.governorate_name_en = ?
                        OR g.governorate_code = ?
                     )
                THEN 0
                ELSE 1
            END,
            COUNT(a.application_id),
            o.organization_id,
            b.branch_id
        """,
        governorate,
        governorate,
        governorate,
        governorate,
    )
    row = fetch_one_dict(cursor)

    if not row:
        raise ValueError("لا توجد جمعية نشطة متاحة للتعيين.")

    return {
        "organization_id": int(row["organization_id"]),
        "organization_name_ar": row.get("organization_name_ar"),
        "branch_id": int(row["branch_id"]) if row.get("branch_id") else None,
        "assignment_reason": (
            f"تم التعيين تلقائيًا حسب المحافظة {governorate or 'غير محددة'} "
            f"ونوع الدعم {support_type_id} وبناءً على أقل ضغط طلبات."
        ),
    }


def get_available_stock(
    cursor: pyodbc.Cursor,
    organization_id: int,
    branch_id: Optional[int],
    item_id: int,
) -> float:
    """
    Prefer dbo.v_inventory_stock_balance.
    If missing, compute directly from inventory_transactions.
    """
    if _table_exists(cursor, "v_inventory_stock_balance"):
        if branch_id:
            cursor.execute(
                """
                SELECT COALESCE(available_quantity, current_stock, 0)
                FROM dbo.v_inventory_stock_balance
                WHERE organization_id = ?
                  AND branch_id = ?
                  AND item_id = ?
                """,
                organization_id,
                branch_id,
                item_id,
            )
        else:
            cursor.execute(
                """
                SELECT COALESCE(SUM(COALESCE(available_quantity, current_stock, 0)), 0)
                FROM dbo.v_inventory_stock_balance
                WHERE organization_id = ?
                  AND item_id = ?
                """,
                organization_id,
                item_id,
            )
        row = cursor.fetchone()
        return float(row[0] or 0) if row else 0.0

    if branch_id:
        cursor.execute(
            """
            SELECT COALESCE(SUM(
                CASE
                    WHEN transaction_type = N'IN' THEN quantity
                    WHEN transaction_type IN (N'OUT', N'LOSS', N'DAMAGE') THEN -quantity
                    ELSE 0
                END
            ), 0)
            FROM dbo.inventory_transactions
            WHERE organization_id = ?
              AND branch_id = ?
              AND item_id = ?
            """,
            organization_id,
            branch_id,
            item_id,
        )
    else:
        cursor.execute(
            """
            SELECT COALESCE(SUM(
                CASE
                    WHEN transaction_type = N'IN' THEN quantity
                    WHEN transaction_type IN (N'OUT', N'LOSS', N'DAMAGE') THEN -quantity
                    ELSE 0
                END
            ), 0)
            FROM dbo.inventory_transactions
            WHERE organization_id = ?
              AND item_id = ?
            """,
            organization_id,
            item_id,
        )
    row = cursor.fetchone()
    return float(row[0] or 0) if row else 0.0


def detect_application_fraud(
    cursor: pyodbc.Cursor,
    payload: dict,
    entity_id: Optional[str],
    user_id: Optional[int],
    organization_id: Optional[int],
) -> None:
    """
    Clean schema fraud detection for beneficiary applications.
    Does not use platform_users.national_id.
    """
    national_id = payload.get("national_id")
    phone = payload.get("phone")
    monthly_income = float(payload.get("monthly_income") or 0)

    if national_id:
        cursor.execute(
            """
            SELECT COUNT(*)
            FROM dbo.beneficiary_profiles bp
            WHERE bp.national_id = ?
            """,
            national_id,
        )
        if int(cursor.fetchone()[0] or 0) > 1:
            create_fraud_alert(
                cursor,
                "DUPLICATE_NATIONAL_ID",
                "APPLICATION_FRAUD",
                "HIGH",
                "beneficiary_applications",
                entity_id,
                "نفس الرقم القومي لديه بيانات مسجلة بالفعل على المنصة.",
                85,
                user_id,
                organization_id,
            )

    if phone:
        cursor.execute(
            """
            SELECT COUNT(DISTINCT beneficiary_id)
            FROM dbo.beneficiary_profiles
            WHERE phone = ?
            """,
            phone,
        )
        if int(cursor.fetchone()[0] or 0) > 1:
            create_fraud_alert(
                cursor,
                "DUPLICATE_PHONE",
                "APPLICATION_FRAUD",
                "MEDIUM",
                "beneficiary_applications",
                entity_id,
                "نفس رقم الهاتف مستخدم مع أكثر من مستفيد.",
                65,
                user_id,
                organization_id,
            )

    if monthly_income >= 20000:
        create_fraud_alert(
            cursor,
            "SUSPICIOUS_INCOME",
            "APPLICATION_FRAUD",
            "MEDIUM",
            "beneficiary_applications",
            entity_id,
            "الدخل الشهري مرتفع مقارنة بطلب المساعدة ويحتاج مراجعة.",
            55,
            user_id,
            organization_id,
        )


def detect_donation_fraud(
    cursor: pyodbc.Cursor,
    payload: dict,
    target_type: str,
    entity_id: Optional[str],
    organization_id: Optional[int],
) -> None:
    amount = float(payload.get("amount") or 0)
    phone = payload.get("phone") or payload.get("donor_phone")

    if amount <= 0:
        create_fraud_alert(
            cursor,
            "INVALID_DONATION_AMOUNT",
            "DONATION_FRAUD",
            "HIGH",
            "donations",
            entity_id,
            "قيمة التبرع يجب أن تكون أكبر من صفر.",
            90,
            organization_id=organization_id,
        )

    if phone:
        cursor.execute(
            """
            SELECT COUNT(*)
            FROM dbo.donations
            WHERE donor_phone = ?
              AND created_at >= DATEADD(MINUTE, -10, SYSUTCDATETIME())
            """,
            phone,
        )
        if int(cursor.fetchone()[0] or 0) >= 3:
            create_fraud_alert(
                cursor,
                "SUSPICIOUS_DONATION_FREQUENCY",
                "DONATION_FRAUD",
                "MEDIUM",
                "donations",
                entity_id,
                "تبرعات متكررة من نفس رقم الهاتف خلال فترة قصيرة.",
                60,
                organization_id=organization_id,
            )
