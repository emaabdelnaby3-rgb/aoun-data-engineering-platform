from datetime import datetime, timezone
from uuid import uuid4


def build_platform_event(event_type: str, payload: dict) -> dict:
    return {
        "event_id": str(uuid4()),
        "event_type": event_type,
        "source_system": "unified_charity_platform",
        "event_timestamp": datetime.now(timezone.utc).isoformat(),
        "payload": payload,
    }
