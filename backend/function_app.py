"""Azure Functions (Python v2 model) — the document pipeline.

Flow:
  1. blob_intake          Blob trigger on `documents/` -> create Cosmos doc
                          (UPLOADED), push a message to Service Bus, notify clients.
  2. process_document     Service Bus trigger on `documents-queue` -> AI-tag,
                          write tags to Cosmos (PROCESSING -> PROCESSED), notify.
                          Raises on bad input so failures retry and reach the DLQ.
  3. dlq_handler          Service Bus trigger on the queue's $DeadLetterQueue ->
                          mark the doc ERROR and notify clients.
  4. negotiate            HTTP + SignalR input binding -> connection info for the
                          React app.
  5. list_documents       HTTP GET -> current documents (initial state for the UI).

Every connection string / name comes from app settings injected by Terraform
(see terraform/functions.tf). Nothing is hard-coded.
"""

import json
import logging
import os
import uuid

import azure.functions as func

from cosmos_repo import CosmosRepo
from signalr_messages import status_message
from tagging import tag_document

app = func.FunctionApp()

# Cosmos client is process-wide; reused across invocations on a warm worker.
_repo = CosmosRepo()

HUB = os.environ.get("SIGNALR_HUB", "documents")

# The React app is served from a different origin (its own Container App), so the
# HTTP endpoints it calls must return CORS headers. The SignalR websocket itself
# goes straight to the SignalR service, which has its own CORS config.
_CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, x-requested-with, x-signalr-user-agent",
}


def _cors_preflight() -> func.HttpResponse:
    return func.HttpResponse(status_code=204, headers=_CORS_HEADERS)


def _log(level: int, message: str, *, document_id: str = "", correlation_id: str = ""):
    """Log with correlationId / documentId as App Insights custom dimensions."""
    logging.log(
        level,
        message,
        extra={"custom_dimensions": {"documentId": document_id, "correlationId": correlation_id}},
    )


# ---------------------------------------------------------------------------
# 1. Blob trigger: a file landed in the `documents` container.
# ---------------------------------------------------------------------------
@app.blob_trigger(
    arg_name="blob",
    path="%DOCS_CONTAINER%/{name}",
    connection="DOCS_STORAGE_CONNECTION",
)
@app.service_bus_queue_output(
    arg_name="msg",
    queue_name="%SERVICEBUS_QUEUE%",
    connection="SERVICEBUS_CONNECTION",
)
@app.generic_output_binding(
    arg_name="signalr",
    type="signalR",
    hub_name=HUB,
    connection_string_setting="AzureSignalRConnectionString",
)
def blob_intake(blob: func.InputStream, msg: func.Out[str], signalr: func.Out[str]):
    name = os.path.basename(blob.name or "unknown")
    document_id = uuid.uuid4().hex
    correlation_id = uuid.uuid4().hex

    _log(logging.INFO, f"Blob received: {name} ({blob.length} bytes)",
         document_id=document_id, correlation_id=correlation_id)

    # A small text snippet helps the AI tagger; binary files just use the name.
    snippet = ""
    try:
        snippet = blob.read(4096).decode("utf-8", errors="ignore")
    except Exception:  # noqa: BLE001 - snippet is best-effort only
        snippet = ""

    doc = {
        "id": document_id,
        "documentId": document_id,
        "name": name,
        "sizeBytes": blob.length,
        "status": "UPLOADED",
        "tags": [],
        "correlationId": correlation_id,
    }
    _repo.upsert(doc)
    signalr.set(status_message(doc))

    # Hand off to the queue. The snippet rides along so the processor can tag
    # without re-reading the blob.
    msg.set(json.dumps({
        "documentId": document_id,
        "name": name,
        "correlationId": correlation_id,
        "snippet": snippet,
    }))

    doc["status"] = "QUEUED"
    _repo.upsert(doc)
    signalr.set(status_message(doc))
    _log(logging.INFO, "Document queued for processing",
         document_id=document_id, correlation_id=correlation_id)


# ---------------------------------------------------------------------------
# 2. Service Bus processor: tag the document and persist the result.
# ---------------------------------------------------------------------------
@app.service_bus_queue_trigger(
    arg_name="msg",
    queue_name="%SERVICEBUS_QUEUE%",
    connection="SERVICEBUS_CONNECTION",
)
@app.generic_output_binding(
    arg_name="signalr",
    type="signalR",
    hub_name=HUB,
    connection_string_setting="AzureSignalRConnectionString",
)
def process_document(msg: func.ServiceBusMessage, signalr: func.Out[str]):
    body = msg.get_body().decode("utf-8")
    # Bad input raises -> Service Bus retries -> after max_delivery_count -> DLQ.
    payload = json.loads(body)
    document_id = payload["documentId"]
    correlation_id = payload.get("correlationId", "")
    name = payload.get("name", "")

    _log(logging.INFO, f"Processing document {name}",
         document_id=document_id, correlation_id=correlation_id)

    doc = _repo.get(document_id) or {
        "id": document_id, "documentId": document_id, "name": name,
        "status": "PROCESSING", "tags": [], "correlationId": correlation_id,
    }
    doc["status"] = "PROCESSING"
    _repo.upsert(doc)
    signalr.set(status_message(doc))

    tags, provider = tag_document(name=name, text=payload.get("snippet", ""))

    doc["tags"] = tags
    doc["taggedBy"] = provider
    doc["status"] = "PROCESSED"
    _repo.upsert(doc)
    signalr.set(status_message(doc))

    _log(logging.INFO, f"Document processed; tags={tags} via {provider}",
         document_id=document_id, correlation_id=correlation_id)


# ---------------------------------------------------------------------------
# 3. Dead Letter Queue handler: a message failed processing 5 times.
# ---------------------------------------------------------------------------
@app.service_bus_queue_trigger(
    arg_name="msg",
    queue_name="%SERVICEBUS_QUEUE%/$DeadLetterQueue",
    connection="SERVICEBUS_CONNECTION",
)
@app.generic_output_binding(
    arg_name="signalr",
    type="signalR",
    hub_name=HUB,
    connection_string_setting="AzureSignalRConnectionString",
)
def dlq_handler(msg: func.ServiceBusMessage, signalr: func.Out[str]):
    raw = msg.get_body().decode("utf-8", errors="ignore")
    document_id = ""
    correlation_id = ""
    try:
        payload = json.loads(raw)
        document_id = payload.get("documentId", "")
        correlation_id = payload.get("correlationId", "")
    except (ValueError, TypeError):
        pass

    reason = msg.dead_letter_reason or "MaxDeliveryCountExceeded"
    _log(logging.ERROR, f"Dead-lettered message: {reason}",
         document_id=document_id, correlation_id=correlation_id)

    if document_id:
        doc = _repo.get(document_id) or {
            "id": document_id, "documentId": document_id, "status": "ERROR",
        }
        doc["status"] = "ERROR"
        doc["error"] = reason
        _repo.upsert(doc)
        signalr.set(status_message(doc))


# ---------------------------------------------------------------------------
# 4. SignalR negotiate: the React app calls this to open a connection.
# ---------------------------------------------------------------------------
@app.route(route="negotiate", auth_level=func.AuthLevel.ANONYMOUS, methods=["GET", "POST", "OPTIONS"])
@app.generic_input_binding(
    arg_name="connectionInfo",
    type="signalRConnectionInfo",
    hub_name=HUB,
    connection_string_setting="AzureSignalRConnectionString",
)
def negotiate(req: func.HttpRequest, connectionInfo) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return _cors_preflight()
    # The binding produces the connection-info JSON the SignalR client needs.
    return func.HttpResponse(connectionInfo, mimetype="application/json", headers=_CORS_HEADERS)


# ---------------------------------------------------------------------------
# 5. List documents: initial state for the UI.
# ---------------------------------------------------------------------------
@app.route(route="documents", auth_level=func.AuthLevel.ANONYMOUS, methods=["GET", "OPTIONS"])
def list_documents(req: func.HttpRequest) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return _cors_preflight()
    docs = _repo.list_recent(limit=50)
    return func.HttpResponse(json.dumps(docs), mimetype="application/json", headers=_CORS_HEADERS)
