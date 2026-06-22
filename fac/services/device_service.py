from datetime import datetime
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update
from ..models.database import DeviceModel
from ..models.schemas import DeviceStatusEnum, PlatformEnum
from .erpnext_service import ERPNextService


class DeviceService:
    def __init__(self, db: AsyncSession, erp: ERPNextService):
        self._db = db
        self._erp = erp

    async def validate_and_register(
        self,
        user_id: str,
        tenant_id: str,
        device_id: str,
        device_name: str,
        platform: PlatformEnum,
        app_version: str,
        ip_address: str = "",
    ) -> dict:
        """
        Full login-time validation flow:
        1. Ask ERPNext for access policy
        2. Upsert device in FAC database
        3. Upsert device in ERPNext
        Returns {'allowed': bool, 'reason': str, 'device_status': DeviceStatusEnum}
        """
        # Step 1 — ERPNext policy check
        policy = await self._erp.validate_user_access(user_id, device_id)
        if not policy.get("allowed"):
            return {
                "allowed": False,
                "reason": policy.get("reason", "ACCESS_DENIED"),
                "device_status": DeviceStatusEnum.blocked,
            }

        # Step 2 — Upsert in FAC DB
        stmt = select(DeviceModel).where(DeviceModel.device_id == device_id)
        result = await self._db.execute(stmt)
        device = result.scalar_one_or_none()

        erp_status = policy.get("device_status", "new")
        initial_status = (
            DeviceStatusEnum.pending
            if (erp_status == "new" and policy.get("require_approval"))
            else DeviceStatusEnum.active
        )

        if device:
            device.last_login = datetime.utcnow()
            device.app_version = app_version
            device.ip_address = ip_address
            await self._db.commit()
            fac_status = device.status
        else:
            device = DeviceModel(
                user_id=user_id,
                tenant_id=tenant_id,
                device_id=device_id,
                device_name=device_name,
                platform=platform,
                app_version=app_version,
                ip_address=ip_address,
                status=initial_status,
                last_login=datetime.utcnow(),
            )
            self._db.add(device)
            await self._db.commit()
            fac_status = initial_status

        # Step 3 — Upsert in ERPNext (fire-and-forget style)
        await self._erp.register_device(
            user=user_id,
            device_id=device_id,
            device_name=device_name,
            platform=platform,
            app_version=app_version,
            ip_address=ip_address,
        )

        if fac_status == DeviceStatusEnum.blocked:
            return {"allowed": False, "reason": "DEVICE_BLOCKED", "device_status": fac_status}
        if fac_status == DeviceStatusEnum.pending:
            return {"allowed": False, "reason": "DEVICE_PENDING", "device_status": fac_status}

        return {"allowed": True, "reason": "OK", "device_status": fac_status}

    async def get_user_devices(self, user_id: str) -> list[DeviceModel]:
        stmt = select(DeviceModel).where(DeviceModel.user_id == user_id)
        result = await self._db.execute(stmt)
        return list(result.scalars().all())

    async def set_device_status(self, device_id: str, status: DeviceStatusEnum) -> None:
        stmt = (
            update(DeviceModel)
            .where(DeviceModel.device_id == device_id)
            .values(status=status)
        )
        await self._db.execute(stmt)
        await self._db.commit()

    async def count_active_devices(self, user_id: str) -> int:
        stmt = select(DeviceModel).where(
            DeviceModel.user_id == user_id,
            DeviceModel.status == DeviceStatusEnum.active,
        )
        result = await self._db.execute(stmt)
        return len(result.scalars().all())
