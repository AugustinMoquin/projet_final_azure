"""Document tagging with graceful fallback: OpenAI -> Azure AI Language -> rules.

Which provider is tried is controlled by app settings Terraform sets:
  AI_PROVIDER       "openai" | "language" | "rules"  (preferred provider)
  OPENAI_ENABLED / OPENAI_ENDPOINT / OPENAI_KEY / OPENAI_DEPLOYMENT
  LANGUAGE_ENABLED / LANGUAGE_ENDPOINT / LANGUAGE_KEY

Any provider failure falls through to the next one; the rule-based tagger always
succeeds, so tag_document() never raises. Returns (tags, provider_used).
"""

import logging
import os

# Keyword -> tag rules for the offline fallback. Matched against name + text.
_RULES = {
    "invoice": ["finance", "invoice"],
    "facture": ["finance", "invoice"],
    "receipt": ["finance", "receipt"],
    "contract": ["legal", "contract"],
    "contrat": ["legal", "contract"],
    "report": ["report"],
    "rapport": ["report"],
    "resume": ["hr", "resume"],
    "cv": ["hr", "resume"],
    "presentation": ["presentation"],
    "budget": ["finance", "budget"],
}

_EXT_TAGS = {
    ".pdf": "pdf",
    ".docx": "word",
    ".doc": "word",
    ".xlsx": "spreadsheet",
    ".csv": "data",
    ".txt": "text",
    ".md": "text",
    ".png": "image",
    ".jpg": "image",
    ".jpeg": "image",
}


def tag_document(name: str, text: str = "") -> tuple[list[str], str]:
    provider = os.environ.get("AI_PROVIDER", "rules").lower()

    if provider == "openai" and os.environ.get("OPENAI_ENABLED") == "true":
        try:
            return _tag_openai(name, text), "openai"
        except Exception as exc:  # noqa: BLE001 - fall back, never fail the doc
            logging.warning("OpenAI tagging failed, falling back: %s", exc)

    if provider in ("openai", "language") and os.environ.get("LANGUAGE_ENABLED") == "true":
        try:
            return _tag_language(name, text), "language"
        except Exception as exc:  # noqa: BLE001
            logging.warning("Language tagging failed, falling back: %s", exc)

    return tag_rules(name, text), "rules"


def tag_rules(name: str, text: str = "") -> list[str]:
    """Deterministic, dependency-free tagging. Always available."""
    haystack = f"{name} {text}".lower()
    tags: list[str] = []

    for keyword, keyword_tags in _RULES.items():
        if keyword in haystack:
            tags.extend(keyword_tags)

    _, ext = os.path.splitext(name.lower())
    if ext in _EXT_TAGS:
        tags.append(_EXT_TAGS[ext])

    if not tags:
        tags.append("untagged")

    # De-duplicate, keep order stable.
    return list(dict.fromkeys(tags))


def _tag_openai(name: str, text: str) -> list[str]:
    from openai import AzureOpenAI

    client = AzureOpenAI(
        azure_endpoint=os.environ["OPENAI_ENDPOINT"],
        api_key=os.environ["OPENAI_KEY"],
        api_version="2024-06-01",
    )
    prompt = (
        "Return 3-6 short, lowercase, comma-separated topical tags for a document. "
        "Reply with ONLY the tags.\n"
        f"Filename: {name}\nExcerpt: {text[:1500]}"
    )
    resp = client.chat.completions.create(
        model=os.environ["OPENAI_DEPLOYMENT"],
        messages=[{"role": "user", "content": prompt}],
        temperature=0.2,
        max_tokens=60,
    )
    raw = resp.choices[0].message.content or ""
    tags = [t.strip().lower() for t in raw.replace("\n", ",").split(",") if t.strip()]
    return list(dict.fromkeys(tags)) or tag_rules(name, text)


def _tag_language(name: str, text: str) -> list[str]:
    from azure.ai.textanalytics import TextAnalyticsClient
    from azure.core.credentials import AzureKeyCredential

    client = TextAnalyticsClient(
        endpoint=os.environ["LANGUAGE_ENDPOINT"],
        credential=AzureKeyCredential(os.environ["LANGUAGE_KEY"]),
    )
    # Key-phrase extraction needs some text; fall back to rules on empty input.
    content = text.strip() or name
    result = client.extract_key_phrases([content])[0]
    if result.is_error:
        raise RuntimeError(result.error.message)
    tags = [p.strip().lower() for p in result.key_phrases][:6]
    return list(dict.fromkeys(tags)) or tag_rules(name, text)
