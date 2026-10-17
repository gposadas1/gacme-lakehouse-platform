output "resource_group_name" {
  value = azurerm_resource_group.lake.name
}

output "storage_account_name" {
  value = azurerm_storage_account.lake.name
}

output "access_connector_id" {
  value = azurerm_databricks_access_connector.this.id
}
