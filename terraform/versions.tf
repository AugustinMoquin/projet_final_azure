terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state. The storage account below is created once, manually,
  # in the bootstrap step of WALKTHROUGH.md. Until then you can comment
  # this whole block out to use local state.
  # backend "azurerm" {
  #   resource_group_name  = "rg-tfstate"
  #   storage_account_name = "sttfstatez45up6"
  #   container_name       = "tfstate"
  #   key                  = "projet-azure.tfstate"
  # }
}
