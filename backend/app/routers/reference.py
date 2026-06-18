from datetime import date, datetime
from decimal import Decimal
from typing import Any, Optional

from fastapi import APIRouter, Query

from app.database import get_connection
from app.schemas import ApiResponse

router = APIRouter()


def clean(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    return value


def rows(cursor) -> list[dict]:
    columns = [c[0] for c in cursor.description]
    return [{k: clean(v) for k, v in zip(columns, row)} for row in cursor.fetchall()]


@router.get("/governorates", response_model=ApiResponse)
def governorates():
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT governorate_id, governorate_name_ar, governorate_name_en
            FROM dbo.governorates
            WHERE is_active = 1
            ORDER BY governorate_name_ar
        """)
        data = rows(cursor)
    return ApiResponse(
        success=True,
        message="Governorates loaded from SQL Server.",
        data={"governorates": data},
    )


@router.get("/cities", response_model=ApiResponse)
def cities(governorate: Optional[str] = Query(default=None)):
    with get_connection() as conn:
        cursor = conn.cursor()
        if governorate:
            cursor.execute(
                """
                SELECT c.city_id, c.city_name_ar, c.city_name_en, g.governorate_name_ar
                FROM dbo.cities c
                JOIN dbo.governorates g ON c.governorate_id = g.governorate_id
                WHERE c.is_active = 1
                  AND (g.governorate_name_ar = ? OR g.governorate_name_en = ?)
                ORDER BY c.city_name_ar
            """,
                governorate,
                governorate,
            )
        else:
            cursor.execute("""
                SELECT c.city_id, c.city_name_ar, c.city_name_en, g.governorate_name_ar
                FROM dbo.cities c
                JOIN dbo.governorates g ON c.governorate_id = g.governorate_id
                WHERE c.is_active = 1
                ORDER BY g.governorate_name_ar, c.city_name_ar
            """)
        data = rows(cursor)
    return ApiResponse(
        success=True, message="Cities loaded from SQL Server.", data={"cities": data}
    )


@router.get("/organizations", response_model=ApiResponse)
def organizations():
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT organization_id, organization_code, organization_name_ar, organization_name_en, is_active
            FROM dbo.organizations
            WHERE is_active = 1
            ORDER BY organization_id
        """)
        data = rows(cursor)
    return ApiResponse(
        success=True,
        message="Organizations loaded from SQL Server.",
        data={"organizations": data},
    )


@router.get("/branches", response_model=ApiResponse)
def branches(
    organization_id: Optional[int] = Query(default=None),
    governorate: Optional[str] = Query(default=None),
):
    filters = ["1=1"]
    params: list[Any] = []
    if organization_id:
        filters.append("b.organization_id = ?")
        params.append(organization_id)
    if governorate:
        filters.append("b.governorate = ?")
        params.append(governorate)

    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            f"""
            SELECT b.branch_id, b.branch_code, b.branch_name_ar, b.organization_id,
                   o.organization_name_ar, g.governorate_name_ar AS governorate,
                        c.city_name_ar AS city
            FROM dbo.branches b
            JOIN dbo.organizations o ON b.organization_id = o.organization_id
            WHERE {" AND ".join(filters)}
            ORDER BY o.organization_id, b.branch_id
        """,
            params,
        )
        data = rows(cursor)
    return ApiResponse(
        success=True,
        message="Branches loaded from SQL Server.",
        data={"branches": data},
    )


@router.get("/support-types", response_model=ApiResponse)
def support_types():
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT support_type_id, support_code, support_name_ar, support_name_en
            FROM dbo.support_types
            WHERE is_active = 1
            ORDER BY support_type_id
        """)
        data = rows(cursor)
    return ApiResponse(
        success=True,
        message="Support types loaded from SQL Server.",
        data={"support_types": data},
    )


@router.get("/payment-methods", response_model=ApiResponse)
def payment_methods():
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT payment_method_id, payment_method_code, method_name_ar, method_name_en
            FROM dbo.payment_methods
            WHERE is_active = 1
            ORDER BY payment_method_id
        """)
        data = rows(cursor)
    return ApiResponse(
        success=True,
        message="Payment methods loaded from SQL Server.",
        data={"payment_methods": data},
    )


@router.get("/document-types", response_model=ApiResponse)
def document_types(support_type_id: Optional[int] = Query(default=None)):
    with get_connection() as conn:
        cursor = conn.cursor()
        if support_type_id:
            cursor.execute(
                """
                SELECT dt.document_type_id, dt.document_type_code, dt.document_type_name_ar,
                       dt.document_type_name_en, rd.is_required
                FROM dbo.document_types dt
                JOIN dbo.support_type_required_documents rd
                    ON dt.document_type_id = rd.document_type_id
                WHERE rd.support_type_id = ?
                  AND dt.is_active = 1
                ORDER BY rd.is_required DESC, dt.document_type_id
            """,
                support_type_id,
            )
        else:
            cursor.execute("""
                SELECT document_type_id, document_type_code, document_type_name_ar,
                       document_type_name_en, CAST(0 AS BIT) AS is_required
                FROM dbo.document_types
                WHERE is_active = 1
                ORDER BY document_type_id
            """)
        data = rows(cursor)
    return ApiResponse(
        success=True,
        message="Document types loaded from SQL Server.",
        data={"document_types": data},
    )


@router.get("/inventory-items", response_model=ApiResponse)
def inventory_items():
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT item_id, item_code, item_name_ar, item_name_en,
                   item_category, unit, default_unit_cost
            FROM dbo.inventory_items
            WHERE is_active = 1
            ORDER BY item_name_ar
        """)
        data = rows(cursor)
    return ApiResponse(
        success=True,
        message="Inventory items loaded from SQL Server.",
        data={"inventory_items": data},
    )


@router.get("/open-cases", response_model=ApiResponse)
def open_cases(organization_id: Optional[int] = Query(default=None)):
    with get_connection() as conn:
        cursor = conn.cursor()
        if organization_id:
            cursor.execute(
                """
                SELECT *
                FROM dbo.v_open_cases_for_donation
                WHERE organization_id = ?
                ORDER BY priority_level DESC, case_id DESC
            """,
                organization_id,
            )
        else:
            cursor.execute("""
                SELECT *
                FROM dbo.v_open_cases_for_donation
                ORDER BY priority_level DESC, case_id DESC
            """)
        data = rows(cursor)
    return ApiResponse(
        success=True, message="Open cases loaded from SQL Server.", data={"cases": data}
    )


@router.get("/reference-ids", response_model=ApiResponse)
def reference_ids(
    reference_type: str = Query(...),
    organization_id: Optional[int] = Query(default=None),
):
    reference_type = reference_type.upper()
    with get_connection() as conn:
        cursor = conn.cursor()

        if reference_type == "CASE":
            if organization_id:
                cursor.execute(
                    """
                    SELECT case_code AS reference_id, case_title AS reference_label
                    FROM dbo.charity_cases
                    WHERE organization_id = ? AND case_status = N'OPEN'
                    ORDER BY case_id DESC
                """,
                    organization_id,
                )
            else:
                cursor.execute("""
                    SELECT case_code AS reference_id, case_title AS reference_label
                    FROM dbo.charity_cases
                    WHERE case_status = N'OPEN'
                    ORDER BY case_id DESC
                """)

        elif reference_type == "APPLICATION":
            if organization_id:
                cursor.execute(
                    """
                    SELECT application_code AS reference_id, application_code AS reference_label
                    FROM dbo.beneficiary_applications
                    WHERE organization_id = ? AND application_status = N'APPROVED'
                    ORDER BY application_id DESC
                """,
                    organization_id,
                )
            else:
                cursor.execute("""
                    SELECT application_code AS reference_id, application_code AS reference_label
                    FROM dbo.beneficiary_applications
                    WHERE application_status = N'APPROVED'
                    ORDER BY application_id DESC
                """)

        elif reference_type == "DONATION":
            if organization_id:
                cursor.execute(
                    """
                    SELECT donation_code AS reference_id,
                           CONCAT(donation_code, N' - ', FORMAT(amount, 'N0'), N' ', currency) AS reference_label
                    FROM dbo.donations
                    WHERE organization_id = ?
                    ORDER BY donation_id DESC
                """,
                    organization_id,
                )
            else:
                cursor.execute("""
                    SELECT donation_code AS reference_id,
                           CONCAT(donation_code, N' - ', FORMAT(amount, 'N0'), N' ', currency) AS reference_label
                    FROM dbo.donations
                    ORDER BY donation_id DESC
                """)
        else:
            return ApiResponse(
                success=True,
                message="Manual adjustment does not require reference IDs.",
                data={"reference_ids": []},
            )

        data = rows(cursor)

    return ApiResponse(
        success=True,
        message="Reference IDs loaded from SQL Server.",
        data={"reference_ids": data},
    )


@router.get("/inventory-stock", response_model=ApiResponse)
def inventory_stock(
    organization_id: Optional[int] = Query(default=None),
    branch_id: Optional[int] = Query(default=None),
    item_id: Optional[int] = Query(default=None),
):
    filters = ["1=1"]
    params: list[Any] = []
    if organization_id:
        filters.append("organization_id = ?")
        params.append(organization_id)
    if branch_id:
        filters.append("branch_id = ?")
        params.append(branch_id)
    if item_id:
        filters.append("item_id = ?")
        params.append(item_id)

    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            f"""
            SELECT *
            FROM dbo.v_inventory_stock_balance
            WHERE {" AND ".join(filters)}
            ORDER BY organization_id, branch_id, item_name_ar
        """,
            params,
        )
        data = rows(cursor)

    return ApiResponse(
        success=True,
        message="Inventory stock balance loaded from SQL Server.",
        data={"stock": data},
    )


@router.get("/fraud-alerts", response_model=ApiResponse)
def fraud_alerts(
    organization_id: Optional[int] = Query(default=None),
    severity: Optional[str] = Query(default=None),
):
    filters = ["1=1"]
    params: list[Any] = []
    if organization_id:
        filters.append("organization_id = ?")
        params.append(organization_id)
    if severity:
        filters.append("severity = ?")
        params.append(severity)

    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            f"""
            SELECT TOP 200 *
            FROM dbo.fraud_alerts
            WHERE {" AND ".join(filters)}
            ORDER BY fraud_alert_id DESC
        """,
            params,
        )
        data = rows(cursor)

    return ApiResponse(
        success=True,
        message="Fraud alerts loaded from SQL Server.",
        data={"fraud_alerts": data},
    )


@router.get("/audit-logs", response_model=ApiResponse)
def audit_logs():
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT TOP 200 *
            FROM dbo.audit_logs
            ORDER BY audit_log_id DESC
        """)
        data = rows(cursor)
    return ApiResponse(
        success=True,
        message="Audit logs loaded from SQL Server.",
        data={"audit_logs": data},
    )


@router.get("/case-references", response_model=ApiResponse)
def case_references(organization_id: Optional[int] = Query(default=None)):
    """
    Dedicated endpoint for inventory OUT movements.
    Returns open cases tied to SQL Server and optionally filtered by organization.
    """
    filters = [
        "c.case_status IN (N'OPEN', N'Published')",
        "c.required_amount > c.collected_amount",
    ]
    params: list[Any] = []

    if organization_id:
        filters.append("c.organization_id = ?")
        params.append(organization_id)

    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            f"""
            SELECT
                c.case_id,
                c.case_code,
                c.case_title,
                c.organization_id,
                o.organization_name_ar,
                c.required_amount,
                c.collected_amount,
                (c.required_amount - c.collected_amount) AS remaining_amount,
                c.case_status
            FROM dbo.charity_cases c
            JOIN dbo.organizations o
                ON c.organization_id = o.organization_id
            WHERE {" AND ".join(filters)}
            ORDER BY c.case_id DESC
            """,
            params,
        )
        data = rows(cursor)

    return ApiResponse(
        success=True,
        message="Case references loaded from SQL Server.",
        data={"cases": data},
    )
