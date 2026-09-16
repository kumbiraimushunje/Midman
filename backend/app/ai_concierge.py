"""Natural-language front door: turns free text like "Pay my daughter's
school fees" into a structured service-request draft for the human to
review and submit. This never creates or submits a request itself - it
only returns a suggestion the customer sees and can edit before anything
is sent ("AI never initiates money movement directly" per the platform's
own rule for AI).
"""

import base64
import io
import json
import logging

from openai import OpenAI
from pypdf import PdfReader

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


_INVOICE_SYSTEM_PROMPT = (
    "You are the intake assistant for MidMan, a concierge platform. A customer has "
    "uploaded an invoice or price quote (school fees, a medical bill, a supplier's "
    "quote, etc). Read it and turn it into a structured draft request - the same "
    "kind of draft you'd build from a typed description.\n\n"
    "This is a financial document a human will review before any money moves, so "
    "accuracy matters more than completeness: only report a vendor, amount, name, or "
    "any other detail you can actually read in the document. Never invent or guess "
    "plausible-sounding values that aren't really there.\n\n"
    "- legible: true only if this is genuinely readable as an invoice/quote with real "
    "content; false if the image/text is blank, unrelated, corrupted, or otherwise "
    "doesn't contain an actual invoice or quote to read. When false, every other field "
    "below should be null/empty/\"other\" - do not fabricate a plausible-looking result.\n"
    f"- category must be exactly one of: {', '.join(_VALID_CATEGORIES)}\n"
    "- title: a short (under 60 char) summary naming the vendor/institution and what it's for\n"
    "- description: the key line items and any reference/invoice number, or null if the "
    "document has nothing beyond the title\n"
    "- if the document names a person this is for (a student, a patient, etc), and that name "
    "matches one of the customer's existing beneficiaries listed below, return that "
    "beneficiary's id in beneficiary_id; otherwise, if a person is named but doesn't match "
    "anyone, put their name in beneficiary_name_hint and leave beneficiary_id null\n"
    "- amount: the total amount due, as a plain number, or null if no total is shown\n"
    "- missing_info: a short list (0-3 items) of the most important details a human would "
    "still need to confirm before this could be actioned - e.g. an unclear total, a missing "
    "due date. Empty list if the document is clear.\n\n"
    'Respond with strict JSON: {"legible": ..., "category": ..., "title": ..., "description": ..., '
    '"beneficiary_id": ..., "beneficiary_name_hint": ..., "amount": ..., "missing_info": [...]}'
)

_MAX_PDF_PAGES = 5


def _extract_pdf_text(contents: bytes) -> str:
    reader = PdfReader(io.BytesIO(contents))
    return "\n".join((page.extract_text() or "") for page in reader.pages[:_MAX_PDF_PAGES]).strip()


def parse_invoice_document(
    contents: bytes, filename: str, content_type: str, beneficiaries: list[Beneficiary]
) -> dict:
    """Reads an uploaded invoice/quote (a photo, or a text-based PDF) and turns it
    into the same kind of draft parse_request_text() builds from typed text - still
    never creates or submits anything itself. Scanned/image-only PDFs (no extractable
    text layer) aren't supported without a rasterizer dependency this app doesn't
    carry yet - those degrade to the same "AI unavailable" fallback as a typed
    request would, prompting the customer to fill the form in by hand instead."""
    if not settings.openai_api_key:
        return _fallback(filename, "AI assistance isn't available right now - please fill in the details below.")

    try:
        client = OpenAI(api_key=settings.openai_api_key)
        beneficiary_context = (
            "\n".join(f"- id={b.id}, name={b.full_name}, relationship={b.relationship_type}" for b in beneficiaries)
            or "(none saved)"
        )

        if content_type == "application/pdf":
            extracted_text = _extract_pdf_text(contents)
            if not extracted_text:
                return _fallback(
                    filename,
                    "Couldn't read any text from this PDF - it may be a scanned image. "
                    "Try uploading a clear photo instead, or fill in the details below.",
                )
            user_content = f"Customer's saved beneficiaries:\n{beneficiary_context}\n\nInvoice/quote text:\n{extracted_text}"
        else:
            b64 = base64.b64encode(contents).decode("ascii")
            user_content = [
                {
                    "type": "text",
                    "text": f"Customer's saved beneficiaries:\n{beneficiary_context}\n\nExtract the details from this invoice/quote photo.",
                },
                {"type": "image_url", "image_url": {"url": f"data:{content_type};base64,{b64}"}},
            ]

        response = client.chat.completions.create(
            model=settings.openai_model,
            messages=[
                {"role": "system", "content": _INVOICE_SYSTEM_PROMPT},
                {"role": "user", "content": user_content},
            ],
            response_format={"type": "json_object"},
            timeout=20,
        )
        result = json.loads(response.choices[0].message.content)

        if not result.get("legible", True):
            # Belt-and-braces: even if the model still filled in other fields
            # despite being told not to, a document it says it couldn't
            # actually read is discarded outright rather than trusted.
            return _fallback(
                filename,
                "Couldn't clearly read this as an invoice or quote - please check the details below.",
            )

        category = result.get("category")
        if category not in _VALID_CATEGORIES:
            category = "other"

        beneficiary_id = result.get("beneficiary_id")
        valid_ids = {str(b.id) for b in beneficiaries}
        if beneficiary_id not in valid_ids:
            beneficiary_id = None

        title = (result.get("title") or filename[:60] or "New request")[:200]

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
        logger.exception("AI invoice parsing failed")
        return _fallback(filename, "AI assistance hit an error reading this document - please check the details below.")
