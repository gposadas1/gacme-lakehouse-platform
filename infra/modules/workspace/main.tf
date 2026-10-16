resource "azurerm_resource_group" "dbx" {
  name     = "rg-${var.prefix}-dbx-${var.environment}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_databricks_workspace" "this" {
  name                        = "dbw-${var.prefix}-${var.environment}"
  resource_group_name         = azurerm_resource_group.dbx.name
  location                    = azurerm_resource_group.dbx.location
  sku                         = var.sku
  managed_resource_group_name = "rg-${var.prefix}-dbx-${var.environment}-managed"

  custom_parameters {
    no_public_ip = true # Secure cluster connectivity
  }

  tags = var.tags
}
