variable "prefix" {
  description = "Organization prefix, e.g. gacme. Names follow <type>-<prefix>-<workload>-<environment>."
  type        = string
}

variable "environment" {
  description = "Environment name, e.g. dev or prod."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "sku" {
  description = "Databricks workspace tier. Premium is required for Unity Catalog and cluster policies."
  type        = string
  default     = "premium"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
