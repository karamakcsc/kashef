"""
Shared FastAPI dependencies (Redis client, ERPNext service).
"""
from functools import lru_cache
import redis.asyncio as aioredis
from .config import get_settings
from .services.erpnext_service import ERPNextService

settings = get_settings()

_redis: aioredis.Redis | None = None


async def get_redis() -> aioredis.Redis:
    global _redis
    if _redis is None:
        _redis = aioredis.from_url(settings.redis_url, decode_responses=True)
    return _redis


@lru_cache
def _erp_instance() -> ERPNextService:
    return ERPNextService()


async def get_erp_service() -> ERPNextService:
    return _erp_instance()
