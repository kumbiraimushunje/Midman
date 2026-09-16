"""International card payments via Flutterwave's v3 REST API
(https://developer.flutterwave.com). No SDK needed - it's a plain REST API,
and this project already depends on httpx.
"""

import logging

import httpx

from .config import settings

logger = logging.getLogger(__name__)

_BASE_URL = "https://api.flutterwave.com/v3"


def is_configured() -> bool:
    return bool(settings.flutterwave_secret_key)


def _headers() -> dict:
    return {"Authorization": f"Bearer {settings.flutterwave_secret_key}", "Content-Type": "application/json"}


def create_checkout(reference: str, email: str, name: str, amount: float, currency: str, title: str) -> dict:
    """Returns {success, checkout_url, error}. checkout_url is Flutterwave's
    hosted payment page - the client just opens it in a browser."""
    if not is_configured():
        return {"success": False, "checkout_url": None, "error": "Flutterwave isn't configured"}

    payload = {
        "tx_ref": reference,
        "amount": str(amount),
        "currency": currency,
        "redirect_url": settings.payment_return_url,
        "customer": {"email": email, "name": name},
        "customizations": {"title": title},
    }
    try:
        res = httpx.post(f"{_BASE_URL}/payments", json=payload, headers=_headers(), timeout=15)
        data = res.json()
        if res.status_code == 200 and data.get("status") == "success":
            return {"success": True, "checkout_url": data["data"]["link"], "error": None}
        return {"success": False, "checkout_url": None, "error": data.get("message", "Flutterwave rejected the request")}
    except httpx.HTTPError:
        logger.exception("Flutterwave checkout creation failed")
        return {"success": False, "checkout_url": None, "error": "Could not reach Flutterwave"}


def verify_transaction(transaction_id: str) -> dict:
    """Always re-verify server-side with Flutterwave's own API rather than
    trusting a webhook body directly - their documented recommendation
    against forged or tampered callbacks."""
    try:
        res = httpx.get(f"{_BASE_URL}/transactions/{transaction_id}/verify", headers=_headers(), timeout=15)
        data = res.json()
        if res.status_code == 200 and data.get("status") == "success":
            d = data["data"]
            return {
                "success": True,
                "status": d.get("status"),
                "amount": d.get("amount"),
                "currency": d.get("currency"),
                "tx_ref": d.get("tx_ref"),
            }
        return {"success": False, "status": None, "amount": None, "currency": None, "tx_ref": None}
    except httpx.HTTPError:
        logger.exception("Flutterwave transaction verification failed")
        return {"success": False, "status": None, "amount": None, "currency": None, "tx_ref": None}


def verify_webhook_signature(received_hash: str | None) -> bool:
    """The verif-hash header must exactly match the secret hash string you
    set in the Flutterwave dashboard's webhook settings - a plain shared
    secret comparison, not an HMAC over the body."""
    if not received_hash or not settings.flutterwave_webhook_secret_hash:
        return False
    return received_hash == settings.flutterwave_webhook_secret_hash
