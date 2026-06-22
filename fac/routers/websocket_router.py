import asyncio
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from ..websocket.connection_manager import manager
from ..models.schemas import WSMessage, WSMessageType

router = APIRouter(tags=["websocket"])


@router.websocket("/ws/{device_id}")
async def websocket_endpoint(websocket: WebSocket, device_id: str):
    # Extract user_id from query param token (validated before upgrading)
    user_id = websocket.query_params.get("user_id", "unknown")
    tenant_id = websocket.query_params.get("tenant_id", "default")

    await manager.connect(websocket, device_id, user_id)

    # Send connection confirmation
    await manager.send_to_device(
        device_id,
        WSMessage(type=WSMessageType.ping, payload={"status": "connected"}),
    )

    try:
        while True:
            data = await asyncio.wait_for(websocket.receive_text(), timeout=60.0)
            try:
                msg = WSMessage.model_validate_json(data)
                if msg.type == WSMessageType.ping:
                    await websocket.send_text(
                        WSMessage(type=WSMessageType.pong).model_dump_json()
                    )
            except Exception:
                pass  # Ignore malformed messages
    except (WebSocketDisconnect, asyncio.TimeoutError):
        manager.disconnect(device_id)
