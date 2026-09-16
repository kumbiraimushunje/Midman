"""Zimbabwe-local payments (EcoCash/OneMoney/ZimSwitch/local bank cards) via
Paynow (paynow.co.zw), using their official Python SDK for outbound calls.

Two things the SDK (as published, v1.0.8) doesn't handle correctly, worked
around here rather than trusted:
- `InitResponse.error` is never actually set on a failed response (the
  __init__ returns early before reaching that line) - read `.data["error"]`
  (the raw dict, always populated) instead.
- `process_status_update()`, meant for parsing the inbound result-url
  webhook, is an unimplemented stub ("Not implemented"). Webhook
  verification is done by hand below, following Paynow's documented
  algorithm: https://developers.paynow.co.zw/docs/paynow/validating_hash/
"""

import hashlib
import logging

from paynow import HashMismatchException, Paynow

from .config import settings

logger = logging.getLogger(__name__)


def _client() -> Paynow:
    return Paynow(
        settings.paynow_integration_id,
        settings.paynow_integration_key,
        settings.payment_return_url,
        settings.paynow_result_url,
    )


def is_configured() -> bool:
    return bool(
        settings.paynow_integration_id
        and settings.paynow_integration_key
        and settings.payment_return_url
        and settings.paynow_result_url
    )


def create_checkout(reference: str, email: str, description: str, amount: float) -> dict:
    """Web-redirect flow: Paynow's own hosted page, where the customer picks
    EcoCash/OneMoney/card. Returns {success, redirect_url, poll_url, error}."""
    if not is_configured():
        return {"success": False, "redirect_url": None, "poll_url": None, "error": "Paynow isn't configured"}

    try:
        paynow = _client()
        payment = paynow.create_payment(reference, email)
        payment.add(description, amount)
        response = paynow.send(payment)
        if not response.success:
            return {"success": False, "redirect_url": None, "poll_url": None, "error": response.data.get("error", "Paynow rejected the request")}
        return {"success": True, "redirect_url": getattr(response, "redirect_url", None), "poll_url": response.poll_url, "error": None}
    except (ValueError, HashMismatchException) as e:
        logger.exception("Paynow web checkout failed")
        return {"success": False, "redirect_url": None, "poll_url": None, "error": str(e)}
    except Exception:
        logger.exception("Paynow web checkout failed")
        return {"success": False, "redirect_url": None, "poll_url": None, "error": "Could not reach Paynow"}


def create_mobile_checkout(reference: str, email: str, description: str, amount: float, phone: str, method: str) -> dict:
    """EcoCash/OneMoney express checkout - the customer approves a USSD/app
    prompt on their own phone, no browser redirect needed."""
    if not is_configured():
        return {"success": False, "poll_url": None, "instructions": None, "error": "Paynow isn't configured"}

    try:
        paynow = _client()
        payment = paynow.create_payment(reference, email)
        payment.add(description, amount)
        response = paynow.send_mobile(payment, phone, method)
        if not response.success:
            return {"success": False, "poll_url": None, "instructions": None, "error": response.data.get("error", "Paynow rejected the request")}
        return {
            "success": True,
            "poll_url": response.poll_url,
            "instructions": response.data.get("instructions"),
            "error": None,
        }
    except (ValueError, HashMismatchException) as e:
        logger.exception("Paynow mobile checkout failed")
        return {"success": False, "poll_url": None, "instructions": None, "error": str(e)}
    except Exception:
        logger.exception("Paynow mobile checkout failed")
        return {"success": False, "poll_url": None, "instructions": None, "error": "Could not reach Paynow"}


def check_status(poll_url: str) -> dict:
    """Independent, server-initiated status check - used as a fallback when a
    customer returns to the app before the webhook has arrived."""
    try:
        status = _client().check_transaction_status(poll_url)
        return {"success": True, "paid": status.paid, "status": status.status}
    except Exception:
        logger.exception("Paynow status poll failed")
        return {"success": False, "paid": False, "status": None}


def verify_result_hash(fields: list[tuple[str, str]]) -> bool:
    """Validates the hash on an inbound resulturl webhook POST. `fields` is
    the body's key/value pairs in the order Paynow sent them (already
    url-decoded by the framework's form parser) - concatenate every value
    except 'hash' in that order, append the integration key, SHA512, compare
    as uppercase hex. Mirrors the (working) outbound __hash() in the SDK,
    including its otherwise-unexplained .lower() on the integration key."""
    received_hash = None
    concatenated = ""
    for key, value in fields:
        if key.lower() == "hash":
            received_hash = value
            continue
        concatenated += value
    if not received_hash:
        return False
    concatenated += settings.paynow_integration_key.lower()
    computed = hashlib.sha512(concatenated.encode("utf-8")).hexdigest().upper()
    return computed == received_hash.upper()
