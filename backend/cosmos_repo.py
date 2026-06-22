"""Thin wrapper around the Cosmos DB SQL API for document metadata.

Reads COSMOS_ENDPOINT / COSMOS_KEY / COSMOS_DATABASE / COSMOS_CONTAINER from the
app settings Terraform injects. The container is partitioned on /documentId.
"""

import os

from azure.cosmos import CosmosClient, PartitionKey, exceptions


class CosmosRepo:
    def __init__(self):
        self._client = None
        self._container = None

    @property
    def container(self):
        # Lazy init so module import (and the unit tests) never need real creds.
        if self._container is None:
            endpoint = os.environ["COSMOS_ENDPOINT"]
            key = os.environ["COSMOS_KEY"]
            db_name = os.environ.get("COSMOS_DATABASE", "documentsdb")
            container_name = os.environ.get("COSMOS_CONTAINER", "documents")

            self._client = CosmosClient(endpoint, credential=key)
            db = self._client.create_database_if_not_exists(id=db_name)
            self._container = db.create_container_if_not_exists(
                id=container_name,
                partition_key=PartitionKey(path="/documentId"),
            )
        return self._container

    def upsert(self, doc: dict) -> dict:
        return self.container.upsert_item(doc)

    def get(self, document_id: str):
        try:
            return self.container.read_item(item=document_id, partition_key=document_id)
        except exceptions.CosmosResourceNotFoundError:
            return None

    def list_recent(self, limit: int = 50):
        query = f"SELECT TOP {int(limit)} * FROM c ORDER BY c._ts DESC"
        return list(self.container.query_items(query=query, enable_cross_partition_query=True))
