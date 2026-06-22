# ---------------------------------------------------------------------------
# Service Bus: main processing queue with built-in Dead Letter Queue.
# The DLQ is automatic on every queue ($DeadLetterQueue sub-entity); we just
# enable the conditions that route failed messages to it.
# ---------------------------------------------------------------------------

resource "azurerm_servicebus_namespace" "main" {
  name                = local.sb_namespace
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_servicebus_queue" "documents" {
  name         = "documents-queue"
  namespace_id = azurerm_servicebus_namespace.main.id

  # Failed messages (poison / expired) flow to the DLQ automatically.
  dead_lettering_on_message_expiration = true
  max_delivery_count                   = 5 # after 5 failed attempts -> DLQ
  default_message_ttl                  = "P14D"
  lock_duration                        = "PT5M"
  max_size_in_megabytes                = 1024
}

# Dedicated SAS rule the Functions use to send/listen (least privilege-ish).
resource "azurerm_servicebus_namespace_authorization_rule" "app" {
  name         = "app-access"
  namespace_id = azurerm_servicebus_namespace.main.id
  listen       = true
  send         = true
  manage       = false
}
