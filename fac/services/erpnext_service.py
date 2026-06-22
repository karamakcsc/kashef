"""
Async HTTP client for ERPNext REST API.
Handles authentication, doctype CRUD, and mobile-access method calls.
"""
from typing import Any
import httpx
from ..config import get_settings

settings = get_settings()

_AUTH_HEADERS = {
    "Authorization": f"token {settings.erpnext_api_key}:{settings.erpnext_api_secret}",
    "Content-Type": "application/json",
}


class ERPNextService:
    def __init__(self):
        self._client = httpx.AsyncClient(
            base_url=settings.erpnext_url,
            headers=_AUTH_HEADERS,
            timeout=30.0,
        )

    # ── Generic CRUD ──────────────────────────────────────────────────────────

    async def get_doc(self, doctype: str, name: str) -> dict:
        r = await self._client.get(f"/api/resource/{doctype}/{name}")
        r.raise_for_status()
        return r.json().get("data", {})

    async def get_list(
        self,
        doctype: str,
        filters: dict | None = None,
        fields: list[str] | None = None,
        limit: int = 20,
        order_by: str | None = None,
    ) -> list[dict]:
        params: dict[str, Any] = {"limit_page_length": limit}
        if filters:
            import json
            params["filters"] = json.dumps(filters)
        if fields:
            import json
            params["fields"] = json.dumps(fields)
        if order_by:
            params["order_by"] = order_by
        r = await self._client.get(f"/api/resource/{doctype}", params=params)
        r.raise_for_status()
        return r.json().get("data", [])

    async def create_doc(self, doctype: str, data: dict) -> dict:
        r = await self._client.post(f"/api/resource/{doctype}", json=data)
        r.raise_for_status()
        return r.json().get("data", {})

    async def update_doc(self, doctype: str, name: str, data: dict) -> dict:
        r = await self._client.put(f"/api/resource/{doctype}/{name}", json=data)
        r.raise_for_status()
        return r.json().get("data", {})

    # ── User Auth via ERPNext ─────────────────────────────────────────────────

    async def authenticate_user(self, username: str, password: str) -> dict | None:
        """Returns user info dict or None on failure.

        Uses a throwaway session client (no API key headers) so the session
        cookie from /api/method/login is what identifies the user in the
        subsequent get_logged_user call — not the FAC's API key.
        """
        async with httpx.AsyncClient(
            base_url=settings.erpnext_url,
            timeout=30.0,
        ) as session_client:
            r = await session_client.post(
                "/api/method/login",
                data={"usr": username, "pwd": password},
            )
            if r.status_code != 200:
                return None
            user_r = await session_client.get(
                "/api/method/frappe.auth.get_logged_user"
            )
            if user_r.status_code != 200:
                return None
            user_email = user_r.json().get("message", "")
            if not user_email or user_email == "Guest":
                return None

        return await self.get_user_info(user_email)

    async def get_user_info(self, email: str) -> dict:
        data = await self.get_doc("User", email)
        roles_raw = await self._client.get(
            f"/api/resource/Has Role",
            params={"filters": f'[["parent","{email}"]]', "fields": '["role"]', "limit_page_length": 50},
        )
        roles = [r["role"] for r in roles_raw.json().get("data", [])]
        tenant_id = data.get("company", "default")
        return {
            "user_id": email,
            "email": email,
            "full_name": data.get("full_name", ""),
            "tenant_id": tenant_id,
            "roles": roles,
            "avatar": data.get("user_image", ""),
        }

    # ── Mobile API Methods ────────────────────────────────────────────────────

    async def validate_user_access(self, user: str, device_id: str) -> dict:
        r = await self._client.get(
            "/api/method/kcsc_erp.api.mobile_api.validate_user_access",
            params={"user": user, "device_id": device_id},
        )
        r.raise_for_status()
        return r.json().get("message", {})

    async def register_device(
        self,
        user: str,
        device_id: str,
        device_name: str,
        platform: str,
        app_version: str,
        ip_address: str = "",
    ) -> dict:
        r = await self._client.post(
            "/api/method/kcsc_erp.api.mobile_api.register_device",
            json={
                "user": user,
                "device_id": device_id,
                "device_name": device_name,
                "platform": platform,
                "app_version": app_version,
                "ip_address": ip_address,
            },
        )
        r.raise_for_status()
        return r.json().get("message", {})

    async def log_session_event(
        self,
        user: str,
        device_id: str,
        event: str,
        ip_address: str = "",
        session_name: str = "",
    ) -> dict:
        r = await self._client.post(
            "/api/method/kcsc_erp.api.mobile_api.log_session_event",
            json={
                "user": user,
                "device_id": device_id,
                "event": event,
                "ip_address": ip_address,
                "session_name": session_name,
            },
        )
        r.raise_for_status()
        return r.json().get("message", {})

    async def close(self):
        await self._client.aclose()
