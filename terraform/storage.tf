# ---------------------------------------------------------------------------
# Storage: one account for the Function App runtime, one for documents.
# The "documents" container is what the Blob Trigger listens on.
# ---------------------------------------------------------------------------

resource "azurerm_storage_account" "func" {
  name                            = local.func_storage
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = var.tags
}

resource "azurerm_storage_account" "docs" {
  name                            = local.docs_storage
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = var.tags
}

# Container that receives uploaded files. Blob-trigger Function fires here.
resource "azurerm_storage_container" "documents" {
  name                  = "documents"
  storage_account_id    = azurerm_storage_account.docs.id
  container_access_type = "private"
}
