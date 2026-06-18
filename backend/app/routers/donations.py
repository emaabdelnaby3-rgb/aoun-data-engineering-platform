from fastapi import APIRouter, HTTPException

from app.schemas import DonationCreate, ApiResponse
from app.event_utils import build_platform_event
from app.database import save_donation_event
from app.kafka_producer import publish_event

router = APIRouter()


@router.post("", response_model=ApiResponse)
def create_donation(payload: DonationCreate):
    event = build_platform_event("DONATION_REQUESTED", payload.model_dump())

    try:
        sql_result = save_donation_event(payload.model_dump(), event)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    publish_event("charity.online_donations", event)

    return ApiResponse(
        success=True,
        message="Donation saved with Step 5 business rules.",
        data={**event, "sql_result": sql_result},
    )
