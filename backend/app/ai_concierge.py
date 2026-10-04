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
from .models import Beneficiary
from .service_taxonomy import ACTIVE_CATEGORIES

logger = logging.getLogger(__name__)

_VALID_CATEGORIES = ACTIVE_CATEGORIES

_SYSTEM_PROMPT = (
    "You are the intake assistant for MidMen, a concierge platform. A customer "
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
    "You are the intake assistant for MidMen, a concierge platform. A customer has "
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


_COMPARISON_SYSTEM_PROMPT = (
    "You are the intake assistant for MidMen, a concierge platform. Staff have gathered "
    "price quotes from multiple suppliers for the same job and want a quick comparison "
    "before presenting one option to the customer.\n\n"
    "This is a financial comparison a human will act on, so accuracy matters more than "
    "completeness: only report an amount or detail you can actually read for that specific "
    "supplier. Never invent or estimate a figure that isn't actually shown, and never let a "
    "detail from one supplier's quote leak into another's.\n\n"
    "For each supplier listed below, return: supplier_name (use exactly the name given), "
    "amount (the total price as a plain number, or null if you can't read one), and notes "
    "(key terms - delivery time, inclusions/exclusions, anything a human should know - or "
    "null if the quote was unreadable or has nothing beyond the price).\n\n"
    "Then write:\n"
    "- summary: 1-3 sentences comparing the suppliers (price differences, what's included where)\n"
    "- recommendation: which supplier looks best and why, in one sentence - or null if the "
    "quotes are too unclear or too similar to recommend one\n\n"
    'Respond with strict JSON: {"suppliers": [{"supplier_name": ..., "amount": ..., "notes": ...}], '
    '"summary": ..., "recommendation": ...}'
)


def _comparison_fallback(supplier_names: list[str], summary: str) -> dict:
    return {
        "ai_available": False,
        "summary": summary,
        "recommendation": None,
        "suppliers": [{"supplier_name": n, "amount": None, "notes": None} for n in supplier_names],
    }


def compare_quotes(quotes: list[dict]) -> dict:
    """quotes: [{"supplier_name": str, "content_type": str, "data": bytes}, ...] - at
    least two, already read from storage by the caller. Builds a single side-by-side
    comparison rather than parsing each quote separately, so the model can reason about
    relative price/terms directly. Still just an aid for staff to review, not a decision."""
    supplier_names = [q["supplier_name"] for q in quotes]

    if not settings.openai_api_key:
        return _comparison_fallback(supplier_names, "AI assistance isn't available right now - review the attached quotes manually.")

    try:
        client = OpenAI(api_key=settings.openai_api_key)
        user_content = [{"type": "text", "text": f"Suppliers to compare: {', '.join(supplier_names)}"}]
        for q in quotes:
            if q["content_type"] == "application/pdf":
                text = _extract_pdf_text(q["data"])
                user_content.append(
                    {
                        "type": "text",
                        "text": f"--- Quote from {q['supplier_name']} ---\n" + (text or "(no readable text in this PDF)"),
                    }
                )
            else:
                b64 = base64.b64encode(q["data"]).decode("ascii")
                user_content.append({"type": "text", "text": f"--- Quote from {q['supplier_name']} (photo below) ---"})
                user_content.append({"type": "image_url", "image_url": {"url": f"data:{q['content_type']};base64,{b64}"}})

        response = client.chat.completions.create(
            model=settings.openai_model,
            messages=[
                {"role": "system", "content": _COMPARISON_SYSTEM_PROMPT},
                {"role": "user", "content": user_content},
            ],
            response_format={"type": "json_object"},
            timeout=30,
        )
        result = json.loads(response.choices[0].message.content)

        suppliers = []
        seen = set()
        for s in result.get("suppliers") or []:
            name = s.get("supplier_name")
            if name not in supplier_names or name in seen:
                continue  # drop anything not matching a supplier we actually sent
            seen.add(name)
            suppliers.append({"supplier_name": name, "amount": s.get("amount"), "notes": s.get("notes")})
        for name in supplier_names:
            if name not in seen:
                suppliers.append({"supplier_name": name, "amount": None, "notes": "Couldn't read this quote clearly."})

        return {
            "ai_available": True,
            "summary": result.get("summary") or "",
            "recommendation": result.get("recommendation"),
            "suppliers": suppliers,
        }
    except Exception:
        logger.exception("AI quote comparison failed")
        return _comparison_fallback(supplier_names, "AI assistance hit an error comparing these quotes - review them manually.")


_SUPPORT_SYSTEM_PROMPT = (
    "You are MidMen's in-app help assistant. MidMen is a concierge platform: customers "
    "submit service requests (school fees, medical, groceries, documents, property, "
    "procurement, gifts, transport, personal concierge, or other) and MidMen staff carry "
    "them out. You are a help/FAQ chatbot only - you cannot create, cancel, approve, or "
    "change anything yourself, and you never move money.\n\n"
    "How the platform works, for answering questions:\n"
    "- Every request moves through 4 customer-visible stages: Received, Arranging, In "
    "Progress, Completed. Staff sometimes need to confirm an approval before payment.\n"
    "- Every customer must verify their identity (KYC): upload an id/passport from the "
    "Account tab; staff review and approve or decline it, with a reason if declined.\n"
    "- MidMen has no paid membership tiers - every account is free and gets the full set "
    "of benefits: saved beneficiaries, full request history, and priority service.\n"
    "- To start a new request, the customer types or speaks what they need on the Home "
    "tab, or uploads an invoice/quote there, or taps a service category directly.\n\n"
    "Rules:\n"
    "- Only state account/request details that are actually given to you below - never "
    "invent an order, amount, date, or status that isn't in that context.\n"
    "- If asked to actually do something (cancel a request, refund a charge, edit an "
    "order), explain you can't take actions, and say where in the app they can do it "
    "themselves (or that staff will handle it).\n"
    "- If you don't know the answer from the context and platform info above, say so "
    "plainly rather than guessing, and suggest checking the Requests tab or waiting for a "
    "staff reply.\n"
    "- Keep replies short and conversational - a few sentences, not an essay.\n\n"
    "Respond with strict JSON: {\"reply\": \"...\"}"
)

_MAX_CHAT_HISTORY = 10
_MAX_MESSAGE_CHARS = 2000


def _chat_fallback(reply: str) -> dict:
    return {"reply": reply, "ai_available": False}


def answer_support_question(message: str, history: list[dict], context: dict) -> dict:
    """A read-only help/FAQ chatbot: answers questions about how MidMen works and the
    customer's own recent requests (given via `context`), but can never create, change,
    or cancel anything - same "AI never acts directly" rule as the rest of the concierge."""
    message = (message or "").strip()[:_MAX_MESSAGE_CHARS]
    if not message:
        return _chat_fallback("Ask me anything about your requests or how MidMen works!")

    if not settings.openai_api_key:
        return _chat_fallback("Chat support isn't available right now - check the Requests tab for status, or a staff member will follow up by email.")

    try:
        client = OpenAI(api_key=settings.openai_api_key)
        messages = [{"role": "system", "content": _SUPPORT_SYSTEM_PROMPT}]
        messages.append({"role": "system", "content": f"Account context (only source of truth for account specifics): {json.dumps(context)}"})
        for h in history[-_MAX_CHAT_HISTORY:]:
            role = h.get("role")
            if role in ("user", "assistant") and h.get("content"):
                messages.append({"role": role, "content": str(h["content"])[:_MAX_MESSAGE_CHARS]})
        messages.append({"role": "user", "content": message})

        response = client.chat.completions.create(
            model=settings.openai_model,
            messages=messages,
            response_format={"type": "json_object"},
            timeout=20,
        )
        result = json.loads(response.choices[0].message.content)
        reply = (result.get("reply") or "").strip()
        if not reply:
            return _chat_fallback("Sorry, I didn't catch that - could you rephrase?")
        return {"reply": reply, "ai_available": True}
    except Exception:
        logger.exception("AI support chat failed")
        return _chat_fallback("Something went wrong answering that - please try again, or check the Requests tab in the meantime.")
