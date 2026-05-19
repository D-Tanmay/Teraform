terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.8.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "tfstate-day04"
    storage_account_name = "day0417691"
    container_name       = "tfstate"
    key                  = "dev.terraform.tfstate"
  }

  required_version = ">=1.9.0"
}

provider "azurerm" {
  features {}

  # Required in azurerm v4.x — no longer inferred automatically
  # ARM_SUBSCRIPTION_ID env var is set in the workflow, this reads from it
  subscription_id = var.subscription_id

  # Replaces deprecated skip_provider_registration
  resource_provider_registrations = "none"
}

# ─────────────────────────────────────────────────────────────────────────────
# Variables
# ─────────────────────────────────────────────────────────────────────────────

variable "subscription_id" {
  description = "Azure Subscription ID — set via TF_VAR_subscription_id env var in CI"
  type        = string
  sensitive   = true
}

# ─────────────────────────────────────────────────────────────────────────────
# Resources
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_resource_group" "example" {
  name     = "example-resources"
  location = "West Europe"
}

resource "azurerm_storage_account" "example" {
  name                     = "tanmayrg"
  resource_group_name      = azurerm_resource_group.example.name
  location                 = azurerm_resource_group.example.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    environment = "staging"
  }
}
