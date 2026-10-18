variable "prefix" {
  type = string
}

variable "environment" {
  type = string
}

variable "domains" {
  description = "Data domains. Each gets a container (created by the lake layer), an external location, and a <domain>_<environment> catalog."
  type        = set(string)
}

variable "workspace_id" {
  description = "Numeric ID of this environment's workspace; the only workspace bound to its catalogs"
  type        = string
}

variable "access_connector_id" {
  description = "Resource ID of the Azure Databricks access connector that can read and write the storage account"
  type        = string
}

variable "storage_account_name" {
  type = string
}

variable "schemas" {
  description = "Schemas created in every domain catalog"
  type        = set(string)
  default     = ["bronze", "silver", "gold"]
}

variable "admin_group" {
  description = "Account group that owns the Unity Catalog objects"
  type        = string
}

variable "node_types" {
  description = "VM sizes the cluster policies allow; the first is the default"
  type        = list(string)
  default     = ["Standard_D4ds_v5", "Standard_DS3_v2"]
}
