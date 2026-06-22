from datetime import datetime, timedelta, timezone
from typing import Optional
from uuid import uuid4
import redis.asyncio as aioredis
from jose import JWTError, jwt
from ..config import get_settings

settings = get_settings()


class JWTService:
    def __init__(self, redis_client: aioredis.Redis):
        self._redis = redis_client

    # ── Token creation ────────────────────────────────────────────────────────

    def create_access_token(
        self,
        user_id: str,
        tenant_id: str,
        device_id: str,
        roles: list[str],
    ) -> tuple[str, str]:
        """Returns (access_token, jti)."""
        jti = str(uuid4())
        expire = datetime.now(timezone.utc) + timedelta(
            minutes=settings.jwt_access_token_expire_minutes
        )
        payload = {
            "sub": user_id,
            "user_id": user_id,
            "tenant_id": tenant_id,
            "device_id": device_id,
            "roles": roles,
            "jti": jti,
            "exp": expire,
            "iat": datetime.now(timezone.utc),
            "type": "access",
        }
        token = jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)
        return token, jti

    def create_refresh_token(
        self,
        user_id: str,
        tenant_id: str,
        device_id: str,
    ) -> tuple[str, str]:
        """Returns (refresh_token, jti)."""
        jti = str(uuid4())
        expire = datetime.now(timezone.utc) + timedelta(
            days=settings.jwt_refresh_token_expire_days
        )
        payload = {
            "sub": user_id,
            "user_id": user_id,
            "tenant_id": tenant_id,
            "device_id": device_id,
            "jti": jti,
            "exp": expire,
            "iat": datetime.now(timezone.utc),
            "type": "refresh",
        }
        token = jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)
        return token, jti

    # ── Token verification ────────────────────────────────────────────────────

    async def verify_access_token(self, token: str) -> dict:
        try:
            payload = jwt.decode(
                token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm]
            )
        except JWTError as exc:
            raise ValueError(f"Invalid token: {exc}") from exc

        if payload.get("type") != "access":
            raise ValueError("Not an access token")

        jti = payload.get("jti")
        if jti and await self._is_blacklisted(jti):
            raise ValueError("Token has been revoked")

        return payload

    async def verify_refresh_token(self, token: str) -> dict:
        try:
            payload = jwt.decode(
                token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm]
            )
        except JWTError as exc:
            raise ValueError(f"Invalid token: {exc}") from exc

        if payload.get("type") != "refresh":
            raise ValueError("Not a refresh token")

        jti = payload.get("jti")
        if jti and await self._is_blacklisted(jti):
            raise ValueError("Token has been revoked")

        return payload

    # ── Blacklisting ──────────────────────────────────────────────────────────

    async def blacklist_token(self, jti: str, expires_at: datetime) -> None:
        ttl = int((expires_at - datetime.now(timezone.utc)).total_seconds())
        if ttl > 0:
            await self._redis.setex(f"blacklist:{jti}", ttl, "1")

    async def blacklist_all_user_tokens(self, user_id: str, tenant_id: str) -> None:
        """Publish force-logout event; FAC WS manager handles per-device revocation."""
        await self._redis.publish(
            f"force_logout:{tenant_id}:{user_id}",
            "1",
        )

    async def _is_blacklisted(self, jti: str) -> bool:
        return bool(await self._redis.exists(f"blacklist:{jti}"))
