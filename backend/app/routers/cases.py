from fastapi import APIRouter, HTTPException

from app.schemas import CaseCreate, ApiResponse
from app.event_utils import build_platform_event
from app.database import save_case_event

router = APIRouter()


@router.post("", response_model=ApiResponse)
def create_case(payload: CaseCreate):
    event = build_platform_event("CASE_CREATED", payload.model_dump())

    try:
        sql_result = save_case_event(payload.model_dump(), event)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return ApiResponse(
        success=True,
        message="Case saved with auto-generated case code and organization/branch validation.",
        data={**event, "sql_result": sql_result},
    )
