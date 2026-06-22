import frappe
from frappe.model.document import Document


class MobileAccessSettings(Document):
    pass


@frappe.whitelist()
def get_ai_settings():
    """Return the active AI provider and model. Never exposes raw API keys."""
    doc = frappe.get_single("Mobile Access Settings")

    provider_id = "anthropic" if doc.ai_provider == "Anthropic" else "openai"

    default_models = {
        "anthropic": "claude-sonnet-4-6",
        "openai": "gpt-4o",
    }
    model = doc.default_ai_model or default_models[provider_id]

    return {
        "ai_provider": provider_id,
        "default_model": model,
    }


@frappe.whitelist()
def get_provider_api_key(provider: str):
    """
    Returns the decrypted API key for the requested provider.
    Only accessible by System Manager — used by server-side AI calls, not mobile.
    """
    frappe.only_for("System Manager")
    doc = frappe.get_single("Mobile Access Settings")
    if provider == "anthropic":
        return doc.get_password("anthropic_api_key")
    elif provider == "openai":
        return doc.get_password("openai_api_key")
    frappe.throw(f"Unknown provider: {provider}")
