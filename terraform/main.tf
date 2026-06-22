# ---------------------------------------------------------------------------
# Naming + foundational resources
# ---------------------------------------------------------------------------

# Globally-unique suffix so storage/cosmos/etc. names don't collide.
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

locals {
  suffix = random_string.suffix.result
  prefix = var.project_name

  # Names with strict rules (storage: 3-24, lowercase alnum only).
  rg_name        = "rg-${local.prefix}"
  func_storage   = substr("st${local.prefix}func${local.suffix}", 0, 24)
  docs_storage   = substr("st${local.prefix}docs${local.suffix}", 0, 24)
  sb_namespace   = "sb-${local.prefix}-${local.suffix}"
  cosmos_account = "cosmos-${local.prefix}-${local.suffix}"
  signalr_name   = "sigr-${local.prefix}-${local.suffix}"
  law_name       = "law-${local.prefix}"
  appi_name      = "appi-${local.prefix}"
  openai_name    = "oai-${local.prefix}-${local.suffix}"
  language_name  = "lang-${local.prefix}-${local.suffix}"

  # Container platform. ACR names allow only alphanumerics (no hyphens).
  acr_name          = substr("acr${local.prefix}${local.suffix}", 0, 50)
  aca_env_name      = "cae-${local.prefix}"
  backend_app_name  = "ca-${local.prefix}-api"
  frontend_app_name = "ca-${local.prefix}-web"
  identity_name     = "id-${local.prefix}-aca"
}

resource "azurerm_resource_group" "main" {
  name     = local.rg_name
  location = var.location
  tags     = var.tags
}
