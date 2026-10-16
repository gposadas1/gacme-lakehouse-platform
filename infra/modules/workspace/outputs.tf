output "resource_group_name" {
  value = azurerm_resource_group.dbx.name
}

output "workspace_name" {
  value = azurerm_databricks_workspace.this.name
}

output "workspace_resource_id" {
  value = azurerm_databricks_workspace.this.id
}

output "workspace_url" {
  value = "https://${azurerm_databricks_workspace.this.workspace_url}"
}

output "workspace_id" {
  value = azurerm_databricks_workspace.this.workspace_id
}
