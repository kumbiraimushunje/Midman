"""AI fraud/risk triage for a newly created service request.

This is a triage signal for the human approver/staff, never an automated
decision - approve/reject and execution stay entirely manual. Runs as a
background task after the request is created so it never adds latency to
the create-request response, and degrades gracefully (leaves the fraud
fields null) if OPENAI_API_KEY is unset or the call fails.
"""

import json
import logging

from openai import OpenAI

from .config import settings
from .database import SessionLocal
from .models import ServiceRequest

logger = logging.getLogger(__name__)

_SYSTEM_PROMPT = (
    "You triage service/payment requests for a concierge platform. Given only "
    "the request details below (no requester history, no external data), rate "
    "how unusual or suspicious it looks and give ONE short sentence of "
    "reasoning. Respond with strict JSON: "
    '{"risk_level": "low"|"medium"|"high", "risk_score": 0-100, "reasoning": "..."}'
)


def run_fraud_check(request_id) -> None:
    if not settings.openai_api_key:
        return

    db = SessionLocal()
    try:
        req = db.query(ServiceRequest).filter(ServiceRequest.id == request_id).first()
        if req is None:
            return

        client = OpenAI(api_key=settings.openai_api_key)
        user_content = (
            f"Category: {req.category.value}\n"
            f"Title: {req.title}\n"
            f"Description: {req.description or '(none)'}\n"
            f"Amount: {req.amount if req.amount is not None else 'unknown'} {req.currency}"
        )

        response = client.chat.completions.create(
            model=settings.openai_model,
            messages=[
                {"role": "system", "content": _SYSTEM_PROMPT},
                {"role": "user", "content": user_content},
            ],
            response_format={"type": "json_object"},
            timeout=15,
        )
        result = json.loads(response.choices[0].message.content)

        from datetime import datetime

        req.fraud_risk_level = result.get("risk_level")
        req.fraud_risk_score = result.get("risk_score")
        req.fraud_reasoning = result.get("reasoning")
        req.fraud_checked_at = datetime.utcnow()
        db.commit()
    except Exception:
        logger.exception("Fraud check failed for request %s", request_id)
        db.rollback()
    finally:
        db.close()
