from typing import Annotated
from fastapi import Depends, HTTPException, Security, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
import redis.asyncio as aioredis

from ..services.jwt_service import JWTService
from ..dependencies import get_redis

_bearer = HTTPBearer(auto_error=True)


async def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials, Security(_bearer)],
    redis: Annotated[aioredis.Redis, Depends(get_redis)],
) -> dict:
    token = credentials.credentials
    jwt_svc = JWTService(redis)
    try:
        payload = await jwt_svc.verify_access_token(token)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
            headers={"WWW-Authenticate": "Bearer"},
        )
    return payload


def require_role(*roles: str):
    """Factory: returns a dependency that enforces at least one of the given roles."""
    async def _check(current_user: Annotated[dict, Depends(get_current_user)]) -> dict:
        user_roles: list = current_user.get("roles", [])
        if not any(r in user_roles for r in roles):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Insufficient permissions",
            )
        return current_user
    return _check
