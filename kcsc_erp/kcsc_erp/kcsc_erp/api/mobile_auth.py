"""
Frappe-native mobile authentication.

Provides a single guest-accessible login endpoint that:
  1. Validates ERPNext credentials
  2. Enforces device-binding / access policy (via kcsc_erp logic)
  3. Issues a 64-char opaque session token stored on the Mobile Device record

All subsequent API calls from the mobile app carry:
  Authorization: Bearer <token>

A before_request hook (registered in hooks.py) validates the token and sets
frappe.session.user before any whitelisted method runs.
"""

import frappe
from frappe import _
from frappe.utils import now_datetime, add_days

_TOKEN_BYTES = 64
_TOKEN_EXPIRY_DAYS = 30


# ── Public endpoints ──────────────────────────────────────────────────────────

@frappe.whitelist(allow_guest=True)
def mobile_login(
    username,
    password,
    device_id,
    device_name,
    platform,
    app_version,
    ip_address="",
):
    """
    Mobile login — returns a Bearer token and user info on success.

    Error reasons returned as HTTP 403 detail string:
      DEVICE_BLOCKED | DEVICE_PENDING | MOBILE_ACCESS_DISABLED |
      MAX_DEVICES_REACHED | USER_ACCESS_DISABLED
    HTTP 202 is used for DEVICE_PENDING.
    """
    # ── 1. Validate credentials ───────────────────────────────────────────────
    try:
        login_manager = frappe.auth.LoginManager()
        login_manager.authenticate(user=username, pwd=password)
        login_manager.post_login()
    except frappe.exceptions.AuthenticationError:
        frappe.response.http_status_code = 401
        frappe.throw(_("Invalid credentials"), frappe.AuthenticationError)

    user = frappe.session.user
    if not user or user == "Guest":
        frappe.response.http_status_code = 401
        frappe.throw(_("Invalid credentials"), frappe.AuthenticationError)

    # ── 2. Device / access policy check ──────────────────────────────────────
    from .mobile_api import validate_user_access, register_device, log_session_event

    access = validate_user_access(user, device_id)
    if not access.get("allowed"):
        reason = access.get("reason", "ACCESS_DENIED")
        frappe.response.http_status_code = 202 if reason == "DEVICE_PENDING" else 403
        frappe.throw(reason, frappe.PermissionError)

    # ── 3. Register / update device ───────────────────────────────────────────
    register_device(user, device_id, device_name, platform, app_version, ip_address)

    # ── 4. Issue session token ────────────────────────────────────────────────
    token = frappe.generate_hash(length=_TOKEN_BYTES)
    expiry = add_days(now_datetime(), _TOKEN_EXPIRY_DAYS)

    device_name_val = frappe.db.get_value("Mobile Device", {"device_id": device_id}, "name")
    if device_name_val:
        frappe.db.set_value(
            "Mobile Device",
            device_name_val,
            {"session_token": token, "token_expiry": expiry},
        )
        frappe.db.commit()

    # ── 5. Log session ────────────────────────────────────────────────────────
    try:
        log_session_event(user, device_id, "login", ip_address)
    except Exception:
        pass

    # ── 6. Build response ─────────────────────────────────────────────────────
    user_doc = frappe.get_doc("User", user)
    roles = frappe.get_roles(user)
    company = (
        frappe.db.get_single_value("Global Defaults", "default_company") or "default"
    )

    return {
        "access_token": token,
        "refresh_token": token,   # same token — no JWT refresh needed
        "token_type": "bearer",
        "expires_in": _TOKEN_EXPIRY_DAYS * 86400,
        "user": {
            "user_id": user,
            "email": user,
            "full_name": user_doc.full_name or user,
            "tenant_id": company,
            "roles": roles,
            "avatar": user_doc.user_image or "",
            "device_id": device_id,
        },
        "device_status": access.get("device_status", "Active"),
    }


@frappe.whitelist()
def mobile_logout(device_id=""):
    """Revoke the session token for the calling device."""
    if not device_id:
        device_id = frappe.get_request_header("X-Device-Id", "")

    if device_id:
        device_name_val = frappe.db.get_value(
            "Mobile Device", {"device_id": device_id}, "name"
        )
        if device_name_val:
            frappe.db.set_value(
                "Mobile Device",
                device_name_val,
                {"session_token": None, "token_expiry": None},
            )
            frappe.db.commit()

    return {"ok": True}


# ── before_request hook ───────────────────────────────────────────────────────

def authenticate_mobile_request():
    """
    Registered as before_request in hooks.py.

    Validates a Bearer token issued by mobile_login() and sets
    frappe.session.user so all subsequent @frappe.whitelist() calls
    work as if the user is normally logged in.
    """
    auth_header = frappe.get_request_header("Authorization") or ""
    if not auth_header.startswith("Bearer "):
        return  # not a mobile token — let Frappe handle other auth types

    token = auth_header[7:].strip()
    if not token:
        return

    device = frappe.db.get_value(
        "Mobile Device",
        {"session_token": token},
        ["user", "token_expiry", "status"],
        as_dict=True,
    )

    if not device:
        return  # unknown token — Frappe will deny access naturally

    if device.status == "Blocked":
        frappe.response.http_status_code = 403
        frappe.throw("DEVICE_BLOCKED", frappe.PermissionError)

    if device.token_expiry and now_datetime() > device.token_expiry:
        frappe.response.http_status_code = 401
        frappe.throw("TOKEN_EXPIRED", frappe.AuthenticationError)

    frappe.set_user(device.user)
