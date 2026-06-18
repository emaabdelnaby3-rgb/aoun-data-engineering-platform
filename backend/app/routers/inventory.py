from fastapi import APIRouter, HTTPException

from app.schemas import InventoryTransactionCreate, ApiResponse
from app.event_utils import build_platform_event
from app.database import save_inventory_event
from app.kafka_producer import publish_event

router = APIRouter()


@router.post("", response_model=ApiResponse)
def create_inventory_transaction(payload: InventoryTransactionCreate):
    event = build_platform_event("INVENTORY_TRANSACTION_CREATED", payload.model_dump())

    try:
        sql_result = save_inventory_event(payload.model_dump(), event)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    publish_event("charity.inventory_transactions", event)

    return ApiResponse(
        success=True,
        message="Inventory transaction saved with auto pricing and stock validation.",
        data={**event, "sql_result": sql_result},
    )
