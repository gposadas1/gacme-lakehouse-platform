# Inputs come from the azure and lake layers' outputs; ci/terraform.sh passes them as TF_VAR_*.

variable "workspace_url" {
  type = string
}

variable "workspace_resource_id" {
  type = string
}

variable "workspace_id" {
  type = string
}

variable "access_connector_id" {
  type = string
}

variable "storage_account_name" {
  type = string
}

variable "prefix" {
  type    = string
  default = "gacme"
}

variable "admin_group" {
  type    = string
  default = "gacme-platform-admins"
}
