output "resource_group" {
  value = azurerm_resource_group.main.name
}

# --- Container platform (used by the GitHub Actions pipeline) ---
output "acr_name" {
  description = "Use as ACR_NAME in the pipeline."
  value       = azurerm_container_registry.main.name
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "backend_app_name" {
  description = "Use as BACKEND_APP_NAME in the pipeline."
  value       = azurerm_container_app.backend.name
}

output "backend_app_fqdn" {
  description = "Public hostname of the backend API. FUNCTION_BASE_URL = https://<this>/api"
  value       = azurerm_container_app.backend.ingress[0].fqdn
}

output "frontend_app_name" {
  description = "Use as FRONTEND_APP_NAME in the pipeline."
  value       = azurerm_container_app.frontend.name
}

output "frontend_app_fqdn" {
  description = "Public hostname of the React app."
  value       = azurerm_container_app.frontend.ingress[0].fqdn
}

output "docs_storage_account" {
  value = azurerm_storage_account.docs.name
}

output "documents_container" {
  value = azurerm_storage_container.documents.name
}

output "servicebus_namespace" {
  value = azurerm_servicebus_namespace.main.name
}

output "servicebus_queue" {
  value = azurerm_servicebus_queue.documents.name
}

output "cosmos_endpoint" {
  value = azurerm_cosmosdb_account.main.endpoint
}

output "signalr_name" {
  value = azurerm_signalr_service.main.name
}

output "application_insights_name" {
  value = azurerm_application_insights.main.name
}

output "openai_endpoint" {
  value     = var.enable_openai ? azurerm_cognitive_account.openai[0].endpoint : "disabled"
  sensitive = false
}

output "language_endpoint" {
  value = var.enable_language ? azurerm_cognitive_account.language[0].endpoint : "disabled"
}

output "language_key" {
  value     = var.enable_language ? azurerm_cognitive_account.language[0].primary_access_key : "disabled"
  sensitive = true
}

# Sensitive values – read with: terraform output -raw <name>
output "docs_storage_connection" {
  value     = azurerm_storage_account.docs.primary_connection_string
  sensitive = true
}

output "servicebus_connection" {
  value     = azurerm_servicebus_namespace_authorization_rule.app.primary_connection_string
  sensitive = true
}

output "cosmos_primary_key" {
  value     = azurerm_cosmosdb_account.main.primary_key
  sensitive = true
}

output "signalr_connection" {
  value     = azurerm_signalr_service.main.primary_connection_string
  sensitive = true
}
