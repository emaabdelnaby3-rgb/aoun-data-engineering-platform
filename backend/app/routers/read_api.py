from datetime import date, datetime
from decimal import Decimal
from typing import Any

from fastapi import APIRouter, Query

from app.database import get_connection
from app.schemas import ApiResponse


router = APIRouter()


def clean_value(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    return value


def rows_to_dicts(cursor) -> list[dict]:
    columns = [column[0] for column in cursor.description]
    return [
        {column: clean_value(value) for column, value in zip(columns, row)}
        for row in cursor.fetchall()
    ]


@router.get("/organizations", response_model=ApiResponse)
def list_organizations():
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT
                o.organization_id,
                o.organization_code,
                o.organization_name_ar,
                o.organization_name_en,
                o.phone,
                o.email,
                o.address,
                o.is_active,
                COUNT(DISTINCT b.branch_id) AS branches_count,
                COUNT(DISTINCT c.case_id) AS cases_count,
                SUM(CASE WHEN c.case_status = N'OPEN' THEN 1 ELSE 0 END) AS open_cases_count,
                SUM(CASE WHEN c.case_status IN (N'CLOSED', N'COMPLETED') THEN 1 ELSE 0 END) AS closed_cases_count,
                COALESCE(SUM(c.required_amount), 0) AS total_required_amount,
                COALESCE(SUM(c.collected_amount), 0) AS total_collected_amount
            FROM dbo.organizations o
            LEFT JOIN dbo.branches b ON o.organization_id = b.organization_id
            LEFT JOIN dbo.charity_cases c ON o.organization_id = c.organization_id
            GROUP BY
                o.organization_id,
                o.organization_code,
                o.organization_name_ar,
                o.organization_name_en,
                o.phone,
                o.email,
                o.address,
                o.is_active
            ORDER BY o.organization_id;
            """
        )
        organizations = rows_to_dicts(cursor)

    return ApiResponse(
        success=True,
        message="Organizations read from SQL Server.",
        data={"count": len(organizations), "organizations": organizations},
    )


@router.get("/support-types", response_model=ApiResponse)
def list_support_types():
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT
                support_type_id,
                support_code,
                support_name_ar,
                support_name_en,
                is_cash_support,
                is_inventory_support,
                is_active
            FROM dbo.support_types
            ORDER BY support_type_id;
            """
        )
        support_types = rows_to_dicts(cursor)

    return ApiResponse(
        success=True,
        message="Support types read from SQL Server.",
        data={"count": len(support_types), "support_types": support_types},
    )


@router.get("/applications", response_model=ApiResponse)
def list_applications(
    status: str | None = Query(default=None),
    organization_id: int | None = Query(default=None),
    support_type_id: int | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=1000),
):
    filters = []
    params: list[Any] = []

    if status:
        filters.append("a.application_status = ?")
        params.append(status)

    if organization_id:
        filters.append("a.organization_id = ?")
        params.append(organization_id)

    if support_type_id:
        filters.append("a.support_type_id = ?")
        params.append(support_type_id)

    where_clause = "WHERE " + " AND ".join(filters) if filters else ""

    query = f"""
        SELECT TOP ({limit})
            a.application_id,
            a.application_code,
            a.beneficiary_id,
            bp.beneficiary_code,
            bp.full_name AS beneficiary_name,
            bp.national_id,
            bp.phone,
            bp.email,
            g.governorate_name_ar AS governorate,
            ci.city_name_ar AS city,
            a.organization_id,
            o.organization_name_ar,
            a.branch_id,
            br.branch_name_ar,
            a.support_type_id,
            st.support_name_ar,
            a.requested_amount,
            a.application_status,
            a.priority_level,
            a.submitted_at,
            a.reviewed_by,
            a.reviewed_at,
            a.admin_notes,
            a.assignment_reason
        FROM dbo.beneficiary_applications a
        JOIN dbo.beneficiary_profiles bp ON a.beneficiary_id = bp.beneficiary_id
        LEFT JOIN dbo.governorates g ON bp.governorate_id = g.governorate_id
        LEFT JOIN dbo.cities ci ON bp.city_id = ci.city_id
        LEFT JOIN dbo.organizations o ON a.organization_id = o.organization_id
        LEFT JOIN dbo.branches br ON a.branch_id = br.branch_id
        JOIN dbo.support_types st ON a.support_type_id = st.support_type_id
        {where_clause}
        ORDER BY a.submitted_at DESC;
    """

    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(query, params)
        applications = rows_to_dicts(cursor)

    return ApiResponse(
        success=True,
        message="Applications read from SQL Server.",
        data={"count": len(applications), "applications": applications},
    )


@router.get("/cases", response_model=ApiResponse)
def list_cases(
    status: str | None = Query(default=None),
    organization_id: int | None = Query(default=None),
    support_type_id: int | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=1000),
):
    filters = []
    params: list[Any] = []

    if status:
        filters.append("c.case_status = ?")
        params.append(status)

    if organization_id:
        filters.append("c.organization_id = ?")
        params.append(organization_id)

    if support_type_id:
        filters.append("c.support_type_id = ?")
        params.append(support_type_id)

    where_clause = "WHERE " + " AND ".join(filters) if filters else ""

    query = f"""
        SELECT TOP ({limit})
            c.case_id,
            c.case_code,
            c.application_id,
            c.beneficiary_id,
            bp.beneficiary_code,
            bp.full_name AS beneficiary_name,
            bp.national_id,
            bp.phone,
            g.governorate_name_ar AS governorate,
            ci.city_name_ar AS city,
            c.organization_id,
            o.organization_name_ar,
            c.branch_id,
            br.branch_name_ar,
            c.support_type_id,
            st.support_name_ar,
            c.case_title,
            c.case_description,
            c.required_amount,
            c.collected_amount,
            CASE WHEN c.required_amount > 0 THEN CAST((c.collected_amount / c.required_amount) * 100 AS DECIMAL(9,2)) ELSE 0 END AS coverage_percent,
            c.case_status,
            c.priority_level,
            c.published_at,
            c.closed_at,
            c.created_at
        FROM dbo.charity_cases c
        JOIN dbo.beneficiary_profiles bp ON c.beneficiary_id = bp.beneficiary_id
        LEFT JOIN dbo.governorates g ON bp.governorate_id = g.governorate_id
        LEFT JOIN dbo.cities ci ON bp.city_id = ci.city_id
        JOIN dbo.organizations o ON c.organization_id = o.organization_id
        LEFT JOIN dbo.branches br ON c.branch_id = br.branch_id
        JOIN dbo.support_types st ON c.support_type_id = st.support_type_id
        {where_clause}
        ORDER BY c.created_at DESC;
    """

    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(query, params)
        cases = rows_to_dicts(cursor)

    return ApiResponse(
        success=True,
        message="Cases read from SQL Server.",
        data={"count": len(cases), "cases": cases},
    )


@router.get("/donations", response_model=ApiResponse)
def list_donations(
    organization_id: int | None = Query(default=None),
    case_code: str | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=1000),
):
    filters = []
    params: list[Any] = []

    if organization_id:
        filters.append("d.organization_id = ?")
        params.append(organization_id)

    if case_code:
        filters.append("c.case_code = ?")
        params.append(case_code)

    where_clause = "WHERE " + " AND ".join(filters) if filters else ""

    query = f"""
        SELECT TOP ({limit})
            d.donation_id,
            d.donation_code,
            d.donor_user_id,
            d.donor_name,
            d.donor_phone,
            d.donor_email,
            d.amount,
            d.currency,
            d.donation_target_type,
            d.donation_status,
            d.payment_status,
            d.campaign_name,
            d.general_notes,
            d.created_at,
            c.case_id,
            c.case_code,
            c.case_title,
            o.organization_id,
            o.organization_name_ar,
            pm.payment_method_id,
            pm.payment_method_code,
            pm.method_name_ar
        FROM dbo.donations d
        LEFT JOIN dbo.charity_cases c ON d.case_id = c.case_id
        LEFT JOIN dbo.organizations o ON d.organization_id = o.organization_id
        JOIN dbo.payment_methods pm ON d.payment_method_id = pm.payment_method_id
        {where_clause}
        ORDER BY d.created_at DESC;
    """

    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(query, params)
        donations = rows_to_dicts(cursor)

    return ApiResponse(
        success=True,
        message="Donations read from SQL Server.",
        data={"count": len(donations), "donations": donations},
    )


@router.get("/documents", response_model=ApiResponse)
def list_sql_documents(
    application_code: str | None = Query(default=None),
    organization_id: int | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=1000),
):
    filters = []
    params: list[Any] = []

    if application_code:
        filters.append("a.application_code = ?")
        params.append(application_code)

    if organization_id:
        filters.append("(a.organization_id = ? OR c.organization_id = ?)")
        params.extend([organization_id, organization_id])

    where_clause = "WHERE " + " AND ".join(filters) if filters else ""

    query = f"""
        SELECT TOP ({limit})
            d.document_id,
            d.document_code,
            d.document_type_id,
            dt.document_type_code,
            dt.document_type_name_ar AS document_type,
            d.original_file_name,
            d.stored_file_name,
            d.content_type,
            d.file_size_kb,
            d.bucket_name,
            d.object_key,
            d.storage_path,
            d.file_url,
            d.document_status,
            d.uploaded_at,
            d.reviewed_by,
            d.reviewed_at,
            a.application_id,
            a.application_code,
            d.case_id,
            c.case_code,
            COALESCE(a.organization_id, c.organization_id) AS organization_id,
            o.organization_name_ar,
            bp.beneficiary_id,
            bp.beneficiary_code,
            bp.full_name,
            bp.national_id
        FROM dbo.beneficiary_documents d
        LEFT JOIN dbo.document_types dt ON d.document_type_id = dt.document_type_id
        LEFT JOIN dbo.beneficiary_applications a ON d.application_id = a.application_id
        LEFT JOIN dbo.charity_cases c ON d.case_id = c.case_id
        LEFT JOIN dbo.organizations o ON COALESCE(a.organization_id, c.organization_id) = o.organization_id
        JOIN dbo.beneficiary_profiles bp ON d.beneficiary_id = bp.beneficiary_id
        {where_clause}
        ORDER BY d.uploaded_at DESC;
    """

    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(query, params)
        documents = rows_to_dicts(cursor)

    return ApiResponse(
        success=True,
        message="Document metadata read from SQL Server.",
        data={"count": len(documents), "documents": documents},
    )


@router.get("/inventory-transactions", response_model=ApiResponse)
def list_inventory_transactions(
    organization_id: int | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=1000),
):
    filters = []
    params: list[Any] = []

    if organization_id:
        filters.append("it.organization_id = ?")
        params.append(organization_id)

    where_clause = "WHERE " + " AND ".join(filters) if filters else ""

    query = f"""
        SELECT TOP ({limit})
            it.transaction_id,
            it.transaction_code,
            it.transaction_type,
            it.quantity,
            it.unit_cost,
            it.total_cost,
            it.case_id,
            c.case_code,
            it.application_id,
            a.application_code,
            it.donation_id,
            d.donation_code,
            it.reference_type,
            it.reference_id,
            it.notes,
            it.transaction_date,
            o.organization_id,
            o.organization_name_ar,
            br.branch_id,
            br.branch_name_ar,
            ii.item_id,
            ii.item_code,
            ii.item_name_ar,
            ii.item_category,
            ii.unit
        FROM dbo.inventory_transactions it
        JOIN dbo.organizations o ON it.organization_id = o.organization_id
        LEFT JOIN dbo.branches br ON it.branch_id = br.branch_id
        JOIN dbo.inventory_items ii ON it.item_id = ii.item_id
        LEFT JOIN dbo.charity_cases c ON it.case_id = c.case_id
        LEFT JOIN dbo.beneficiary_applications a ON it.application_id = a.application_id
        LEFT JOIN dbo.donations d ON it.donation_id = d.donation_id
        {where_clause}
        ORDER BY it.transaction_date DESC;
    """

    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(query, params)
        transactions = rows_to_dicts(cursor)

    return ApiResponse(
        success=True,
        message="Inventory transactions read from SQL Server.",
        data={"count": len(transactions), "inventory_transactions": transactions},
    )


@router.get("/events/outbox", response_model=ApiResponse)
def list_event_outbox(
    status: str | None = Query(default=None),
    organization_id: int | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=1000),
):
    filters = []
    params: list[Any] = []

    if status:
        filters.append("e.event_status = ?")
        params.append(status)

    if organization_id:
        filters.append("e.organization_id = ?")
        params.append(organization_id)

    where_clause = "WHERE " + " AND ".join(filters) if filters else ""

    query = f"""
        SELECT TOP ({limit})
            e.event_id,
            e.event_uuid,
            e.event_type,
            e.source_system,
            e.event_status,
            e.payload,
            e.created_at,
            e.sent_to_kafka_at,
            e.user_id,
            e.beneficiary_id,
            bp.beneficiary_code,
            bp.full_name AS beneficiary_name,
            e.organization_id,
            o.organization_name_ar,
            e.branch_id,
            br.branch_name_ar,
            e.application_id,
            a.application_code,
            e.case_id,
            c.case_code,
            e.donation_id,
            d.donation_code,
            e.document_id,
            doc.document_code,
            e.inventory_transaction_id,
            it.transaction_code,
            e.fraud_alert_id,
            fa.alert_code
        FROM dbo.platform_event_outbox e
        LEFT JOIN dbo.beneficiary_profiles bp ON e.beneficiary_id = bp.beneficiary_id
        LEFT JOIN dbo.organizations o ON e.organization_id = o.organization_id
        LEFT JOIN dbo.branches br ON e.branch_id = br.branch_id
        LEFT JOIN dbo.beneficiary_applications a ON e.application_id = a.application_id
        LEFT JOIN dbo.charity_cases c ON e.case_id = c.case_id
        LEFT JOIN dbo.donations d ON e.donation_id = d.donation_id
        LEFT JOIN dbo.beneficiary_documents doc ON e.document_id = doc.document_id
        LEFT JOIN dbo.inventory_transactions it ON e.inventory_transaction_id = it.transaction_id
        LEFT JOIN dbo.fraud_alerts fa ON e.fraud_alert_id = fa.fraud_alert_id
        {where_clause}
        ORDER BY e.created_at DESC;
    """

    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(query, params)
        events = rows_to_dicts(cursor)

    return ApiResponse(
        success=True,
        message="Event outbox read from SQL Server.",
        data={"count": len(events), "events": events},
    )


@router.get("/dashboard/government", response_model=ApiResponse)
def government_dashboard():
    with get_connection() as conn:
        cursor = conn.cursor()

        cursor.execute(
            """
            SELECT
                organizations_count AS active_organizations,
                beneficiaries_count AS beneficiaries,
                applications_count AS applications,
                cases_count AS cases,
                total_donations_amount AS total_donations,
                cross_organization_beneficiaries_count,
                open_duplicate_candidates_count,
                open_fraud_alerts_count
            FROM dbo.v_dashboard_government_summary;
            """
        )
        kpis = rows_to_dicts(cursor)[0]

        cursor.execute(
            """
            SELECT a.application_status AS label, COUNT(*) AS value
            FROM dbo.beneficiary_applications a
            GROUP BY a.application_status
            ORDER BY value DESC;
            """
        )
        application_status = rows_to_dicts(cursor)

        cursor.execute(
            """
            SELECT c.case_status AS label, COUNT(*) AS value
            FROM dbo.charity_cases c
            GROUP BY c.case_status
            ORDER BY value DESC;
            """
        )
        case_status = rows_to_dicts(cursor)

        cursor.execute(
            """
            SELECT st.support_name_ar AS label, COUNT(*) AS value
            FROM dbo.charity_cases c
            JOIN dbo.support_types st ON c.support_type_id = st.support_type_id
            GROUP BY st.support_name_ar
            ORDER BY value DESC;
            """
        )
        support_types = rows_to_dicts(cursor)

        cursor.execute(
            """
            SELECT o.organization_name_ar AS label, COALESCE(SUM(d.amount), 0) AS value
            FROM dbo.organizations o
            LEFT JOIN dbo.donations d ON o.organization_id = d.organization_id
            GROUP BY o.organization_name_ar
            ORDER BY value DESC;
            """
        )
        donations_by_organization = rows_to_dicts(cursor)

        cursor.execute(
            """
            SELECT
                c.case_code,
                c.case_title,
                o.organization_name_ar,
                c.required_amount,
                c.collected_amount,
                CASE WHEN c.required_amount > 0 THEN CAST((c.collected_amount / c.required_amount) * 100 AS DECIMAL(9,2)) ELSE 0 END AS coverage_percent,
                c.case_status
            FROM dbo.charity_cases c
            JOIN dbo.organizations o ON c.organization_id = o.organization_id
            ORDER BY c.created_at DESC;
            """
        )
        case_coverage = rows_to_dicts(cursor)

    return ApiResponse(
        success=True,
        message="Government dashboard read from SQL Server.",
        data={
            "kpis": kpis,
            "charts": {
                "application_status": application_status,
                "case_status": case_status,
                "support_types": support_types,
                "donations_by_organization": donations_by_organization,
                "case_coverage": case_coverage,
            },
        },
    )


@router.get("/beneficiaries/cross-organization", response_model=ApiResponse)
def list_cross_organization_beneficiaries(
    limit: int = Query(default=100, ge=1, le=1000),
):
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            f"""
            SELECT TOP ({limit})
                beneficiary_id,
                beneficiary_code,
                full_name,
                national_id,
                phone,
                governorate,
                city,
                organizations_count,
                organizations_names,
                applications_count,
                cases_count,
                fraud_alerts_count,
                duplicate_candidates_count,
                last_activity_date
            FROM dbo.v_beneficiary_360
            WHERE organizations_count > 1
            ORDER BY last_activity_date DESC;
            """
        )
        beneficiaries = rows_to_dicts(cursor)

    return ApiResponse(
        success=True,
        message="Cross-organization beneficiaries read from SQL Server.",
        data={
            "count": len(beneficiaries),
            "beneficiaries": beneficiaries,
        },
    )


@router.get("/dashboard/charity-network", response_model=ApiResponse)
def charity_network_dashboard(
    organization_id: int | None = Query(default=None),
):
    with get_connection() as conn:
        cursor = conn.cursor()

        charity_cards_where = "WHERE organization_id = ?" if organization_id else ""
        charity_cards_params: list[Any] = [organization_id] if organization_id else []

        cursor.execute(
            f"""
            SELECT
                organization_id,
                organization_code,
                organization_name_ar,
                beneficiaries_served,
                applications_count,
                approved_applications,
                rejected_applications,
                cases_count AS total_cases,
                open_cases,
                closed_cases,
                total_donations,
                fraud_alerts_count
            FROM dbo.v_charity_performance_dashboard
            {charity_cards_where}
            ORDER BY organization_id;
            """,
            charity_cards_params,
        )
        charity_cards = rows_to_dicts(cursor)

        support_where = "WHERE st.support_name_ar IS NOT NULL"
        support_params: list[Any] = []
        if organization_id:
            support_where += " AND o.organization_id = ?"
            support_params.append(organization_id)

        cursor.execute(
            f"""
            SELECT o.organization_id, o.organization_name_ar, st.support_name_ar AS label, COUNT(c.case_id) AS value
            FROM dbo.organizations o
            LEFT JOIN dbo.charity_cases c ON o.organization_id = c.organization_id
            LEFT JOIN dbo.support_types st ON c.support_type_id = st.support_type_id
            {support_where}
            GROUP BY o.organization_id, o.organization_name_ar, st.support_name_ar
            ORDER BY o.organization_id, value DESC;
            """,
            support_params,
        )
        support_distribution = rows_to_dicts(cursor)

        inventory_where = "WHERE it.transaction_type IS NOT NULL"
        inventory_params: list[Any] = []
        if organization_id:
            inventory_where += " AND o.organization_id = ?"
            inventory_params.append(organization_id)

        cursor.execute(
            f"""
            SELECT o.organization_id, o.organization_name_ar, it.transaction_type AS label, COALESCE(SUM(it.quantity), 0) AS value
            FROM dbo.organizations o
            LEFT JOIN dbo.inventory_transactions it ON o.organization_id = it.organization_id
            {inventory_where}
            GROUP BY o.organization_id, o.organization_name_ar, it.transaction_type
            ORDER BY o.organization_id, value DESC;
            """,
            inventory_params,
        )
        inventory_distribution = rows_to_dicts(cursor)

        coverage_where = "WHERE o.organization_id = ?" if organization_id else ""
        coverage_params: list[Any] = [organization_id] if organization_id else []

        cursor.execute(
            f"""
            SELECT
                o.organization_id,
                o.organization_name_ar,
                c.case_code,
                c.case_title,
                c.required_amount,
                c.collected_amount,
                CASE WHEN c.required_amount > 0 THEN CAST((c.collected_amount / c.required_amount) * 100 AS DECIMAL(9,2)) ELSE 0 END AS coverage_percent,
                c.case_status
            FROM dbo.organizations o
            JOIN dbo.charity_cases c ON o.organization_id = c.organization_id
            {coverage_where}
            ORDER BY o.organization_id, c.created_at DESC;
            """,
            coverage_params,
        )
        case_coverage = rows_to_dicts(cursor)

    return ApiResponse(
        success=True,
        message="Charity network dashboard read from SQL Server.",
        data={
            "organization_id": organization_id,
            "charity_cards": charity_cards,
            "charts": {
                "support_distribution": support_distribution,
                "inventory_distribution": inventory_distribution,
                "case_coverage": case_coverage,
            },
        },
    )
