# ---------------------------------------------------------------------------
# Container platform: ACR + Azure Container Apps.
#
# Both apps run as containers pulled from ACR:
#   - backend  : the Azure Functions image (keeps blob/Service Bus/SignalR
#                triggers; min_replicas = 1 so the runtime is always listening).
#   - frontend : the React build served by nginx.
#
# Images are pushed and rolled out by the GitHub Actions pipeline; Terraform only
# provisions the platform and seeds a placeholder image (lifecycle ignores later
# image changes so `terraform apply` never reverts a deployed revision).
# ---------------------------------------------------------------------------

resource "azurerm_container_registry" "main" {
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = var.tags
}

# User-assigned identity both apps use to pull from ACR (no admin creds, no
# circular dependency with system-assigned identities).
resource "azurerm_user_assigned_identity" "aca" {
  name                = local.identity_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.aca.principal_id
}

resource "azurerm_container_app_environment" "main" {
  name                       = local.aca_env_name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = var.tags
}

# Public placeholder until the pipeline pushes the real images.
locals {
  placeholder_image = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"

  # Sensitive values surfaced as Container App secrets. Keyed by the ENV VAR name
  # the app expects; the secret name is the lowercased, hyphenated form.
  backend_secret_env = merge(
    {
      DOCS_STORAGE_CONNECTION               = azurerm_storage_account.docs.primary_connection_string
      SERVICEBUS_CONNECTION                 = azurerm_servicebus_namespace_authorization_rule.app.primary_connection_string
      COSMOS_KEY                            = azurerm_cosmosdb_account.main.primary_key
      AzureSignalRConnectionString          = azurerm_signalr_service.main.primary_connection_string
      AzureWebJobsStorage                   = azurerm_storage_account.func.primary_connection_string
      APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.main.connection_string
    },
    var.enable_openai ? { OPENAI_KEY = azurerm_cognitive_account.openai[0].primary_access_key } : {},
    var.enable_language ? { LANGUAGE_KEY = azurerm_cognitive_account.language[0].primary_access_key } : {},
  )

  # Non-sensitive environment variables.
  backend_plain_env = merge(
    {
      FUNCTIONS_WORKER_RUNTIME = "python"
      DOCS_CONTAINER           = azurerm_storage_container.documents.name
      SERVICEBUS_QUEUE         = azurerm_servicebus_queue.documents.name
      COSMOS_ENDPOINT          = azurerm_cosmosdb_account.main.endpoint
      COSMOS_DATABASE          = azurerm_cosmosdb_sql_database.main.name
      COSMOS_CONTAINER         = azurerm_cosmosdb_sql_container.documents.name
      SIGNALR_HUB              = "documents"
      OPENAI_ENABLED           = tostring(var.enable_openai)
      LANGUAGE_ENABLED         = tostring(var.enable_language)
      AI_PROVIDER              = var.enable_openai ? "openai" : (var.enable_language ? "language" : "rules")
    },
    var.enable_openai ? {
      OPENAI_ENDPOINT   = azurerm_cognitive_account.openai[0].endpoint
      OPENAI_DEPLOYMENT = azurerm_cognitive_deployment.tagging[0].name
    } : {},
    var.enable_language ? {
      LANGUAGE_ENDPOINT = azurerm_cognitive_account.language[0].endpoint
    } : {},
  )
}

# ---------------------------------------------------------------------------
# Backend: containerized Azure Functions.
# ---------------------------------------------------------------------------
resource "azurerm_container_app" "backend" {
  name                         = local.backend_app_name
  resource_group_name          = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.main.id
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aca.id]
  }

  registry {
    server   = azurerm_container_registry.main.login_server
    identity = azurerm_user_assigned_identity.aca.id
  }

  dynamic "secret" {
    for_each = local.backend_secret_env
    content {
      name  = lower(replace(secret.key, "_", "-"))
      value = secret.value
    }
  }

  ingress {
    external_enabled = true
    target_port      = 80
    transport        = "auto"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 1 # keep the Functions host alive to listen for triggers
    max_replicas = 3

    container {
      name   = "functions"
      image  = local.placeholder_image
      cpu    = 0.5
      memory = "1Gi"

      dynamic "env" {
        for_each = local.backend_plain_env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.backend_secret_env
        content {
          name        = env.key
          secret_name = lower(replace(env.key, "_", "-"))
        }
      }
    }

    # Scale out on Service Bus queue depth (KEDA).
    custom_scale_rule {
      name             = "servicebus-queue"
      custom_rule_type = "azure-servicebus"
      metadata = {
        queueName    = azurerm_servicebus_queue.documents.name
        namespace    = azurerm_servicebus_namespace.main.name
        messageCount = "5"
      }
      authentication {
        secret_name       = "servicebus-connection"
        trigger_parameter = "connection"
      }
    }
  }

  depends_on = [azurerm_role_assignment.acr_pull]

  lifecycle {
    # The pipeline owns the image tag; don't revert it on the next apply.
    ignore_changes = [template[0].container[0].image]
  }
}

# ---------------------------------------------------------------------------
# Frontend: React build served by nginx.
# ---------------------------------------------------------------------------
resource "azurerm_container_app" "frontend" {
  name                         = local.frontend_app_name
  resource_group_name          = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.main.id
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aca.id]
  }

  registry {
    server   = azurerm_container_registry.main.login_server
    identity = azurerm_user_assigned_identity.aca.id
  }

  ingress {
    external_enabled = true
    target_port      = 80
    transport        = "auto"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 1
    max_replicas = 3

    container {
      name   = "web"
      image  = local.placeholder_image
      cpu    = 0.25
      memory = "0.5Gi"
    }

    http_scale_rule {
      name                = "http"
      concurrent_requests = 50
    }
  }

  depends_on = [azurerm_role_assignment.acr_pull]

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }
}
