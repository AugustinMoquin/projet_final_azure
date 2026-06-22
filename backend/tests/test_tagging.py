"""Unit tests for the rule-based tagger (no Azure resources required)."""

from tagging import tag_rules


def test_keyword_match():
    tags = tag_rules("2024-invoice.pdf")
    assert "finance" in tags
    assert "invoice" in tags
    assert "pdf" in tags


def test_french_keyword():
    tags = tag_rules("contrat-location.docx")
    assert "legal" in tags
    assert "contract" in tags
    assert "word" in tags


def test_text_content_is_searched():
    tags = tag_rules("scan001.png", text="Annual budget report for the team")
    assert "finance" in tags
    assert "budget" in tags
    assert "report" in tags
    assert "image" in tags


def test_unknown_is_untagged():
    assert tag_rules("zxqw.bin") == ["untagged"]


def test_tags_are_unique():
    tags = tag_rules("invoice-facture.pdf")
    assert len(tags) == len(set(tags))
