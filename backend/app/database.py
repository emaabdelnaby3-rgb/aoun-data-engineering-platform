import json
from typing import Any, Optional

import pyodbc

from app.config import settings
from app.business_logic import (
    auto_assign_organization,
    create_audit_log,
    detect_application_fraud,
    detect_donation_fraud,
    fetch_one_dict,
    get_available_stock,
    resolve_branch_for_organization,
    resolve_inventory_item,
    resolve_payment_method_id,
    resolve_support_type_id,
    validate_national_id,
    validate_phone,
    validate_positive,
)


def get_connection() -> pyodbc.Connection:
    server = settings.sql_server_host
    if settings.sql_server_port:
        server = f"{server},{settings.sql_server_port}"

    base = (
        f"DRIVER={{{settings.sql_server_driver}}};"
        f"SERVER={server};"
        f"DATABASE={settings.sql_server_database};"
        f"TrustServerCertificate={'yes' if settings.sql_server_trust_server_certificate else 'no'};"
    )

    if settings.sql_server_trusted_connection:
        connection_string = base + "Trusted_Connection=yes;"
    else:
        connection_string = base + f"UID={settings.sql_server_user};PWD={settings.sql_server_password};"

    return pyodbc.connect(connection_string)


def _to_json(payload: dict) -> str:
    return json.dumps(payload or {}, ensure_ascii=False, default=str)


def _next_code(cursor: pyodbc.Cursor, table: str, column: str, prefix: str, digits: int = 4) -> str:
    """
    Safe business-code generator for demo/local usage.
    Example: APP-0001, CASE-0001, DON-0001.
    """
    cursor.execute(
        f"""
        SELECT ISNULL(MAX(TRY_CONVERT(INT, RIGHT({column}, ?))), 0) + 1
        FROM dbo.{table}
        WHERE {column} LIKE ?
        """,
        digits,
        f"{prefix}-%",
    )
    number = cursor.fetchone()[0]
    return f"{prefix}-{int(number):0{digits}d}"


def _first_existing_column(cursor: pyodbc.Cursor, table: str, candidates: list[str]) -> Optional[str]:
    for column in candidates:
        cursor.execute(
            """
            SELECT 1
            FROM sys.columns
            WHERE object_id = OBJECT_ID(?)
              AND name = ?;
            """,
            f"dbo.{table}",
            column,
        )
        if cursor.fetchone():
            return column
    return None


def _insert_outbox(
    cursor: pyodbc.Cursor,
    event: dict,
    entity_name: Optional[str] = None,
    entity_id: Optional[str] = None,
    *,
    user_id: Optional[int] = None,
    beneficiary_id: Optional[int] = None,
    organization_id: Optional[int] = None,
    branch_id: Optional[int] = None,
    application_id: Optional[int] = None,
    case_id: Optional[int] = None,
    donation_id: Optional[int] = None,
    document_id: Optional[int] = None,
    inventory_transaction_id: Optional[int] = None,
    fraud_alert_id: Optional[int] = None,
) -> None:
    """
    Insert into the clean outbox table.

    This function is defensive:
    - If your table has the new FK columns, it writes them.
    - If your table still has legacy entity_name/entity_id columns, it writes them too.
    """
    payload = dict(event or {})
    event_type = payload.get("event_type") or payload.get("type") or "PLATFORM_EVENT"
    source_system = payload.get("source_system") or "unified_charity_platform"

    payload.setdefault("event_type", event_type)
    payload.setdefault("source_system", source_system)
    if entity_name is not None:
        payload.setdefault("entity_name", entity_name)
    if entity_id is not None:
        payload.setdefault("entity_id", entity_id)

    columns: list[str] = []
    values: list[Any] = []

    def add_if_exists(column: str, value: Any) -> None:
        cursor.execute(
            """
            SELECT 1
            FROM sys.columns
            WHERE object_id = OBJECT_ID('dbo.platform_event_outbox')
              AND name = ?;
            """,
            column,
        )
        if cursor.fetchone():
            columns.append(column)
            values.append(value)

    add_if_exists("event_type", event_type)
    add_if_exists("source_system", source_system)
    add_if_exists("event_status", "PENDING")
    add_if_exists("entity_name", entity_name)
    add_if_exists("entity_id", entity_id)
    add_if_exists("payload", _to_json(payload))

    add_if_exists("user_id", user_id)
    add_if_exists("beneficiary_id", beneficiary_id)
    add_if_exists("organization_id", organization_id)
    add_if_exists("branch_id", branch_id)
    add_if_exists("application_id", application_id)
    add_if_exists("case_id", case_id)
    add_if_exists("donation_id", donation_id)
    add_if_exists("document_id", document_id)
    add_if_exists("inventory_transaction_id", inventory_transaction_id)
    add_if_exists("fraud_alert_id", fraud_alert_id)

    if not columns:
        raise ValueError("platform_event_outbox table has no supported columns.")

    placeholders = ", ".join(["?"] * len(columns))
    column_sql = ", ".join(columns)
    cursor.execute(
        f"INSERT INTO dbo.platform_event_outbox ({column_sql}) VALUES ({placeholders})",
        *values,
    )


def save_event_to_sql_server(table_name: str, payload: dict) -> None:
    with get_connection() as conn:
        cursor = conn.cursor()
        _insert_outbox(cursor, payload, entity_name=table_name, entity_id=payload.get("event_id"))
        conn.commit()


def _get_role_id(cursor: pyodbc.Cursor, role_code: str) -> int:
    cursor.execute("SELECT role_id FROM dbo.roles WHERE role_code = ?", role_code)
    row = cursor.fetchone()
    if not row:
        raise ValueError(f"Role not found: {role_code}")
    return int(row[0])


def _resolve_governorate_id(cursor: pyodbc.Cursor, governorate_value: Optional[Any]) -> Optional[int]:
    if governorate_value in (None, ""):
        return None

    cursor.execute(
        """
        SELECT TOP 1 governorate_id
        FROM dbo.governorates
        WHERE governorate_id = TRY_CONVERT(INT, ?)
           OR governorate_code = ?
           OR governorate_name_ar = ?
           OR governorate_name_en = ?
        ORDER BY governorate_id;
        """,
        governorate_value,
        str(governorate_value),
        str(governorate_value),
        str(governorate_value),
    )
    row = cursor.fetchone()
    return int(row[0]) if row else None


def _resolve_city_id(
    cursor: pyodbc.Cursor,
    city_value: Optional[Any],
    governorate_id: Optional[int] = None,
) -> Optional[int]:
    if city_value in (None, ""):
        return None

    params: list[Any] = [city_value, str(city_value), str(city_value), str(city_value)]
    gov_filter = ""
    if governorate_id:
        gov_filter = "AND governorate_id = ?"
        params.append(governorate_id)

    cursor.execute(
        f"""
        SELECT TOP 1 city_id
        FROM dbo.cities
        WHERE (
                city_id = TRY_CONVERT(INT, ?)
                OR city_code = ?
                OR city_name_ar = ?
                OR city_name_en = ?
              )
          {gov_filter}
        ORDER BY city_id;
        """,
        *params,
    )
    row = cursor.fetchone()
    return int(row[0]) if row else None


def _resolve_document_type_id(cursor: pyodbc.Cursor, document_type_value: Optional[Any]) -> Optional[int]:
    if document_type_value in (None, ""):
        cursor.execute("SELECT TOP 1 document_type_id FROM dbo.document_types ORDER BY document_type_id;")
        row = cursor.fetchone()
        return int(row[0]) if row else None

    cursor.execute(
        """
        SELECT TOP 1 document_type_id
        FROM dbo.document_types
        WHERE document_type_id = TRY_CONVERT(INT, ?)
           OR document_type_code = ?
           OR document_type_name_ar = ?
           OR document_type_name_en = ?
        ORDER BY document_type_id;
        """,
        document_type_value,
        str(document_type_value),
        str(document_type_value),
        str(document_type_value),
    )
    row = cursor.fetchone()
    if not row:
        raise ValueError(f"Document type not found: {document_type_value}")
    return int(row[0])


def _find_or_create_beneficiary(cursor: pyodbc.Cursor, payload: dict) -> tuple[int, int]:
    """
    Clean schema rule:
    - national_id is stored in beneficiary_profiles, not platform_users.
    - platform_users stores login/contact data only.
    """
    national_id = payload.get("national_id")
    full_name = payload.get("full_name") or payload.get("beneficiary_name")
    phone = payload.get("phone") or payload.get("beneficiary_phone")
    email = payload.get("email")

    validate_national_id(national_id)
    if phone:
        validate_phone(phone)

    cursor.execute(
        """
        SELECT beneficiary_id, user_id
        FROM dbo.beneficiary_profiles
        WHERE national_id = ?;
        """,
        national_id,
    )
    row = cursor.fetchone()

    # Friendly validation before SQL unique-index error:
    # If email already belongs to another platform user, stop with a clear message.
    if email:
        cursor.execute(
            "SELECT TOP 1 user_id FROM dbo.platform_users WHERE email = ?;",
            email,
        )
        email_owner = cursor.fetchone()

        if email_owner:
            existing_email_user_id = int(email_owner[0])
            current_user_id = int(row[1]) if row and row[1] is not None else None

            if current_user_id != existing_email_user_id:
                raise ValueError("EMAIL_ALREADY_EXISTS")

    governorate_id = _resolve_governorate_id(cursor, payload.get("governorate_id") or payload.get("governorate"))
    city_id = _resolve_city_id(cursor, payload.get("city_id") or payload.get("city"), governorate_id)

    if row:
        beneficiary_id = int(row[0])
        user_id = int(row[1]) if row[1] is not None else None

        cursor.execute(
            """
            UPDATE dbo.beneficiary_profiles
            SET
                full_name = COALESCE(?, full_name),
                phone = COALESCE(?, phone),
                email = COALESCE(?, email),
                gender = COALESCE(?, gender),
                birth_date = COALESCE(TRY_CONVERT(date, ?), birth_date),
                governorate_id = COALESCE(?, governorate_id),
                city_id = COALESCE(?, city_id),
                address = COALESCE(?, address),
                family_size = COALESCE(TRY_CONVERT(INT, ?), family_size),
                monthly_income = COALESCE(TRY_CONVERT(DECIMAL(12,2), ?), monthly_income),
                employment_status = COALESCE(?, employment_status)
            WHERE beneficiary_id = ?;
            """,
            full_name,
            phone,
            email,
            payload.get("gender"),
            payload.get("birth_date"),
            governorate_id,
            city_id,
            payload.get("address"),
            payload.get("family_size"),
            payload.get("monthly_income"),
            payload.get("employment_status"),
            beneficiary_id,
        )

        if user_id:
            cursor.execute(
                """
                UPDATE dbo.platform_users
                SET
                    full_name = COALESCE(?, full_name),
                    phone = COALESCE(?, phone),
                    email = COALESCE(?, email)
                WHERE user_id = ?;
                """,
                full_name,
                phone,
                email,
                user_id,
            )
        return beneficiary_id, user_id

    role_id = _get_role_id(cursor, "BENEFICIARY")
    user_code = _next_code(cursor, "platform_users", "user_code", "USR")

    cursor.execute(
        """
        INSERT INTO dbo.platform_users
        (user_code, role_id, full_name, phone, email, password_hash)
        VALUES (?, ?, ?, ?, ?, ?);
        """,
        user_code,
        role_id,
        full_name,
        phone,
        email,
        "platform_auto",
    )
    cursor.execute("SELECT user_id FROM dbo.platform_users WHERE user_code = ?", user_code)
    user_id = int(cursor.fetchone()[0])

    beneficiary_code = _next_code(cursor, "beneficiary_profiles", "beneficiary_code", "BEN")

    cursor.execute(
        """
        INSERT INTO dbo.beneficiary_profiles
        (
            beneficiary_code,
            user_id,
            national_id,
            full_name,
            gender,
            birth_date,
            phone,
            email,
            governorate_id,
            city_id,
            address,
            family_size,
            monthly_income,
            employment_status
        )
        VALUES (?, ?, ?, ?, ?, TRY_CONVERT(date, ?), ?, ?, ?, ?, ?, TRY_CONVERT(INT, ?), TRY_CONVERT(DECIMAL(12,2), ?), ?);
        """,
        beneficiary_code,
        user_id,
        national_id,
        full_name,
        payload.get("gender"),
        payload.get("birth_date"),
        phone,
        email,
        governorate_id,
        city_id,
        payload.get("address"),
        payload.get("family_size"),
        payload.get("monthly_income"),
        payload.get("employment_status"),
    )
    cursor.execute("SELECT beneficiary_id FROM dbo.beneficiary_profiles WHERE beneficiary_code = ?", beneficiary_code)
    beneficiary_id = int(cursor.fetchone()[0])

    return beneficiary_id, user_id


def _ensure_registration(
    cursor: pyodbc.Cursor,
    beneficiary_id: int,
    organization_id: int,
    branch_id: Optional[int],
    notes: Optional[str] = None,
) -> None:
    cursor.execute(
        """
        SELECT 1
        FROM dbo.beneficiary_org_registrations
        WHERE beneficiary_id = ?
          AND organization_id = ?;
        """,
        beneficiary_id,
        organization_id,
    )
    if cursor.fetchone():
        return

    cursor.execute(
        """
        INSERT INTO dbo.beneficiary_org_registrations
        (beneficiary_id, organization_id, branch_id, registration_channel, notes)
        VALUES (?, ?, ?, N'PLATFORM', ?);
        """,
        beneficiary_id,
        organization_id,
        branch_id,
        notes or "Registered automatically from platform API",
    )


def _resolve_application_id(cursor: pyodbc.Cursor, value: Any) -> Optional[int]:
    if value in (None, ""):
        return None
    cursor.execute(
        """
        SELECT TOP 1 application_id
        FROM dbo.beneficiary_applications
        WHERE application_id = TRY_CONVERT(INT, ?)
           OR application_code = ?;
        """,
        value,
        str(value),
    )
    row = cursor.fetchone()
    return int(row[0]) if row else None


def _resolve_case_id(cursor: pyodbc.Cursor, value: Any) -> Optional[int]:
    if value in (None, ""):
        return None
    cursor.execute(
        """
        SELECT TOP 1 case_id
        FROM dbo.charity_cases
        WHERE case_id = TRY_CONVERT(INT, ?)
           OR case_code = ?;
        """,
        value,
        str(value),
    )
    row = cursor.fetchone()
    return int(row[0]) if row else None


def save_application_event(payload: dict, event: dict) -> dict:
    """
    Create/update beneficiary and submit a beneficiary application using clean DB schema.
    """
    with get_connection() as conn:
        cursor = conn.cursor()

        support_type_id = resolve_support_type_id(
            cursor,
            payload.get("support_requested") or payload.get("support_type"),
            payload.get("support_type_id"),
        )

        beneficiary_id, user_id = _find_or_create_beneficiary(cursor, payload)

        organization_id = payload.get("organization_id")
        branch_id = payload.get("branch_id")

        if organization_id:
            organization_id = int(organization_id)
            cursor.execute("SELECT is_active FROM dbo.organizations WHERE organization_id = ?", organization_id)
            org = cursor.fetchone()
            if not org or not bool(org[0]):
                raise ValueError("الجمعية غير موجودة أو غير نشطة.")
            branch_id = resolve_branch_for_organization(
                cursor,
                organization_id,
                branch_id,
                payload.get("governorate") or payload.get("governorate_id"),
            )
            assignment_reason = "تم اختيار الجمعية من المستخدم أو الواجهة."
        else:
            assignment = auto_assign_organization(
                cursor,
                payload.get("governorate") or payload.get("governorate_id"),
                int(support_type_id),
            )
            organization_id = int(assignment["organization_id"])
            branch_id = assignment.get("branch_id")
            assignment_reason = assignment.get("assignment_reason")

        _ensure_registration(cursor, beneficiary_id, organization_id, branch_id, assignment_reason)

        requested_amount = (
            payload.get("requested_amount")
            or payload.get("amount")
            or payload.get("estimated_monthly_support")
            or 0
        )

        application_code = _next_code(cursor, "beneficiary_applications", "application_code", "APP")
        status = payload.get("application_status") or "SUBMITTED"
        priority_level = payload.get("priority_level") or "MEDIUM"

        cursor.execute(
            """
            INSERT INTO dbo.beneficiary_applications
            (
                application_code,
                beneficiary_id,
                organization_id,
                branch_id,
                support_type_id,
                requested_amount,
                application_status,
                priority_level,
                assignment_reason,
                admin_notes
            )
            VALUES (?, ?, ?, ?, ?, TRY_CONVERT(DECIMAL(12,2), ?), ?, ?, ?, ?);
            """,
            application_code,
            beneficiary_id,
            organization_id,
            branch_id,
            int(support_type_id),
            requested_amount,
            status,
            priority_level,
            assignment_reason,
            payload.get("notes") or payload.get("admin_notes"),
        )
        cursor.execute("SELECT application_id FROM dbo.beneficiary_applications WHERE application_code = ?", application_code)
        application_id = int(cursor.fetchone()[0])

        try:
            detect_application_fraud(cursor, payload, application_code, user_id, organization_id)
        except Exception as exc:
            event.setdefault("payload", {})["fraud_detection_warning"] = str(exc)

        event.setdefault("payload", {})
        event["payload"].update(
            {
                "application_code": application_code,
                "application_id": application_id,
                "beneficiary_id": beneficiary_id,
                "assigned_organization_id": organization_id,
                "branch_id": branch_id,
                "support_type_id": int(support_type_id),
                "assignment_reason": assignment_reason,
            }
        )
        event.setdefault("event_type", "BENEFICIARY_APPLICATION_SUBMITTED")

        _insert_outbox(
            cursor,
            event,
            "beneficiary_applications",
            application_code,
            user_id=user_id,
            beneficiary_id=beneficiary_id,
            organization_id=organization_id,
            branch_id=branch_id,
            application_id=application_id,
        )
        create_audit_log(
            cursor,
            "APPLICATION_SUBMITTED",
            "beneficiary_applications",
            application_code,
            new_value=event["payload"],
            actor_user_id=user_id,
        )

        conn.commit()

        return {
            "application_id": application_id,
            "application_code": application_code,
            "beneficiary_id": beneficiary_id,
            "organization_id": organization_id,
            "branch_id": branch_id,
            "support_type_id": int(support_type_id),
            "assignment_reason": assignment_reason,
            "application_status": status,
        }


def save_application_review_event(application_code: str, payload: dict, event: dict) -> dict:
    decision = (payload.get("decision") or "").upper()
    if decision not in ("APPROVED", "REJECTED", "UNDER_REVIEW"):
        raise ValueError("قرار المراجعة يجب أن يكون APPROVED أو REJECTED أو UNDER_REVIEW.")

    if decision == "REJECTED" and not payload.get("notes"):
        raise ValueError("سبب الرفض مطلوب عند رفض الطلب.")

    with get_connection() as conn:
        cursor = conn.cursor()

        cursor.execute(
            """
            SELECT
                application_id,
                beneficiary_id,
                organization_id,
                branch_id,
                support_type_id,
                requested_amount
            FROM dbo.beneficiary_applications
            WHERE application_code = ?;
            """,
            application_code,
        )
        app_row = fetch_one_dict(cursor)
        if not app_row:
            raise ValueError(f"Application not found: {application_code}")

        application_id = int(app_row["application_id"])
        beneficiary_id = int(app_row["beneficiary_id"])
        organization_id = int(app_row["organization_id"])
        branch_id = int(app_row["branch_id"]) if app_row.get("branch_id") is not None else None
        support_type_id = int(app_row["support_type_id"])

        cursor.execute(
            """
            UPDATE dbo.beneficiary_applications
            SET application_status = ?,
                admin_notes = ?,
                reviewed_at = SYSDATETIME()
            WHERE application_id = ?;
            """,
            decision,
            payload.get("notes"),
            application_id,
        )

        created_case = None
        if decision == "APPROVED" and payload.get("create_case"):
            required_amount = validate_positive(
                payload.get("required_amount") or app_row.get("requested_amount") or 0,
                "المبلغ المطلوب للحالة",
            )
            case_code = _next_code(cursor, "charity_cases", "case_code", "CASE")
            cursor.execute(
                """
                INSERT INTO dbo.charity_cases
                (
                    case_code,
                    application_id,
                    beneficiary_id,
                    organization_id,
                    branch_id,
                    support_type_id,
                    case_title,
                    case_description,
                    required_amount,
                    collected_amount,
                    case_status,
                    priority_level,
                    published_at
                )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, N'OPEN', ?, SYSDATETIME());
                """,
                case_code,
                application_id,
                beneficiary_id,
                organization_id,
                branch_id,
                support_type_id,
                payload.get("case_title") or f"حالة من الطلب {application_code}",
                payload.get("notes") or payload.get("case_description") or "",
                required_amount,
                payload.get("priority_level") or "MEDIUM",
            )
            cursor.execute("SELECT case_id FROM dbo.charity_cases WHERE case_code = ?", case_code)
            case_id = int(cursor.fetchone()[0])
            created_case = {"case_id": case_id, "case_code": case_code}

            _insert_outbox(
                cursor,
                {"event_type": "CHARITY_CASE_CREATED", "payload": {"case_code": case_code, "application_code": application_code}},
                "charity_cases",
                case_code,
                beneficiary_id=beneficiary_id,
                organization_id=organization_id,
                branch_id=branch_id,
                application_id=application_id,
                case_id=case_id,
            )

        event.setdefault("payload", {})
        event["payload"].update(
            {
                "application_code": application_code,
                "application_id": application_id,
                "decision": decision,
                "created_case": created_case,
            }
        )
        event.setdefault("event_type", "BENEFICIARY_APPLICATION_REVIEWED")

        _insert_outbox(
            cursor,
            event,
            "beneficiary_applications",
            application_code,
            beneficiary_id=beneficiary_id,
            organization_id=organization_id,
            branch_id=branch_id,
            application_id=application_id,
        )
        create_audit_log(cursor, "APPLICATION_REVIEWED", "beneficiary_applications", application_code, new_value=event["payload"])

        conn.commit()
        return {
            "application_id": application_id,
            "application_code": application_code,
            "application_status": decision,
            "created_case": created_case,
        }


def save_case_event(payload: dict, event: dict) -> dict:
    """
    Create a case from an existing application.
    This protects Beneficiary 360 consistency.
    """
    with get_connection() as conn:
        cursor = conn.cursor()

        application_value = payload.get("application_id") or payload.get("application_code")
        application_id = _resolve_application_id(cursor, application_value)
        if not application_id:
            raise ValueError("لازم تختاري طلب موجود لإنشاء حالة. ابعتي application_id أو application_code.")

        cursor.execute(
            """
            SELECT
                application_id,
                application_code,
                beneficiary_id,
                organization_id,
                branch_id,
                support_type_id,
                requested_amount,
                application_status
            FROM dbo.beneficiary_applications
            WHERE application_id = ?;
            """,
            application_id,
        )
        app_row = fetch_one_dict(cursor)
        if not app_row:
            raise ValueError("الطلب غير موجود.")

        required_amount = validate_positive(
            payload.get("required_amount") or payload.get("estimated_monthly_support") or app_row.get("requested_amount") or 0,
            "المبلغ المطلوب",
        )

        case_code = _next_code(cursor, "charity_cases", "case_code", "CASE")
        title = payload.get("title") or payload.get("case_title") or f"حالة من الطلب {app_row['application_code']}"

        cursor.execute(
            """
            INSERT INTO dbo.charity_cases
            (
                case_code,
                application_id,
                beneficiary_id,
                organization_id,
                branch_id,
                support_type_id,
                case_title,
                case_description,
                required_amount,
                collected_amount,
                case_status,
                priority_level,
                published_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, N'OPEN', ?, SYSDATETIME());
            """,
            case_code,
            int(app_row["application_id"]),
            int(app_row["beneficiary_id"]),
            int(app_row["organization_id"]),
            int(app_row["branch_id"]) if app_row.get("branch_id") is not None else None,
            int(app_row["support_type_id"]),
            title,
            payload.get("description") or payload.get("case_description") or "",
            required_amount,
            payload.get("priority_level") or "MEDIUM",
        )
        cursor.execute("SELECT case_id FROM dbo.charity_cases WHERE case_code = ?", case_code)
        case_id = int(cursor.fetchone()[0])

        cursor.execute(
            """
            UPDATE dbo.beneficiary_applications
            SET application_status = CASE
                    WHEN application_status IN (N'SUBMITTED', N'ASSIGNED', N'UNDER_REVIEW')
                    THEN N'APPROVED'
                    ELSE application_status
                END,
                reviewed_at = COALESCE(reviewed_at, SYSDATETIME())
            WHERE application_id = ?;
            """,
            application_id,
        )

        event.setdefault("payload", {})
        event["payload"].update(
            {
                "case_code": case_code,
                "case_id": case_id,
                "application_id": int(app_row["application_id"]),
                "application_code": app_row["application_code"],
                "beneficiary_id": int(app_row["beneficiary_id"]),
                "organization_id": int(app_row["organization_id"]),
                "branch_id": int(app_row["branch_id"]) if app_row.get("branch_id") is not None else None,
                "support_type_id": int(app_row["support_type_id"]),
            }
        )
        event.setdefault("event_type", "CHARITY_CASE_CREATED")

        _insert_outbox(
            cursor,
            event,
            "charity_cases",
            case_code,
            beneficiary_id=int(app_row["beneficiary_id"]),
            organization_id=int(app_row["organization_id"]),
            branch_id=int(app_row["branch_id"]) if app_row.get("branch_id") is not None else None,
            application_id=int(app_row["application_id"]),
            case_id=case_id,
        )
        create_audit_log(cursor, "CASE_CREATED", "charity_cases", case_code, new_value=event["payload"])

        conn.commit()
        return {
            "case_id": case_id,
            "case_code": case_code,
            "application_id": int(app_row["application_id"]),
            "beneficiary_id": int(app_row["beneficiary_id"]),
            "organization_id": int(app_row["organization_id"]),
            "branch_id": int(app_row["branch_id"]) if app_row.get("branch_id") is not None else None,
        }


def save_donation_event(payload: dict, event: dict) -> dict:
    phone = payload.get("phone") or payload.get("donor_phone")
    if phone:
        validate_phone(phone)

    amount = validate_positive(payload.get("amount"), "مبلغ التبرع")

    with get_connection() as conn:
        cursor = conn.cursor()

        if payload.get("idempotency_key"):
            cursor.execute("SELECT donation_code FROM dbo.donations WHERE idempotency_key = ?", payload["idempotency_key"])
            duplicate = cursor.fetchone()
            if duplicate:
                return {"duplicate": True, "donation_code": duplicate[0]}

        payment_method_id = resolve_payment_method_id(cursor, payload.get("payment_method_id") or payload.get("payment_method"))

        target_type = (payload.get("donation_target_type") or "").upper()
        case_id = _resolve_case_id(cursor, payload.get("case_id") or payload.get("case_code"))
        organization_id: Optional[int] = None

        if case_id:
            target_type = "CASE"
            cursor.execute(
                """
                SELECT case_id, case_code, organization_id, required_amount, case_status
                FROM dbo.charity_cases
                WHERE case_id = ?;
                """,
                case_id,
            )
            case_row = fetch_one_dict(cursor)
            if not case_row:
                raise ValueError("الحالة غير موجودة.")
            if case_row["case_status"] not in ("OPEN", "PUBLISHED"):
                raise ValueError("لا يمكن التبرع لحالة مغلقة.")

            organization_id = int(case_row["organization_id"])

        elif target_type == "ORGANIZATION_GENERAL" or payload.get("organization_id"):
            target_type = "ORGANIZATION_GENERAL"
            organization_id = int(payload.get("organization_id") or 0)
            if not organization_id:
                raise ValueError("التبرع العام لجمعية لازم يكون فيه organization_id.")
            cursor.execute("SELECT is_active FROM dbo.organizations WHERE organization_id = ?", organization_id)
            org = cursor.fetchone()
            if not org or not bool(org[0]):
                raise ValueError("الجمعية المختارة غير موجودة أو غير نشطة.")
            case_id = None

        else:
            target_type = "PLATFORM_GENERAL"
            organization_id = None
            case_id = None

        donation_code = _next_code(cursor, "donations", "donation_code", "DON")

        cursor.execute(
            """
            INSERT INTO dbo.donations
            (
                donation_code,
                donor_user_id,
                donor_name,
                donor_phone,
                donor_email,
                organization_id,
                case_id,
                payment_method_id,
                amount,
                currency,
                donation_target_type,
                donation_status,
                payment_status,
                campaign_name,
                general_notes,
                idempotency_key
            )
            VALUES (?, TRY_CONVERT(INT, ?), ?, ?, ?, ?, ?, ?, ?, ?, ?, N'COMPLETED', N'SUCCESS', ?, ?, ?);
            """,
            donation_code,
            payload.get("donor_user_id"),
            payload.get("donor_name"),
            phone,
            payload.get("email") or payload.get("donor_email"),
            organization_id,
            case_id,
            payment_method_id,
            amount,
            payload.get("currency") or "EGP",
            target_type,
            payload.get("campaign_name"),
            payload.get("general_notes") or payload.get("notes"),
            payload.get("idempotency_key"),
        )
        cursor.execute("SELECT donation_id FROM dbo.donations WHERE donation_code = ?", donation_code)
        donation_id = int(cursor.fetchone()[0])

        new_case_status = None
        if target_type == "CASE" and case_id:
            # Idempotent recalculation. Safe even if a trigger already updates collected_amount.
            cursor.execute(
                """
                SELECT
                    c.required_amount,
                    COALESCE(SUM(CASE
                        WHEN d.donation_status = N'COMPLETED'
                         AND d.payment_status = N'SUCCESS'
                        THEN d.amount ELSE 0 END), 0) AS collected_amount
                FROM dbo.charity_cases c
                LEFT JOIN dbo.donations d
                    ON c.case_id = d.case_id
                WHERE c.case_id = ?
                GROUP BY c.required_amount;
                """,
                case_id,
            )
            c = fetch_one_dict(cursor)
            collected = float(c["collected_amount"] or 0)
            required = float(c["required_amount"] or 0)
            new_case_status = "CLOSED" if required > 0 and collected >= required else "OPEN"

            cursor.execute(
                """
                UPDATE dbo.charity_cases
                SET collected_amount = ?,
                    case_status = ?,
                    closed_at = CASE WHEN ? = N'CLOSED' THEN COALESCE(closed_at, SYSDATETIME()) ELSE closed_at END
                WHERE case_id = ?;
                """,
                collected,
                new_case_status,
                new_case_status,
                case_id,
            )

        try:
            detect_donation_fraud(cursor, payload, target_type, donation_code, organization_id)
        except Exception as exc:
            event.setdefault("payload", {})["fraud_detection_warning"] = str(exc)

        event_type = (
            "CASE_DONATION_RECORDED"
            if target_type == "CASE"
            else "ORGANIZATION_GENERAL_DONATION_RECORDED"
            if target_type == "ORGANIZATION_GENERAL"
            else "PLATFORM_GENERAL_DONATION_RECORDED"
        )

        event["event_type"] = event.get("event_type") or event_type
        event.setdefault("payload", {})
        event["payload"].update(
            {
                "donation_code": donation_code,
                "donation_id": donation_id,
                "donation_target_type": target_type,
                "case_id": case_id,
                "organization_id": organization_id,
                "case_status": new_case_status,
            }
        )

        _insert_outbox(
            cursor,
            event,
            "donations",
            donation_code,
            organization_id=organization_id,
            case_id=case_id,
            donation_id=donation_id,
        )
        create_audit_log(cursor, event_type, "donations", donation_code, new_value=event["payload"])

        conn.commit()
        return {
            "donation_id": donation_id,
            "donation_code": donation_code,
            "donation_target_type": target_type,
            "case_id": case_id,
            "organization_id": organization_id,
            "case_status": new_case_status,
        }


def save_inventory_event(payload: dict, event: dict) -> dict:
    quantity = validate_positive(payload.get("quantity"), "الكمية")
    transaction_type = (payload.get("transaction_type") or "").upper()

    if transaction_type not in ("IN", "OUT", "LOSS", "DAMAGE", "MANUAL_ADJUSTMENT"):
        raise ValueError("نوع حركة المخزون يجب أن يكون IN أو OUT أو LOSS أو DAMAGE أو MANUAL_ADJUSTMENT.")

    organization_id = int(payload.get("organization_id"))

    with get_connection() as conn:
        cursor = conn.cursor()

        cursor.execute("SELECT is_active FROM dbo.organizations WHERE organization_id = ?", organization_id)
        org = cursor.fetchone()
        if not org or not bool(org[0]):
            raise ValueError("الجمعية غير موجودة أو غير نشطة.")

        branch_id = resolve_branch_for_organization(
            cursor,
            organization_id,
            payload.get("branch_id"),
            payload.get("governorate"),
        )

        item = resolve_inventory_item(cursor, payload.get("item_id") or payload.get("item_code") or payload.get("item_name"))
        item_id = int(item["item_id"])

        unit_cost = payload.get("unit_cost")
        if unit_cost is None:
            unit_cost = float(item.get("default_unit_cost") or 0)

        case_id = _resolve_case_id(cursor, payload.get("case_id") or payload.get("case_code"))
        application_id = _resolve_application_id(cursor, payload.get("application_id") or payload.get("application_code"))

        if transaction_type == "OUT":
            if not case_id:
                # If reference type is CASE, try resolving reference_id as case id/code.
                if (payload.get("reference_type") or "").upper() == "CASE":
                    case_id = _resolve_case_id(cursor, payload.get("reference_id"))

            if not case_id:
                raise ValueError("حركة OUT لازم تكون مرتبطة بحالة case_id أو case_code.")

            cursor.execute(
                """
                SELECT organization_id, branch_id, application_id
                FROM dbo.charity_cases
                WHERE case_id = ?;
                """,
                case_id,
            )
            c = fetch_one_dict(cursor)
            if not c:
                raise ValueError("الحالة المرتبطة بحركة المخزون غير موجودة.")

            if int(c["organization_id"]) != organization_id:
                raise ValueError("حركة المخزون OUT لازم تكون من نفس جمعية الحالة.")

            if application_id is None and c.get("application_id") is not None:
                application_id = int(c["application_id"])

            available = get_available_stock(cursor, organization_id, branch_id, item_id)
            if quantity > available:
                raise ValueError(f"الكمية المطلوبة أكبر من المخزون المتاح. المتاح: {available}")

        if transaction_type in ("LOSS", "DAMAGE") and not payload.get("notes"):
            raise ValueError("حركات LOSS/DAMAGE لازم يكون معها ملاحظات توضح السبب.")

        transaction_code = _next_code(cursor, "inventory_transactions", "transaction_code", "INV")

        reference_type = payload.get("reference_type")
        reference_id = payload.get("reference_id")
        if transaction_type == "OUT" and case_id:
            reference_type = reference_type or "CASE"
            reference_id = reference_id or str(case_id)
        elif transaction_type in ("LOSS", "DAMAGE"):
            reference_type = reference_type or transaction_type
        elif transaction_type in ("IN", "MANUAL_ADJUSTMENT"):
            reference_type = reference_type or "MANUAL_ADJUSTMENT"

        cursor.execute(
            """
            INSERT INTO dbo.inventory_transactions
            (
                transaction_code,
                organization_id,
                branch_id,
                item_id,
                transaction_type,
                quantity,
                unit_cost,
                case_id,
                application_id,
                donation_id,
                reference_type,
                reference_id,
                notes
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, TRY_CONVERT(INT, ?), ?, ?, ?);
            """,
            transaction_code,
            organization_id,
            branch_id,
            item_id,
            transaction_type,
            quantity,
            unit_cost,
            case_id,
            application_id,
            payload.get("donation_id"),
            reference_type,
            reference_id,
            payload.get("notes") or "Created from platform API",
        )
        cursor.execute("SELECT transaction_id FROM dbo.inventory_transactions WHERE transaction_code = ?", transaction_code)
        transaction_id = int(cursor.fetchone()[0])

        event.setdefault("payload", {})
        event["payload"].update(
            {
                "transaction_code": transaction_code,
                "transaction_id": transaction_id,
                "organization_id": organization_id,
                "branch_id": branch_id,
                "item_id": item_id,
                "unit_cost": float(unit_cost),
                "total_cost": float(unit_cost) * float(quantity),
                "case_id": case_id,
                "application_id": application_id,
            }
        )
        event.setdefault("event_type", "INVENTORY_TRANSACTION_RECORDED")

        _insert_outbox(
            cursor,
            event,
            "inventory_transactions",
            transaction_code,
            organization_id=organization_id,
            branch_id=branch_id,
            application_id=application_id,
            case_id=case_id,
            inventory_transaction_id=transaction_id,
        )
        create_audit_log(cursor, "INVENTORY_TRANSACTION_RECORDED", "inventory_transactions", transaction_code, new_value=event["payload"])

        conn.commit()
        return {
            "transaction_id": transaction_id,
            "transaction_code": transaction_code,
            "organization_id": organization_id,
            "branch_id": branch_id,
            "item_id": item_id,
            "unit_cost": float(unit_cost),
            "total_cost": float(unit_cost) * float(quantity),
            "case_id": case_id,
            "application_id": application_id,
        }


def save_document_upload_event(payload: dict, event: dict) -> dict:
    with get_connection() as conn:
        cursor = conn.cursor()

        application_id = _resolve_application_id(cursor, payload.get("application_id") or payload.get("application_code"))
        case_id = _resolve_case_id(cursor, payload.get("case_id") or payload.get("case_code"))

        beneficiary_id = payload.get("beneficiary_id")

        if application_id:
            cursor.execute(
                """
                SELECT beneficiary_id
                FROM dbo.beneficiary_applications
                WHERE application_id = ?;
                """,
                application_id,
            )
            row = cursor.fetchone()
            if not row:
                raise ValueError("الطلب المرتبط بالمستند غير موجود.")
            beneficiary_id = int(row[0])

        elif case_id:
            cursor.execute(
                """
                SELECT beneficiary_id, application_id
                FROM dbo.charity_cases
                WHERE case_id = ?;
                """,
                case_id,
            )
            row = cursor.fetchone()
            if not row:
                raise ValueError("الحالة المرتبطة بالمستند غير موجودة.")
            beneficiary_id = int(row[0])
            application_id = int(row[1]) if row[1] is not None else None

        if not beneficiary_id:
            raise ValueError("لازم المستند يكون مرتبط بمستفيد أو طلب أو حالة.")

        document_type_id = _resolve_document_type_id(
            cursor,
            payload.get("document_type_id") or payload.get("document_type_code") or payload.get("document_type"),
        )

        document_code = payload.get("document_id") or payload.get("document_code") or _next_code(
            cursor, "beneficiary_documents", "document_code", "DOC"
        )

        cursor.execute(
            """
            INSERT INTO dbo.beneficiary_documents
            (
                document_code,
                beneficiary_id,
                application_id,
                case_id,
                document_type_id,
                original_file_name,
                stored_file_name,
                content_type,
                file_size_kb,
                bucket_name,
                object_key,
                storage_path,
                file_url,
                document_status
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            document_code,
            int(beneficiary_id),
            application_id,
            case_id,
            document_type_id,
            payload.get("original_file_name"),
            payload.get("stored_file_name"),
            payload.get("content_type"),
            payload.get("file_size_kb"),
            payload.get("bucket_name"),
            payload.get("object_key"),
            payload.get("storage_path"),
            payload.get("file_url"),
            payload.get("document_status") or "UPLOADED",
        )
        cursor.execute("SELECT document_id FROM dbo.beneficiary_documents WHERE document_code = ?", document_code)
        document_id = int(cursor.fetchone()[0])

        event.setdefault("payload", {})
        event["payload"].update(
            {
                "document_id": document_id,
                "document_code": document_code,
                "beneficiary_id": int(beneficiary_id),
                "application_id": application_id,
                "case_id": case_id,
                "document_type_id": document_type_id,
            }
        )
        event.setdefault("event_type", "BENEFICIARY_DOCUMENT_UPLOADED")

        _insert_outbox(
            cursor,
            event,
            "beneficiary_documents",
            document_code,
            beneficiary_id=int(beneficiary_id),
            application_id=application_id,
            case_id=case_id,
            document_id=document_id,
        )
        create_audit_log(cursor, "DOCUMENT_UPLOADED", "beneficiary_documents", document_code, new_value=event["payload"])

        conn.commit()
        return {
            "document_saved": True,
            "document_id": document_id,
            "document_code": document_code,
            "beneficiary_id": int(beneficiary_id),
            "application_id": application_id,
            "case_id": case_id,
        }
