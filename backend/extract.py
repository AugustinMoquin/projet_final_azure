"""Extract plain text from an uploaded file so the AI tagger gets real content.

PDFs are parsed with pypdf; text-like files are decoded directly. Anything that
looks binary returns "" so the tagger falls back to filename-based rules instead
of feeding garbage bytes to key-phrase extraction.
"""

import io
import logging

_TEXT_EXTENSIONS = (".txt", ".md", ".csv", ".json", ".log", ".html", ".xml", ".yaml", ".yml")


def extract_text(name: str, data: bytes, max_chars: int = 4000) -> str:
    lower = name.lower()

    if lower.endswith(".pdf") or data[:5] == b"%PDF-":
        return _extract_pdf(data, max_chars)

    if lower.endswith(_TEXT_EXTENSIONS):
        return data.decode("utf-8", errors="ignore")[:max_chars].strip()

    # Unknown type: accept it only if it decodes to mostly-printable text.
    try:
        text = data[: max_chars * 2].decode("utf-8")
    except UnicodeDecodeError:
        return ""
    printable = sum(1 for ch in text if ch.isprintable() or ch.isspace())
    if text and printable / len(text) > 0.85:
        return text[:max_chars].strip()
    return ""


def _extract_pdf(data: bytes, max_chars: int) -> str:
    try:
        from pypdf import PdfReader

        reader = PdfReader(io.BytesIO(data))
        parts: list[str] = []
        total = 0
        for page in reader.pages[:10]:  # cap pages so big PDFs stay cheap
            chunk = page.extract_text() or ""
            parts.append(chunk)
            total += len(chunk)
            if total > max_chars:
                break
        return " ".join(parts).strip()[:max_chars]
    except Exception as exc:  # noqa: BLE001 - extraction is best-effort
        logging.warning("PDF text extraction failed: %s", exc)
        return ""
