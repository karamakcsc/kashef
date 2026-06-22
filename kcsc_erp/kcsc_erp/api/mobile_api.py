"""
KCSC ERPNext Mobile API
Whitelisted endpoints called by FAC (authenticated via API key/secret).
All methods require a valid Frappe session or token — no allow_guest.
"""
import frappe
from frappe import _
from datetime import datetime, timezone


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── Access Validation ─────────────────────────────────────────────────────────

@frappe.whitelist()
def validate_user_access(user: str, device_id: str) -> dict:
    """
    Called by FAC on every login attempt.
    Returns the access policy for the given user/device pair.
    """
    settings = frappe.get_single("Mobile Access Settings")

    if not settings.enable_mobile_access:
        return {"allowed": False, "reason": "MOBILE_ACCESS_DISABLED"}

    # User-level override
    access_name = frappe.db.get_value("User Mobile Access", {"user": user}, "name")
    if access_name:
        access = frappe.get_doc("User Mobile Access", access_name)
        if not access.mobile_access_enabled:
            return {"allowed": False, "reason": "USER_ACCESS_DISABLED"}

    # Device check
    device = frappe.db.get_value(
        "Mobile Device",
        {"user": user, "device_id": device_id},
        ["status", "is_trusted"],
        as_dict=True,
    )

    if not device:
        active_count = frappe.db.count(
            "Mobile Device",
            {"user": user, "status": ["in", ["Active", "Pending"]]},
        )
        if active_count >= (settings.max_devices_per_user or 3):
            return {"allowed": False, "reason": "MAX_DEVICES_REACHED"}

        return {
            "allowed": True,
            "device_status": "new",
            "require_approval": bool(settings.require_device_approval),
        }

    if device.status == "Blocked":
        return {"allowed": False, "reason": "DEVICE_BLOCKED"}

    if device.status == "Pending":
        return {"allowed": False, "reason": "DEVICE_PENDING"}

    return {
        "allowed": True,
        "device_status": device.status,
        "is_trusted": bool(device.is_trusted),
        "require_approval": False,
    }


# ── Device Registration ───────────────────────────────────────────────────────

@frappe.whitelist()
def register_device(
    user: str,
    device_id: str,
    device_name: str,
    platform: str,
    app_version: str,
    ip_address: str = "",
) -> dict:
    """Upsert a Mobile Device record. Called by FAC after successful auth."""
    settings = frappe.get_single("Mobile Access Settings")
    initial_status = "Pending" if settings.require_device_approval else "Active"

    # Use frappe.db.get_value to get the document name — NEVER pass dict to set_value
    existing_name = frappe.db.get_value(
        "Mobile Device", {"device_id": device_id}, "name"
    )

    if existing_name:
        frappe.db.set_value(
            "Mobile Device",
            existing_name,
            {
                "last_login": _now(),
                "app_version": app_version,
                "ip_address": ip_address,
            },
        )
    else:
        doc = frappe.get_doc({
            "doctype": "Mobile Device",
            "user": user,
            "device_id": device_id,
            "device_name": device_name,
            "platform": platform,
            "app_version": app_version,
            "ip_address": ip_address,
            "status": initial_status,
            "last_login": _now(),
        })
        doc.insert(ignore_permissions=True)

    frappe.db.commit()
    return {"status": initial_status if not existing_name else "updated"}


# ── Session Logging ───────────────────────────────────────────────────────────

@frappe.whitelist()
def log_session_event(
    user: str,
    device_id: str,
    event: str,
    ip_address: str = "",
    session_name: str = "",
) -> dict:
    """
    Record a session lifecycle event.
    event: 'login' | 'logout' | 'force_logout' | 'expired'
    """
    if event == "login":
        doc = frappe.get_doc({
            "doctype": "Mobile Session Log",
            "user": user,
            "device_id": device_id,
            "login_time": _now(),
            "ip_address": ip_address,
            "status": "Active",
        })
        doc.insert(ignore_permissions=True)
        frappe.db.commit()
        return {"log_name": doc.name}

    status_map = {
        "logout": "LoggedOut",
        "force_logout": "ForceLogout",
        "expired": "Expired",
    }
    if event in status_map and session_name:
        frappe.db.set_value(
            "Mobile Session Log",
            session_name,  # actual document name (hash), not a dict
            {
                "logout_time": _now(),
                "status": status_map[event],
            },
        )
        frappe.db.commit()

    return {"ok": True}


# ── Force Logout ──────────────────────────────────────────────────────────────

@frappe.whitelist()
def trigger_force_logout(user: str) -> dict:
    """Admin endpoint — sets force_logout flag on User Mobile Access."""
    access_name = frappe.db.get_value(
        "User Mobile Access", {"user": user}, "name"
    )

    if not access_name:
        doc = frappe.get_doc({
            "doctype": "User Mobile Access",
            "user": user,
            "mobile_access_enabled": 1,
        })
        doc.insert(ignore_permissions=True)
        access_name = doc.name

    # Use the document name string — never a dict
    frappe.db.set_value("User Mobile Access", access_name, "force_logout", 1)
    frappe.db.commit()

    frappe.publish_realtime(
        event="force_logout",
        message={"user": user},
        user=user,
    )
    return {"status": "force_logout_triggered"}


# ── Scheduled Tasks ───────────────────────────────────────────────────────────

def cleanup_expired_sessions():
    """Mark sessions inactive after 30 days — runs daily."""
    frappe.db.sql(
        """
        UPDATE `tabMobile Session Log`
        SET status = 'Expired'
        WHERE status = 'Active'
          AND login_time < DATE_SUB(NOW(), INTERVAL 30 DAY)
        """
    )
    frappe.db.commit()


def sync_device_status():
    """Placeholder for FAC → ERPNext device sync heartbeat."""
    pass


# ── Doc Event Handlers ────────────────────────────────────────────────────────

_SYSTEM_USERS = {"Guest", "Administrator"}

def on_user_update(doc, method=None):
    """
    Ensure a UserMobileAccess record exists for every real user.
    Guards against system users and recursive calls.
    """
    if doc.name in _SYSTEM_USERS:
        return

    # Skip users that are not of type "System User" (e.g. Website User)
    if getattr(doc, "user_type", None) not in (None, "System User"):
        return

    if not frappe.db.exists("User Mobile Access", {"user": doc.name}):
        try:
            frappe.get_doc({
                "doctype": "User Mobile Access",
                "user": doc.name,
                "mobile_access_enabled": 1,
            }).insert(ignore_permissions=True)
            frappe.db.commit()
        except frappe.exceptions.DuplicateEntryError:
            # Race condition — record was inserted by a parallel request
            pass
