# Lakehouse storage, kept apart from the workspace so the workspace can be destroyed and
# redeployed (to stop idle cost) without touching data.

resource "azurerm_resource_group" "lake" {
  name     = "rg-${var.prefix}-lake-${var.environment}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "lake" {
  name                            = coalesce(var.storage_account_name, "st${var.prefix}lake${var.environment}")
  resource_group_name             = azurerm_resource_group.lake.name
  location                        = azurerm_resource_group.lake.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  is_hns_enabled                  = true # ADLS Gen2, required by Unity Catalog
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = var.tags

  # Holds the catalog's data. Removing it should take a deliberate code change.
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "domain" {
  for_each = var.containers

  name                  = each.value
  storage_account_id    = azurerm_storage_account.lake.id
  container_access_type = "private"
}

# Managed identity Unity Catalog uses to reach the storage account (no secrets)
resource "azurerm_databricks_access_connector" "this" {
  name                = "dbac-${var.prefix}-${var.environment}"
  resource_group_name = azurerm_resource_group.lake.name
  location            = azurerm_resource_group.lake.location

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# The CI identity can assign this one role and no other (conditional RBAC Administrator, see bootstrap)
resource "azurerm_role_assignment" "connector_blob" {
  scope                = azurerm_storage_account.lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}
