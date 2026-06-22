# ---------------------------------------------------------------------------
# Azure AI Language (Cognitive Services "TextAnalytics" kind).
# Used for key-phrase extraction -> document tags. No OpenAI-style quota gate;
# the F0 tier is free. This is the brief-approved alternative to Azure OpenAI.
# ---------------------------------------------------------------------------

resource "azurerm_cognitive_account" "language" {
  count = var.enable_language ? 1 : 0

  name                  = local.language_name
  resource_group_name   = azurerm_resource_group.main.name
  location              = var.language_location
  kind                  = "TextAnalytics"
  sku_name              = var.language_sku # F0 = free, one per region/subscription
  custom_subdomain_name = local.language_name
  tags                  = var.tags
}
