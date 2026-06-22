"""
WebSocket connection manager.
Handles per-device connections, force-logout fan-out, and Redis pub/sub relay.
"""
import asyncio
import json
from datetime import datetime
from typing import Dict
from fastapi import WebSocket
import redis.asyncio as aioredis
from ..models.schemas import WSMessage, WSMessageType
from ..config import get_settings

settings = get_settings()


class ConnectionManager:
    def __init__(self):
        # device_id → WebSocket
        self._connections: Dict[str, WebSocket] = {}
        # device_id → user_id (reverse lookup for fan-out)
        self._device_user: Dict[str, str] = {}

    # ── Lifecycle ─────────────────────────────────────────────────────────────

    async def connect(self, websocket: WebSocket, device_id: str, user_id: str):
        await websocket.accept()
        self._connections[device_id] = websocket
        self._device_user[device_id] = user_id

    def disconnect(self, device_id: str):
        self._connections.pop(device_id, None)
        self._device_user.pop(device_id, None)

    # ── Send helpers ──────────────────────────────────────────────────────────

    async def send_to_device(self, device_id: str, message: WSMessage) -> bool:
        ws = self._connections.get(device_id)
        if ws:
            try:
                await ws.send_text(message.model_dump_json())
                return True
            except Exception:
                self.disconnect(device_id)
        return False

    async def send_to_user(self, user_id: str, message: WSMessage):
        """Broadcast to every device belonging to user_id."""
        targets = [d for d, u in self._device_user.items() if u == user_id]
        await asyncio.gather(*[self.send_to_device(d, message) for d in targets])

    async def broadcast(self, message: WSMessage):
        for device_id in list(self._connections.keys()):
            await self.send_to_device(device_id, message)

    # ── Force logout ──────────────────────────────────────────────────────────

    async def force_logout_user(self, user_id: str, reason: str = ""):
        msg = WSMessage(
            type=WSMessageType.force_logout,
            payload={"reason": reason, "timestamp": datetime.utcnow().isoformat()},
        )
        await self.send_to_user(user_id, msg)

    # ── Redis pub/sub relay ───────────────────────────────────────────────────

    async def start_redis_listener(self, redis_client: aioredis.Redis, tenant_id: str):
        """
        Subscribe to force_logout channels on Redis.
        FAC publishes when admin triggers force-logout from ERPNext.
        """
        pubsub = redis_client.pubsub()
        await pubsub.psubscribe(f"force_logout:{tenant_id}:*")

        async for message in pubsub.listen():
            if message["type"] != "pmessage":
                continue
            channel: str = message["channel"].decode()
            # channel = "force_logout:<tenant>:<user>"
            parts = channel.split(":")
            if len(parts) == 3:
                user_id = parts[2]
                await self.force_logout_user(user_id, reason="Admin force logout")


# Singleton — shared across all request handlers
manager = ConnectionManager()
