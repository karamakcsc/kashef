from datetime import datetime
from sqlalchemy import Boolean, Column, DateTime, Enum, ForeignKey, Integer, String, Text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase, relationship
from ..config import get_settings

settings = get_settings()

engine = create_async_engine(settings.database_url, echo=settings.debug, pool_pre_ping=True)
AsyncSessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


async def get_db():
    async with AsyncSessionLocal() as session:
        yield session


class DeviceModel(Base):
    __tablename__ = "mobile_devices"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(String(255), nullable=False, index=True)
    tenant_id = Column(String(255), nullable=False, index=True)
    device_id = Column(String(36), unique=True, nullable=False, index=True)
    device_name = Column(String(255))
    platform = Column(Enum("Android", "iOS", name="platform_enum"), nullable=False)
    app_version = Column(String(50))
    last_login = Column(DateTime, default=datetime.utcnow)
    status = Column(Enum("Active", "Blocked", "Pending", name="device_status_enum"), default="Pending")
    is_trusted = Column(Boolean, default=False)
    ip_address = Column(String(45))
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    sessions = relationship("SessionModel", back_populates="device", cascade="all, delete-orphan")


class SessionModel(Base):
    __tablename__ = "mobile_sessions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(String(255), nullable=False, index=True)
    tenant_id = Column(String(255), nullable=False, index=True)
    device_id = Column(String(36), ForeignKey("mobile_devices.device_id"), nullable=False)
    jti = Column(String(36), unique=True, nullable=False, index=True)  # JWT ID for blacklisting
    access_token = Column(Text, nullable=False)
    refresh_token = Column(Text)
    login_time = Column(DateTime, default=datetime.utcnow)
    logout_time = Column(DateTime, nullable=True)
    ip_address = Column(String(45))
    status = Column(Enum("Active", "Revoked", "Expired", name="session_status_enum"), default="Active")
    created_at = Column(DateTime, default=datetime.utcnow)

    device = relationship("DeviceModel", back_populates="sessions")


class TokenBlacklistModel(Base):
    __tablename__ = "token_blacklist"

    id = Column(Integer, primary_key=True, index=True)
    jti = Column(String(36), unique=True, nullable=False, index=True)
    user_id = Column(String(255), nullable=False)
    device_id = Column(String(36), nullable=False)
    blacklisted_at = Column(DateTime, default=datetime.utcnow)
    expires_at = Column(DateTime, nullable=False)
