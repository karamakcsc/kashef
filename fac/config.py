from functools import lru_cache
from typing import List
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # App
    app_name: str = "KCSC_AI_FAC"
    app_env: str = "production"
    debug: bool = False
    secret_key: str
    api_v1_prefix: str = "/api/v1"

    # JWT
    jwt_secret_key: str
    jwt_algorithm: str = "HS256"
    jwt_access_token_expire_minutes: int = 30
    jwt_refresh_token_expire_days: int = 30

    # Database
    database_url: str
    sync_database_url: str

    # Redis
    redis_url: str = "redis://localhost:6379/0"

    # ERPNext
    erpnext_url: str
    erpnext_api_key: str
    erpnext_api_secret: str

    # AI Providers
    anthropic_api_key: str = ""
    openai_api_key: str = ""
    default_ai_provider: str = "anthropic"
    default_ai_model: str = "claude-sonnet-4-6"

    # WebSocket
    ws_heartbeat_interval: int = 30

    # CORS
    allowed_origins: List[str] = ["http://localhost:3000"]

    # Files
    max_file_size_mb: int = 50
    allowed_file_types: List[str] = ["pdf", "png", "jpg", "jpeg", "xlsx", "xls", "csv", "docx"]

    # OTP
    otp_issuer: str = "KCSC_AI"
    otp_validity_seconds: int = 300


@lru_cache
def get_settings() -> Settings:
    return Settings()
