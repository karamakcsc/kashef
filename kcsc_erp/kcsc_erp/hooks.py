app_name = "kcsc_erp"
app_title = "KCSC ERP"
app_publisher = "KCSC"
app_description = "KCSC AI Platform - ERPNext Extension"
app_version = "1.0.0"
# Use a Font Awesome icon (Bootstrap icons also accepted in v15/v16)
app_icon = "fa fa-mobile-phone"
app_color = "#1E3A5F"
app_email = "admin@kcsc.com"
app_license = "MIT"

# ── Mobile Bearer Token Auth ──────────────────────────────────────────────────
before_request = [
    "kcsc_erp.kcsc_erp.api.mobile_auth.authenticate_mobile_request",
]

# ── Document Events ───────────────────────────────────────────────────────────
doc_events = {
    "User": {
        "on_update": "kcsc_erp.api.mobile_api.on_user_update",
    },
}

# ── Scheduled Tasks ───────────────────────────────────────────────────────────
scheduler_events = {
    "daily": [
        "kcsc_erp.api.mobile_api.cleanup_expired_sessions",
    ],
    "hourly": [
        "kcsc_erp.api.mobile_api.sync_device_status",
    ],
}

# ── Fixtures ──────────────────────────────────────────────────────────────────
fixtures = [
    "Mobile Access Settings",
]
