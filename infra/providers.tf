terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Values supplied at init time via -backend-config
  backend "azurerm" {}
}

# Auth comes from ARM_CLIENT_ID / ARM_TENANT_ID / ARM_SUBSCRIPTION_ID / ARM_USE_OIDC env vars
provider "azurerm" {
  features {}
}
