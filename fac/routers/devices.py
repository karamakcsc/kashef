from typing import Annotated, List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
import redis.asyncio as aioredis

from ..models.database import get_db
from ..models.schemas import DeviceResponse, DeviceStatusEnum, ForceLogoutRequest
from ..services.device_service import DeviceService
from ..services.erpnext_service import ERPNextService
from ..services.jwt_service import JWTService
from ..middleware.auth_middleware import get_current_user, require_role
from ..websocket.connection_manager import manager
from ..dependencies import get_redis, get_erp_service

router = APIRouter(prefix="/devices", tags=["devices"])


@router.get("", response_model=List[DeviceResponse])
async def list_my_devices(
    current_user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    erp: Annotated[ERPNextService, Depends(get_erp_service)],
):
    svc = DeviceService(db, erp)
    devices = await svc.get_user_devices(current_user["user_id"])
    return [DeviceResponse.model_validate(d) for d in devices]


@router.post("/{device_id}/block", status_code=status.HTTP_200_OK)
async def block_device(
    device_id: str,
    current_user: Annotated[dict, Depends(require_role("System Manager"))],
    db: Annotated[AsyncSession, Depends(get_db)],
    redis: Annotated[aioredis.Redis, Depends(get_redis)],
    erp: Annotated[ERPNextService, Depends(get_erp_service)],
):
    svc = DeviceService(db, erp)
    await svc.set_device_status(device_id, DeviceStatusEnum.blocked)

    # Notify device via WS
    from ..models.schemas import WSMessage, WSMessageType
    await manager.send_to_device(
        device_id,
        WSMessage(type=WSMessageType.device_blocked, payload={"device_id": device_id}),
    )
    return {"detail": f"Device {device_id} blocked"}


@router.post("/{device_id}/trust", status_code=status.HTTP_200_OK)
async def trust_device(
    device_id: str,
    current_user: Annotated[dict, Depends(require_role("System Manager"))],
    db: Annotated[AsyncSession, Depends(get_db)],
    erp: Annotated[ERPNextService, Depends(get_erp_service)],
):
    svc = DeviceService(db, erp)
    await svc.set_device_status(device_id, DeviceStatusEnum.active)

    from ..models.schemas import WSMessage, WSMessageType
    await manager.send_to_device(
        device_id,
        WSMessage(type=WSMessageType.device_approved, payload={"device_id": device_id}),
    )
    return {"detail": f"Device {device_id} approved"}


@router.post("/force-logout", status_code=status.HTTP_200_OK)
async def force_logout(
    payload: ForceLogoutRequest,
    current_user: Annotated[dict, Depends(require_role("System Manager"))],
    redis: Annotated[aioredis.Redis, Depends(get_redis)],
    erp: Annotated[ERPNextService, Depends(get_erp_service)],
):
    jwt_svc = JWTService(redis)
    await jwt_svc.blacklist_all_user_tokens(payload.user_id, payload.tenant_id)
    await manager.force_logout_user(payload.user_id, reason=payload.reason or "")

    await erp.log_session_event(
        user=payload.user_id,
        device_id="all",
        event="force_logout",
    )
    return {"detail": f"Force logout triggered for {payload.user_id}"}
