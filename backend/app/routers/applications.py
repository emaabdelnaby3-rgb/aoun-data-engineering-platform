from fastapi import APIRouter, HTTPException

from app.schemas import BeneficiaryApplicationCreate, ReviewApplicationRequest, ApiResponse
from app.event_utils import build_platform_event
from app.database import save_application_event, save_application_review_event
from app.kafka_producer import publish_event

router = APIRouter()


@router.post("", response_model=ApiResponse)
def create_application(payload: BeneficiaryApplicationCreate):
    event = build_platform_event("BENEFICIARY_APPLICATION_SUBMITTED", payload.model_dump())

    try:
        sql_result = save_application_event(payload.model_dump(), event)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    publish_event("charity.beneficiary_applications", event)

    return ApiResponse(
        success=True,
        message="Application saved and auto-assigned using Step 5 business rules.",
        data={**event, "sql_result": sql_result},
    )


@router.post("/{application_id}/review", response_model=ApiResponse)
def review_application(application_id: str, payload: ReviewApplicationRequest):
    body = payload.model_dump()
    body["application_id"] = application_id
    event = build_platform_event("BENEFICIARY_APPLICATION_REVIEWED", body)

    try:
        sql_result = save_application_review_event(application_id, payload.model_dump(), event)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    publish_event("charity.beneficiary_applications", event)

    return ApiResponse(
        success=True,
        message="Application review saved with Step 5 business rules.",
        data={**event, "sql_result": sql_result},
    )
