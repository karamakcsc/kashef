"""
KCSC AI FAC (Frappe AI Connector) — FastAPI entry point.
"""
import asyncio
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

from .config import get_settings
from .models.database import engine, Base
from .routers import auth, devices, ai as ai_router, websocket_router
from .dependencies import get_redis
from .websocket.connection_manager import manager

settings = get_settings()
limiter = Limiter(key_func=get_remote_address)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Create DB tables
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    # Start Redis pub/sub listener for force-logout fan-out
    redis = await get_redis()
    asyncio.create_task(
        manager.start_redis_listener(redis, tenant_id="default")
    )

    yield

    await engine.dispose()
    await redis.aclose()


app = FastAPI(
    title="KCSC AI FAC",
    description="Frappe AI Connector — Mobile backend for KCSC AI Platform",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs" if settings.debug else None,
    redoc_url="/redoc" if settings.debug else None,
)

# ── Middleware ────────────────────────────────────────────────────────────────
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(GZipMiddleware, minimum_size=1000)

# ── Routers ───────────────────────────────────────────────────────────────────
prefix = settings.api_v1_prefix
app.include_router(auth.router, prefix=prefix)
app.include_router(devices.router, prefix=prefix)
app.include_router(ai_router.router, prefix=prefix)
app.include_router(websocket_router.router)  # WS routes have no prefix


@app.get("/health")
async def health():
    return {"status": "ok", "service": "KCSC_AI_FAC", "version": "1.0.0"}
