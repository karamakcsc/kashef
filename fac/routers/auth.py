from datetime import datetime
from typing import Annotated
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession
import redis.asyncio as aioredis

from ..models.database import get_db, SessionModel
from ..models.schemas import (
    LoginRequest, TokenResponse, RefreshRequest, UserInfo,
    DeviceStatusEnum,
)
from ..services.jwt_service import JWTService
from ..services.device_service import DeviceService
from ..services.erpnext_service import ERPNextService
from ..middleware.auth_middleware import get_current_user
from ..dependencies import get_redis, get_erp_service

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=TokenResponse)
async def login(
    payload: LoginRequest,
    request: Request,
    db: Annotated[AsyncSession, Depends(get_db)],
    redis: Annotated[aioredis.Redis, Depends(get_redis)],
    erp: Annotated[ERPNextService, Depends(get_erp_service)],
):
    ip = request.client.host if request.client else ""

    # 1 — Authenticate against ERPNext
    user_info = await erp.authenticate_user(payload.username, payload.password)
    if not user_info:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")

    user_id = user_info["user_id"]
    tenant_id = user_info["tenant_id"]

    # 2 — Device validation
    device_svc = DeviceService(db, erp)
    result = await device_svc.validate_and_register(
        user_id=user_id,
        tenant_id=tenant_id,
        device_id=payload.device_id,
        device_name=payload.device_name,
        platform=payload.platform,
        app_version=payload.app_version,
        ip_address=ip or payload.ip_address or "",
    )

    if not result["allowed"]:
        reason = result["reason"]
        code_map = {
            "DEVICE_BLOCKED": 403,
            "DEVICE_PENDING": 202,
            "MOBILE_ACCESS_DISABLED": 403,
            "MAX_DEVICES_REACHED": 403,
        }
        raise HTTPException(
            status_code=code_map.get(reason, 403),
            detail=reason,
        )

    # 3 — Issue tokens
    jwt_svc = JWTService(redis)
    access_token, access_jti = jwt_svc.create_access_token(
        user_id=user_id,
        tenant_id=tenant_id,
        device_id=payload.device_id,
        roles=user_info["roles"],
    )
    refresh_token, _ = jwt_svc.create_refresh_token(
        user_id=user_id,
        tenant_id=tenant_id,
        device_id=payload.device_id,
    )

    # 4 — Persist session
    session = SessionModel(
        user_id=user_id,
        tenant_id=tenant_id,
        device_id=payload.device_id,
        jti=access_jti,
        access_token=access_token,
        refresh_token=refresh_token,
        login_time=datetime.utcnow(),
        ip_address=ip or "",
    )
    db.add(session)
    await db.commit()

    # 5 — Log to ERPNext
    await erp.log_session_event(
        user=user_id,
        device_id=payload.device_id,
        event="login",
        ip_address=ip or "",
    )

    from ..config import get_settings
    s = get_settings()
    expires_in = s.jwt_access_token_expire_minutes * 60

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=expires_in,
        user=UserInfo(**user_info),
        device_status=result["device_status"],
    )


@router.post("/refresh", response_model=TokenResponse)
async def refresh(
    payload: RefreshRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    redis: Annotated[aioredis.Redis, Depends(get_redis)],
    erp: Annotated[ERPNextService, Depends(get_erp_service)],
):
    jwt_svc = JWTService(redis)
    try:
        claims = await jwt_svc.verify_refresh_token(payload.refresh_token)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(exc))

    if claims["device_id"] != payload.device_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Device mismatch")

    user_info = await erp.get_user_info(claims["user_id"])
    access_token, access_jti = jwt_svc.create_access_token(
        user_id=claims["user_id"],
        tenant_id=claims["tenant_id"],
        device_id=payload.device_id,
        roles=user_info["roles"],
    )
    new_refresh, _ = jwt_svc.create_refresh_token(
        user_id=claims["user_id"],
        tenant_id=claims["tenant_id"],
        device_id=payload.device_id,
    )

    from ..config import get_settings
    s = get_settings()
    return TokenResponse(
        access_token=access_token,
        refresh_token=new_refresh,
        expires_in=s.jwt_access_token_expire_minutes * 60,
        user=UserInfo(**user_info),
        device_status=DeviceStatusEnum.active,
    )


@router.post("/logout")
async def logout(
    current_user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    redis: Annotated[aioredis.Redis, Depends(get_redis)],
    erp: Annotated[ERPNextService, Depends(get_erp_service)],
):
    jwt_svc = JWTService(redis)
    from datetime import timezone
    from jose import jwt as jose_jwt
    from ..config import get_settings
    s = get_settings()

    jti = current_user.get("jti", "")
    if jti:
        exp = datetime.fromtimestamp(current_user["exp"], tz=timezone.utc)
        await jwt_svc.blacklist_token(jti, exp)

    await erp.log_session_event(
        user=current_user["user_id"],
        device_id=current_user["device_id"],
        event="logout",
    )
    return {"detail": "Logged out successfully"}


@router.get("/me", response_model=UserInfo)
async def get_me(
    current_user: Annotated[dict, Depends(get_current_user)],
    erp: Annotated[ERPNextService, Depends(get_erp_service)],
):
    info = await erp.get_user_info(current_user["user_id"])
    return UserInfo(**info)
