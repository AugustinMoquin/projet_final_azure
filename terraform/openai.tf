# ---------------------------------------------------------------------------
# Azure OpenAI (optional). Requires your subscription to be approved for the
# service. If enable_openai = false, nothing here is created and the Functions
# fall back to rule-based tagging (allowed by the spec).
# ---------------------------------------------------------------------------

resource "azurerm_cognitive_account" "openai" {
  count = var.enable_openai ? 1 : 0

  name                  = local.openai_name
  resource_group_name   = azurerm_resource_group.main.name
  location              = var.openai_location
  kind                  = "OpenAI"
  sku_name              = "S0"
  custom_subdomain_name = local.openai_name
  tags                  = var.tags
}

resource "azurerm_cognitive_deployment" "tagging" {
  count = var.enable_openai ? 1 : 0

  name                 = "tagging"
  cognitive_account_id = azurerm_cognitive_account.openai[0].id

  model {
    format  = "OpenAI"
    name    = var.openai_model
    version = var.openai_model_version
  }

  sku {
    name     = "GlobalStandard"
    capacity = 10
  }
}
