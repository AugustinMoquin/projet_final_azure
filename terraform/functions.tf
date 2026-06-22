# ---------------------------------------------------------------------------
# Azure Functions (Linux, Python, Consumption plan).
# Hosts all three functions: blob trigger, service bus processor, DLQ handler.
# Every downstream connection string is injected as an app setting.
# ---------------------------------------------------------------------------

resource "azurerm_service_plan" "main" {
  name                = local.plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption
  tags                = var.tags
}

resource "azurerm_linux_function_app" "main" {
  name                       = local.func_app_name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  service_plan_id            = azurerm_service_plan.main.id
  storage_account_name       = azurerm_storage_account.func.name
  storage_account_access_key = azurerm_storage_account.func.primary_access_key

  site_config {
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    application_insights_key               = azurerm_application_insights.main.instrumentation_key

    application_stack {
      python_version = "3.11"
    }

    cors {
      allowed_origins = ["*"]
    }
  }

  identity {
    type = "SystemAssigned"
  }

  app_settings = merge(
    {
      FUNCTIONS_WORKER_RUNTIME = "python"

      # Blob trigger source (the "documents" container lives here).
      DOCS_STORAGE_CONNECTION = azurerm_storage_account.docs.primary_connection_string
      DOCS_CONTAINER          = azurerm_storage_container.documents.name

      # Service Bus + queue.
      SERVICEBUS_CONNECTION = azurerm_servicebus_namespace_authorization_rule.app.primary_connection_string
      SERVICEBUS_QUEUE      = azurerm_servicebus_queue.documents.name

      # Cosmos DB.
      COSMOS_ENDPOINT  = azurerm_cosmosdb_account.main.endpoint
      COSMOS_KEY       = azurerm_cosmosdb_account.main.primary_key
      COSMOS_DATABASE  = azurerm_cosmosdb_sql_database.main.name
      COSMOS_CONTAINER = azurerm_cosmosdb_sql_container.documents.name

      # SignalR (Functions binding reads this exact key name by convention).
      AzureSignalRConnectionString = azurerm_signalr_service.main.primary_connection_string
      SIGNALR_HUB                  = "documents"
    },
    var.enable_openai ? {
      OPENAI_ENABLED    = "true"
      OPENAI_ENDPOINT   = azurerm_cognitive_account.openai[0].endpoint
      OPENAI_KEY        = azurerm_cognitive_account.openai[0].primary_access_key
      OPENAI_DEPLOYMENT = azurerm_cognitive_deployment.tagging[0].name
    } : {
      OPENAI_ENABLED = "false"
    },
    var.enable_language ? {
      LANGUAGE_ENABLED  = "true"
      LANGUAGE_ENDPOINT = azurerm_cognitive_account.language[0].endpoint
      LANGUAGE_KEY      = azurerm_cognitive_account.language[0].primary_access_key
    } : {
      LANGUAGE_ENABLED = "false"
    },
    {
      # Which tagger the Functions try first. Order: openai -> language -> rules.
      AI_PROVIDER = var.enable_openai ? "openai" : (var.enable_language ? "language" : "rules")
    }
  )

  tags = var.tags
}
