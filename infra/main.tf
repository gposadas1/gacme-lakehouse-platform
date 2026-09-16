locals {
  tags = {
    project = "databricks-admin-lab"
    owner   = "gposadas"
    managed = "terraform"
  }
}

resource "azurerm_resource_group" "dbx" {
  name     = "rg-${var.prefix}-dbx"
  location = var.location
  tags     = local.tags
}

resource "azurerm_databricks_workspace" "this" {
  name                        = "dbw-${var.prefix}"
  resource_group_name         = azurerm_resource_group.dbx.name
  location                    = azurerm_resource_group.dbx.location
  sku                         = "premium"
  managed_resource_group_name = "rg-${var.prefix}-dbx-managed"

  custom_parameters {
    no_public_ip = true # Secure cluster connectivity
  }

  tags = local.tags
}
