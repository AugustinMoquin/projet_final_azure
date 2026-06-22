"""Tests for text extraction (the part that fed garbage to the tagger before)."""

from extract import extract_text


def test_plain_text_is_decoded():
    text = extract_text("notes.txt", b"Annual budget report for the finance team")
    assert "budget" in text
    assert "finance" in text


def test_binary_returns_empty():
    # Random binary (e.g. a non-PDF blob) must not produce garbage "text".
    blob = bytes(range(256)) * 4
    assert extract_text("image.bin", blob) == ""


def test_unsupported_text_extension_decodes():
    assert extract_text("data.csv", b"name,amount\ninvoice,100") != ""


def test_truncates_to_max_chars():
    out = extract_text("big.txt", b"x" * 10000, max_chars=100)
    assert len(out) <= 100
