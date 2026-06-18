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


@router.get("/search", response_model=ApiResponse)
def search_beneficiaries(
    q: str | None = Query(default=None),
    national_id: str | None = Query(default=None),
    phone: str | None = Query(default=None),
    organization_id: int | None = Query(default=None),
    governorate_id: int | None = Query(default=None),
    city_id: int | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=1000),
):
    filters = []
    params: list[Any] = []

    if q:
        filters.append(
            """
            (
                bp.full_name LIKE ?
                OR bp.beneficiary_code LIKE ?
                OR bp.national_id LIKE ?
                OR bp.phone LIKE ?
            )
            """
        )
        like_value = f"%{q}%"
        params.extend([like_value, like_value, like_value, like_value])

    if national_id:
        filters.append("bp.national_id = ?")
        params.append(national_id)

    if phone:
        filters.append("bp.phone = ?")
        params.append(phone)

    if organization_id:
        filters.append(
            """
            EXISTS (
                SELECT 1
                FROM dbo.beneficiary_org_registrations bor
                WHERE bor.beneficiary_id = bp.beneficiary_id
                  AND bor.organization_id = ?
            )
            """
        )
        params.append(organization_id)

    if governorate_id:
        filters.append("bp.governorate_id = ?")
        params.append(governorate_id)

    if city_id:
        filters.append("bp.city_id = ?")
        params.append(city_id)

    where_clause = "WHERE " + " AND ".join(filters) if filters else ""

    query = f"""
        SELECT TOP ({limit})
            bp.beneficiary_id,
            bp.beneficiary_code,
            bp.user_id,
            bp.national_id,
            bp.full_name,
            bp.gender,
            bp.birth_date,
            bp.phone,
            bp.email,
            bp.governorate_id,
            g.governorate_name_ar AS governorate,
            bp.city_id,
            c.city_name_ar AS city,
            bp.address,
            bp.family_size,
            bp.monthly_income,
            bp.employment_status,
            bp.is_active,
            bp.created_at,
            bp.updated_at,

            COALESCE(orgs.organizations_count, 0) AS organizations_count,
            orgs.organizations_names,
            COALESCE(apps.applications_count, 0) AS applications_count,
            COALESCE(cases.cases_count, 0) AS cases_count,
            COALESCE(fraud.fraud_alerts_count, 0) AS fraud_alerts_count,
            COALESCE(dups.duplicate_candidates_count, 0) AS duplicate_candidates_count
        FROM dbo.beneficiary_profiles bp
        LEFT JOIN dbo.governorates g
            ON bp.governorate_id = g.governorate_id
        LEFT JOIN dbo.cities c
            ON bp.city_id = c.city_id
        OUTER APPLY (
            SELECT
                COUNT(DISTINCT bor.organization_id) AS organizations_count,
                STRING_AGG(x.organization_name_ar, N'، ') AS organizations_names
            FROM (
                SELECT DISTINCT o.organization_name_ar, bor2.organization_id
                FROM dbo.beneficiary_org_registrations bor2
                JOIN dbo.organizations o
                    ON bor2.organization_id = o.organization_id
                WHERE bor2.beneficiary_id = bp.beneficiary_id
            ) x
            JOIN dbo.beneficiary_org_registrations bor
                ON bor.organization_id = x.organization_id
               AND bor.beneficiary_id = bp.beneficiary_id
        ) orgs
        OUTER APPLY (
            SELECT COUNT(*) AS applications_count
            FROM dbo.beneficiary_applications a
            WHERE a.beneficiary_id = bp.beneficiary_id
        ) apps
        OUTER APPLY (
            SELECT COUNT(*) AS cases_count
            FROM dbo.charity_cases cc
            WHERE cc.beneficiary_id = bp.beneficiary_id
        ) cases
        OUTER APPLY (
            SELECT COUNT(*) AS fraud_alerts_count
            FROM dbo.fraud_alerts fa
            WHERE fa.beneficiary_id = bp.beneficiary_id
        ) fraud
        OUTER APPLY (
            SELECT COUNT(*) AS duplicate_candidates_count
            FROM dbo.duplicate_candidates dc
            WHERE dc.primary_beneficiary_id = bp.beneficiary_id
               OR dc.duplicate_beneficiary_id = bp.beneficiary_id
        ) dups
        {where_clause}
        ORDER BY bp.created_at DESC;
    """

    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(query, params)
        beneficiaries = rows_to_dicts(cursor)

    return ApiResponse(
        success=True,
        message="Beneficiaries loaded from SQL Server.",
        data={"count": len(beneficiaries), "beneficiaries": beneficiaries},
    )


@router.get("/dashboard/summary", response_model=ApiResponse)
def beneficiary_dashboard_summary():
    with get_connection() as conn:
        cursor = conn.cursor()

        cursor.execute(
            """
            SELECT
                COUNT(*) AS total_beneficiaries,
                SUM(CASE WHEN organizations_count > 1 THEN 1 ELSE 0 END) AS cross_organization_beneficiaries,
                SUM(CASE WHEN fraud_alerts_count > 0 THEN 1 ELSE 0 END) AS fraud_alert_beneficiaries,
                SUM(CASE WHEN duplicate_candidates_count > 0 THEN 1 ELSE 0 END) AS duplicate_candidate_beneficiaries,
                COALESCE(SUM(applications_count), 0) AS total_applications,
                COALESCE(SUM(cases_count), 0) AS total_cases,
                COALESCE(SUM(total_required_amount), 0) AS total_required_amount,
                COALESCE(SUM(total_collected_amount), 0) AS total_collected_amount
            FROM dbo.v_beneficiary_360;
            """
        )
        summary = rows_to_dicts(cursor)[0]

        cursor.execute(
            """
            SELECT governorate AS label, COUNT(*) AS value
            FROM dbo.v_beneficiary_360
            GROUP BY governorate
            ORDER BY value DESC;
            """
        )
        beneficiaries_by_governorate = rows_to_dicts(cursor)

        cursor.execute(
            """
            SELECT
                CASE WHEN organizations_count > 1 THEN N'مسجل في أكثر من جمعية'
                     ELSE N'مسجل في جمعية واحدة'
                END AS label,
                COUNT(*) AS value
            FROM dbo.v_beneficiary_360
            GROUP BY CASE WHEN organizations_count > 1 THEN N'مسجل في أكثر من جمعية'
                          ELSE N'مسجل في جمعية واحدة'
                     END
            ORDER BY value DESC;
            """
        )
        cross_org_distribution = rows_to_dicts(cursor)

        cursor.execute(
            """
            SELECT
                CASE
                    WHEN fraud_alerts_count > 0 THEN N'عليه تنبيهات مخاطر'
                    WHEN duplicate_candidates_count > 0 THEN N'مرشح تكرار'
                    ELSE N'طبيعي'
                END AS label,
                COUNT(*) AS value
            FROM dbo.v_beneficiary_360
            GROUP BY
                CASE
                    WHEN fraud_alerts_count > 0 THEN N'عليه تنبيهات مخاطر'
                    WHEN duplicate_candidates_count > 0 THEN N'مرشح تكرار'
                    ELSE N'طبيعي'
                END
            ORDER BY value DESC;
            """
        )
        risk_distribution = rows_to_dicts(cursor)

    return ApiResponse(
        success=True,
        message="Beneficiary dashboard summary loaded from SQL Server.",
        data={
            "summary": summary,
            "charts": {
                "beneficiaries_by_governorate": beneficiaries_by_governorate,
                "cross_org_distribution": cross_org_distribution,
                "risk_distribution": risk_distribution,
            },
        },
    )


@router.get("/reports/cross-organization", response_model=ApiResponse)
def cross_organization_beneficiaries(
    limit: int = Query(default=100, ge=1, le=1000),
):
    query = f"""
        SELECT TOP ({limit})
            beneficiary_id,
            beneficiary_code,
            national_id,
            full_name,
            phone,
            email,
            governorate,
            city,
            family_size,
            monthly_income,
            organizations_count,
            organizations_names,
            applications_count,
            approved_applications_count,
            rejected_applications_count,
            cases_count,
            open_cases_count,
            closed_cases_count,
            total_required_amount,
            total_collected_amount,
            fraud_alerts_count,
            duplicate_candidates_count
                   last_activity_date
        FROM dbo.v_beneficiary_cross_organization
        ORDER BY last_activity_date DESC, organizations_count DESC, applications_count DESC;
    """

    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(query)
        beneficiaries = rows_to_dicts(cursor)

    return ApiResponse(
        success=True,
        message="Cross-organization beneficiaries loaded from SQL Server.",
        data={"count": len(beneficiaries), "beneficiaries": beneficiaries},
    )


@router.get("/reports/duplicates", response_model=ApiResponse)
def duplicate_beneficiary_candidates(
    status: str | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=1000),
):
    filters = []
    params: list[Any] = []

    if status:
        filters.append("candidate_status = ?")
        params.append(status)

    where_clause = "WHERE " + " AND ".join(filters) if filters else ""

    query = f"""
        SELECT TOP ({limit})
            duplicate_candidate_id,
            rule_code,
            primary_beneficiary_id,
            duplicate_beneficiary_id,
            identity_record_id,
            organization_id,
            beneficiary_code,
            full_name,
            national_id,
            phone,
            organization_name_ar,
            candidate_reason,
            confidence_score AS risk_score,
            candidate_status,
            detected_at,
            resolved_by,
            resolved_at,
            resolution_notes
        FROM dbo.v_duplicate_beneficiary_candidates
        {where_clause}
        ORDER BY confidence_score DESC, detected_at DESC;
    """

    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(query, params)
        duplicates = rows_to_dicts(cursor)

    return ApiResponse(
        success=True,
        message="Duplicate beneficiary candidates loaded from SQL Server.",
        data={"count": len(duplicates), "duplicates": duplicates},
    )


@router.get("/fraud-alerts", response_model=ApiResponse)
def fraud_alerts(
    status: str | None = Query(default=None),
    severity: str | None = Query(default=None),
    beneficiary_id: int | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=1000),
):
    filters = []
    params: list[Any] = []

    if status:
        filters.append("alert_status = ?")
        params.append(status)

    if severity:
        filters.append("severity = ?")
        params.append(severity)

    if beneficiary_id:
        filters.append("beneficiary_id = ?")
        params.append(beneficiary_id)

    where_clause = "WHERE " + " AND ".join(filters) if filters else ""

    query = f"""
        SELECT TOP ({limit}) *
        FROM dbo.v_fraud_command_center
        {where_clause}
        ORDER BY risk_score DESC, created_at DESC;
    """

    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(query, params)
        alerts = rows_to_dicts(cursor)

    return ApiResponse(
        success=True,
        message="Fraud alerts loaded from SQL Server.",
        data={"count": len(alerts), "fraud_alerts": alerts},
    )


@router.get("/360", response_model=ApiResponse)
def beneficiary_360(
    beneficiary_id: int | None = Query(default=None),
    national_id: str | None = Query(default=None),
):
    if beneficiary_id is None and not national_id:
        return ApiResponse(
            success=False,
            message="Please provide beneficiary_id or national_id.",
            data=None,
        )

    with get_connection() as conn:
        cursor = conn.cursor()

        if beneficiary_id is None:
            cursor.execute(
                """
                SELECT beneficiary_id
                FROM dbo.beneficiary_profiles
                WHERE national_id = ?;
                """,
                national_id,
            )
            row = cursor.fetchone()
            if not row:
                return ApiResponse(
                    success=False, message="Beneficiary not found.", data=None
                )
            beneficiary_id = row[0]

        # Clean profile, without duplicated organization names caused by analytical view joins
        cursor.execute(
            """
            SELECT
                bp.beneficiary_id,
                bp.beneficiary_code,
                bp.user_id,
                bp.national_id,
                bp.full_name,
                bp.gender,
                bp.birth_date,
                bp.phone,
                bp.email,
                g.governorate_name_ar AS governorate,
                ci.city_name_ar AS city,
                bp.address,
                bp.family_size,
                bp.monthly_income,
                bp.employment_status,
                COALESCE(orgs.organizations_count, 0) AS organizations_count,
                orgs.organizations_names,
                COALESCE(apps.applications_count, 0) AS applications_count,
                COALESCE(apps.approved_applications_count, 0) AS approved_applications_count,
                COALESCE(apps.rejected_applications_count, 0) AS rejected_applications_count,
                COALESCE(cases.cases_count, 0) AS cases_count,
                COALESCE(cases.open_cases_count, 0) AS open_cases_count,
                COALESCE(cases.closed_cases_count, 0) AS closed_cases_count,
                COALESCE(cases.total_required_amount, 0) AS total_required_amount,
                COALESCE(cases.total_collected_amount, 0) AS total_collected_amount,
                COALESCE(don.total_donations_received, 0) AS total_donations_received,
                COALESCE(inv.inventory_support_movements_count, 0) AS inventory_support_movements_count,
                COALESCE(inv.total_inventory_support_value, 0) AS total_inventory_support_value,
                COALESCE(fraud.fraud_alerts_count, 0) AS fraud_alerts_count,
                COALESCE(dups.duplicate_candidates_count, 0) AS duplicate_candidates_count
            FROM dbo.beneficiary_profiles bp
            LEFT JOIN dbo.governorates g
                ON bp.governorate_id = g.governorate_id
            LEFT JOIN dbo.cities ci
                ON bp.city_id = ci.city_id
            OUTER APPLY (
                SELECT
                    COUNT(*) AS organizations_count,
                    STRING_AGG(organization_name_ar, N'، ') AS organizations_names
                FROM (
                    SELECT DISTINCT o.organization_name_ar
                    FROM dbo.beneficiary_org_registrations bor
                    JOIN dbo.organizations o
                        ON bor.organization_id = o.organization_id
                    WHERE bor.beneficiary_id = bp.beneficiary_id
                ) x
            ) orgs
            OUTER APPLY (
                SELECT
                    COUNT(*) AS applications_count,
                    SUM(CASE WHEN application_status = N'APPROVED' THEN 1 ELSE 0 END) AS approved_applications_count,
                    SUM(CASE WHEN application_status = N'REJECTED' THEN 1 ELSE 0 END) AS rejected_applications_count
                FROM dbo.beneficiary_applications a
                WHERE a.beneficiary_id = bp.beneficiary_id
            ) apps
            OUTER APPLY (
                SELECT
                    COUNT(*) AS cases_count,
                    SUM(CASE WHEN case_status = N'OPEN' THEN 1 ELSE 0 END) AS open_cases_count,
                    SUM(CASE WHEN case_status IN (N'CLOSED', N'COMPLETED') THEN 1 ELSE 0 END) AS closed_cases_count,
                    SUM(required_amount) AS total_required_amount,
                    SUM(collected_amount) AS total_collected_amount
                FROM dbo.charity_cases c
                WHERE c.beneficiary_id = bp.beneficiary_id
            ) cases
            OUTER APPLY (
                SELECT SUM(d.amount) AS total_donations_received
                FROM dbo.donations d
                JOIN dbo.charity_cases c
                    ON d.case_id = c.case_id
                WHERE c.beneficiary_id = bp.beneficiary_id
                  AND d.donation_status = N'COMPLETED'
                  AND d.payment_status = N'SUCCESS'
            ) don
            OUTER APPLY (
                SELECT
                    COUNT(*) AS inventory_support_movements_count,
                    SUM(it.total_cost) AS total_inventory_support_value
                FROM dbo.inventory_transactions it
                JOIN dbo.charity_cases c
                    ON it.case_id = c.case_id
                WHERE c.beneficiary_id = bp.beneficiary_id
                  AND it.transaction_type = N'OUT'
            ) inv
            OUTER APPLY (
                SELECT COUNT(*) AS fraud_alerts_count
                FROM dbo.fraud_alerts fa
                WHERE fa.beneficiary_id = bp.beneficiary_id
            ) fraud
            OUTER APPLY (
                SELECT COUNT(*) AS duplicate_candidates_count
                FROM dbo.duplicate_candidates dc
                WHERE dc.primary_beneficiary_id = bp.beneficiary_id
                   OR dc.duplicate_beneficiary_id = bp.beneficiary_id
            ) dups
            WHERE bp.beneficiary_id = ?;
            """,
            beneficiary_id,
        )
        profile_rows = rows_to_dicts(cursor)
        if not profile_rows:
            return ApiResponse(
                success=False, message="Beneficiary not found.", data=None
            )

        cursor.execute(
            """
            SELECT
                a.application_id,
                a.application_code,
                a.beneficiary_id,
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
                a.reviewed_at,
                a.admin_notes,
                a.assignment_reason
            FROM dbo.beneficiary_applications a
            JOIN dbo.organizations o
                ON a.organization_id = o.organization_id
            LEFT JOIN dbo.branches br
                ON a.branch_id = br.branch_id
            JOIN dbo.support_types st
                ON a.support_type_id = st.support_type_id
            WHERE a.beneficiary_id = ?
            ORDER BY a.submitted_at DESC;
            """,
            beneficiary_id,
        )
        applications = rows_to_dicts(cursor)

        cursor.execute(
            """
            SELECT
                c.case_id,
                c.case_code,
                c.application_id,
                c.beneficiary_id,
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
                CASE
                    WHEN c.required_amount > 0
                    THEN CAST((c.collected_amount / c.required_amount) * 100 AS DECIMAL(9,2))
                    ELSE 0
                END AS coverage_percent,
                c.case_status,
                c.priority_level,
                c.published_at,
                c.closed_at,
                c.created_at
            FROM dbo.charity_cases c
            JOIN dbo.organizations o
                ON c.organization_id = o.organization_id
            LEFT JOIN dbo.branches br
                ON c.branch_id = br.branch_id
            JOIN dbo.support_types st
                ON c.support_type_id = st.support_type_id
            WHERE c.beneficiary_id = ?
            ORDER BY c.created_at DESC;
            """,
            beneficiary_id,
        )
        cases = rows_to_dicts(cursor)

        cursor.execute(
            """
            SELECT
                d.donation_id,
                d.donation_code,
                d.donor_name,
                d.donor_phone,
                d.amount,
                d.currency,
                d.donation_target_type,
                d.donation_status,
                d.payment_status,
                d.campaign_name,
                d.created_at,
                c.case_id,
                c.case_code,
                c.case_title,
                o.organization_name_ar,
                pm.method_name_ar AS payment_method
            FROM dbo.donations d
            JOIN dbo.charity_cases c
                ON d.case_id = c.case_id
            LEFT JOIN dbo.organizations o
                ON d.organization_id = o.organization_id
            JOIN dbo.payment_methods pm
                ON d.payment_method_id = pm.payment_method_id
            WHERE c.beneficiary_id = ?
            ORDER BY d.created_at DESC;
            """,
            beneficiary_id,
        )
        donations = rows_to_dicts(cursor)

        cursor.execute(
            """
            SELECT
                it.transaction_id,
                it.transaction_code,
                it.transaction_type,
                it.quantity,
                it.unit_cost,
                it.total_cost,
                it.reference_type,
                it.reference_id,
                it.notes,
                it.transaction_date,
                ii.item_id,
                ii.item_code,
                ii.item_name_ar,
                ii.item_category,
                ii.unit,
                c.case_id,
                c.case_code,
                c.case_title,
                o.organization_name_ar
            FROM dbo.inventory_transactions it
            JOIN dbo.inventory_items ii
                ON it.item_id = ii.item_id
            JOIN dbo.charity_cases c
                ON it.case_id = c.case_id
            JOIN dbo.organizations o
                ON it.organization_id = o.organization_id
            WHERE c.beneficiary_id = ?
            ORDER BY it.transaction_date DESC;
            """,
            beneficiary_id,
        )
        inventory_support = rows_to_dicts(cursor)

        cursor.execute(
            """
            SELECT
                d.document_id,
                d.document_code,
                dt.document_type_name_ar AS document_type,
                d.original_file_name,
                d.content_type,
                d.file_size_kb,
                d.bucket_name,
                d.object_key,
                d.storage_path,
                d.file_url,
                d.document_status,
                d.uploaded_at,
                a.application_id,
                a.application_code,
                c.case_id,
                c.case_code
            FROM dbo.beneficiary_documents d
            LEFT JOIN dbo.document_types dt
                ON d.document_type_id = dt.document_type_id
            LEFT JOIN dbo.beneficiary_applications a
                ON d.application_id = a.application_id
            LEFT JOIN dbo.charity_cases c
                ON d.case_id = c.case_id
            WHERE d.beneficiary_id = ?
            ORDER BY d.uploaded_at DESC;
            """,
            beneficiary_id,
        )
        documents = rows_to_dicts(cursor)

        cursor.execute(
            """
            SELECT *
            FROM dbo.v_beneficiary_support_timeline
            WHERE beneficiary_id = ?
            ORDER BY event_date DESC;
            """,
            beneficiary_id,
        )
        timeline = rows_to_dicts(cursor)

        cursor.execute(
            """
            SELECT *
            FROM dbo.v_fraud_command_center
            WHERE beneficiary_id = ?
            ORDER BY risk_score DESC, created_at DESC;
            """,
            beneficiary_id,
        )
        fraud_alerts_rows = rows_to_dicts(cursor)

        cursor.execute(
            """
            SELECT *
            FROM dbo.v_duplicate_beneficiary_candidates
            WHERE primary_beneficiary_id = ?
               OR duplicate_beneficiary_id = ?
            ORDER BY confidence_score DESC, detected_at DESC;
            """,
            beneficiary_id,
            beneficiary_id,
        )
        duplicates = rows_to_dicts(cursor)

    return ApiResponse(
        success=True,
        message="Beneficiary 360 loaded from SQL Server.",
        data={
            "profile": profile_rows[0],
            "applications": applications,
            "cases": cases,
            "donations": donations,
            "inventory_support": inventory_support,
            "inventory_transactions": inventory_support,
            "documents": documents,
            "timeline": timeline,
            "fraud_alerts": fraud_alerts_rows,
            "duplicates": duplicates,
        },
    )
