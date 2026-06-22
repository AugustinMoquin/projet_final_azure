# ---------------------------------------------------------------------------
# Azure SignalR Service in Serverless mode so Azure Functions can use the
# SignalR output binding (negotiate + broadcast) to push to the React app.
# ---------------------------------------------------------------------------

resource "azurerm_signalr_service" "main" {
  name                = local.signalr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  sku {
    name     = "Free_F1" # bump to Standard_S1 if you need >20 connections
    capacity = 1
  }

  # Serverless is required for the Functions SignalR bindings.
  service_mode = "Serverless"

  # Allow the React dev server / static site to call the negotiate endpoint.
  cors {
    allowed_origins = ["*"]
  }

  tags = var.tags
}
