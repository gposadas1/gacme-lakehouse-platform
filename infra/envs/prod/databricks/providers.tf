terraform {
  required_version = ">= 1.6"

  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.130"
    }
  }

  # resource_group_name and storage_account_name are supplied at init time via -backend-config
  backend "azurerm" {
    container_name   = "tfstate"
    key              = "platform-prod-databricks.tfstate"
    use_azuread_auth = true
  }
}

# CI: DATABRICKS_AUTH_TYPE=github-oidc-azure with ARM_CLIENT_ID / ARM_TENANT_ID (same identity as azurerm)
# Local: az login (the provider falls back to Azure CLI auth)
provider "databricks" {
  host                        = var.workspace_url
  azure_workspace_resource_id = var.workspace_resource_id
}
