terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # resource_group_name and storage_account_name are supplied at init time via -backend-config
  backend "azurerm" {
    container_name   = "tfstate"
    key              = "platform-prod-lake.tfstate"
    use_azuread_auth = true
  }
}

# CI: ARM_CLIENT_ID / ARM_TENANT_ID / ARM_SUBSCRIPTION_ID / ARM_USE_OIDC
# Local: az login + ARM_SUBSCRIPTION_ID
provider "azurerm" {
  features {}
}
