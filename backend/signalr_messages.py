"""Helpers for the SignalR output binding.

The binding expects a JSON object describing which client method to invoke and
with what arguments. The React app listens for the `statusUpdate` target.
"""

import json

STATUS_TARGET = "statusUpdate"


def status_message(doc: dict) -> str:
    """Build a broadcast message carrying a document's current state."""
    arg = {
        "documentId": doc.get("documentId"),
        "name": doc.get("name"),
        "status": doc.get("status"),
        "tags": doc.get("tags", []),
        "taggedBy": doc.get("taggedBy"),
        "error": doc.get("error"),
        "correlationId": doc.get("correlationId"),
    }
    return json.dumps({"target": STATUS_TARGET, "arguments": [arg]})
