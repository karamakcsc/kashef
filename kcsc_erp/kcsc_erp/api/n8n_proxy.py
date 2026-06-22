"""
n8n Chat Proxy — KCSC ERPNext
Whitelisted endpoint that forwards Flutter chat messages to the n8n webhook.

Architecture:
    Flutter Web/Mobile
        ↓  (same-origin, no CORS)
    POST /api/method/kcsc_erp.api.n8n_proxy.chat
        ↓  (server-side HTTP, no CORS)
    n8n webhook

Frappe route: kcsc_erp.api.n8n_proxy.chat
"""

import frappe

try:
    import requests as _requests
    _REQUESTS_OK = True
except ImportError:
    _REQUESTS_OK = False

# ── Configuration ─────────────────────────────────────────────────────────────

_N8N_WEBHOOK_URL = (
    "https://n8n.kcsc.com.jo"
    "/webhook/df559bcb-aa2d-4e83-9fea-55fc63c2cd9d/chat"
)
_TIMEOUT_S = 30
_MAX_RETRIES = 2


# ── Public endpoint ───────────────────────────────────────────────────────────

@frappe.whitelist()
def chat(message, session_id=None, language="ar"):
    """
    Forward a chat message to the n8n webhook and return the reply.

    Request  (from Flutter via ApiService.postForm):
        message    str  — user's message text (required)
        session_id str  — conversation session ID
        language   str  — 'ar' | 'en'

    Response (Frappe wraps this in {"message": ...}):
        {"output": "<bot reply text>"}
    """
    if not _REQUESTS_OK:
        frappe.log_error(
            "requests library is not installed on this server.",
            "n8n Proxy — Configuration",
        )
        frappe.throw(
            "Chat proxy is not configured. Contact your administrator.",
            title="Configuration Error",
        )

    msg = (message or "").strip()
    if not msg:
        frappe.throw("message is required.", title="Validation Error")

    payload = {
        "message": msg,
        "session_id": str(session_id or ""),
        "language": str(language or "ar"),
    }

    last_exc = None
    for attempt in range(1, _MAX_RETRIES + 2):   # attempts: 1, 2, 3
        try:
            resp = _requests.post(
                _N8N_WEBHOOK_URL,
                json=payload,
                timeout=_TIMEOUT_S,
                headers={
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                },
            )
            resp.raise_for_status()

            return {"output": _extract_output(resp)}

        except _requests.Timeout as exc:
            last_exc = exc
            frappe.log_error(
                f"n8n proxy: timeout on attempt {attempt}",
                "n8n Proxy",
            )
            # Retry on timeout
            continue

        except _requests.ConnectionError as exc:
            last_exc = exc
            frappe.log_error(
                f"n8n proxy: connection error on attempt {attempt} — {exc}",
                "n8n Proxy",
            )
            continue

        except _requests.HTTPError as exc:
            # Do not retry on 4xx client errors
            status = resp.status_code
            frappe.log_error(
                f"n8n proxy: HTTP {status} — {resp.text[:500]}",
                "n8n Proxy",
            )
            frappe.throw(
                f"Chat service returned an error ({status}). Please try again.",
                title="Service Error",
            )

        except Exception as exc:  # noqa: BLE001
            last_exc = exc
            frappe.log_error(
                f"n8n proxy: unexpected error — {exc}",
                "n8n Proxy",
            )
            continue

    # All retries exhausted
    frappe.log_error(
        f"n8n proxy: all {_MAX_RETRIES + 1} attempts failed — {last_exc}",
        "n8n Proxy",
    )
    frappe.throw(
        "Could not reach the chat service after multiple attempts. "
        "Please check your connection and try again.",
        title="Connection Error",
    )


# ── Helpers ───────────────────────────────────────────────────────────────────

def _extract_output(resp) -> str:
    """Parse the n8n response and return the reply text."""
    try:
        data = resp.json()
    except ValueError:
        return resp.text or ""

    if isinstance(data, dict):
        return str(
            data.get("output")
            or data.get("text")
            or data.get("message")
            or data.get("response")
            or data.get("answer")
            or ""
        )

    if isinstance(data, list) and data:
        first = data[0]
        if isinstance(first, dict):
            return str(first.get("output") or first.get("text") or "")
        return str(first)

    return str(data) if data else ""
