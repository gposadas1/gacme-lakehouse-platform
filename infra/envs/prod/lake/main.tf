locals {
  environment = "prod"

  tags = {
    project     = "gacme-lakehouse-platform"
    environment = local.environment
    owner       = "gposadas"
    managed     = "terraform"
  }
}

module "lake" {
  source = "../../../modules/lake"

  prefix               = var.prefix
  environment          = local.environment
  location             = var.location
  storage_account_name = var.storage_account_name
  containers           = ["energy"]
  tags                 = local.tags
}
