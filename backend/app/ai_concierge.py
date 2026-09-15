"""Natural-language front door: turns free text like "Pay my daughter's
school fees" into a structured service-request draft for the human to
review and submit. This never creates or submits a request itself - it
only returns a suggestion the customer sees and can edit before anything
is sent ("AI never initiates money movement directly" per the platform's
own rule for AI).
"""

import json
import logging

from openai import OpenAI

from .config import settings
from .models import Beneficiary, ServiceCategory

logger = logging.getLogger(__name__)

_VALID_CATEGORIES = [c.value for c in ServiceCategory]

_SYSTEM_PROMPT = (
    "You are the intake assistant for MidMan, a concierge platform. A customer "
    "describes something they need done in their own words. Turn it into a "
    "structured draft request.\n\n"
    f"- category must be exactly one of: {', '.join(_VALID_CATEGORIES)}\n"
    "- title: a short (under 60 char) summary\n"
    "- description: fuller detail, or null if the text has nothing beyond the title\n"
    "- if the text names a person the request is for, and that name matches one of "
    "the customer's existing beneficiaries listed below, return that beneficiary's id "
    "in beneficiary_id; otherwise, if a person is named but doesn't match anyone, put "
    "their name in beneficiary_name_hint and leave beneficiary_id null\n"
    "- amount: a plain number if a specific amount is mentioned, else null\n"
    "- missing_info: a short list (0-3 items) of the most important missing details "
    "a human would need to know before this could be actioned - e.g. an exact amount, "
    "a deadline, a school name. Empty list if nothing important is missing.\n\n"
    'Respond with strict JSON: {"category": ..., "title": ..., "description": ..., '
    '"beneficiary_id": ..., "beneficiary_name_hint": ..., "amount": ..., "missing_info": [...]}'
)


def _fallback(text: str, reason: str) -> dict:
    return {
        "category": "other",
        "title": (text.strip()[:60] or "New request"),
        "description": None,
        "beneficiary_id": None,
        "beneficiary_name_hint": None,
        "amount": None,
        "missing_info": [reason],
        "ai_available": False,
    }


def parse_request_text(text: str, beneficiaries: list[Beneficiary]) -> dict:
    if not text.strip():
        return _fallback(text, "Tell us what you need done.")

    if not settings.openai_api_key:
        return _fallback(text, "AI assistance isn't available right now - please fill in the details below.")

    try:
        client = OpenAI(api_key=settings.openai_api_key)
        beneficiary_context = (
            "\n".join(f"- id={b.id}, name={b.full_name}, relationship={b.relationship_type}" for b in beneficiaries)
            or "(none saved)"
        )

        response = client.chat.completions.create(
            model=settings.openai_model,
            messages=[
                {"role": "system", "content": _SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": f"Customer's saved beneficiaries:\n{beneficiary_context}\n\nRequest: {text}",
                },
            ],
            response_format={"type": "json_object"},
            timeout=15,
        )
        result = json.loads(response.choices[0].message.content)

        category = result.get("category")
        if category not in _VALID_CATEGORIES:
            category = "other"

        # The model may hallucinate an id - only trust it if it's actually
        # one of this customer's own beneficiaries.
        beneficiary_id = result.get("beneficiary_id")
        valid_ids = {str(b.id) for b in beneficiaries}
        if beneficiary_id not in valid_ids:
            beneficiary_id = None

        title = (result.get("title") or text.strip()[:60] or "New request")[:200]

        return {
            "category": category,
            "title": title,
            "description": result.get("description"),
            "beneficiary_id": beneficiary_id,
            "beneficiary_name_hint": result.get("beneficiary_name_hint"),
            "amount": result.get("amount"),
            "missing_info": result.get("missing_info") or [],
            "ai_available": True,
        }
    except Exception:
        logger.exception("AI request parsing failed")
        return _fallback(text, "AI assistance hit an error - please check the details below.")
