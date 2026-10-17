# Domains must match the lake layer's containers
module "governance" {
  source = "../../../modules/governance"

  prefix               = var.prefix
  environment          = "prod"
  domains              = ["energy"]
  workspace_id         = var.workspace_id
  access_connector_id  = var.access_connector_id
  storage_account_name = var.storage_account_name
  admin_group          = var.admin_group
}
