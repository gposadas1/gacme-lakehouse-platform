locals {
  environment = "prod"

  tags = {
    project     = "gacme-lakehouse-platform"
    environment = local.environment
    owner       = "gposadas"
    managed     = "terraform"
  }
}

module "workspace" {
  source = "../../../modules/workspace"

  prefix      = var.prefix
  environment = local.environment
  location    = var.location
  tags        = local.tags
}
