# Unity Catalog objects for each data domain, plus the workspace's cluster policies.
#
# The storage credential, external location, catalog and schemas live in the metastore, so they
# outlive the workspace: destroying the workspace to save cost keeps them and their data.
# Cluster policies live in the workspace and are recreated on the next apply.

locals {
  # Every (domain, schema) pair, keyed "energy.bronze"
  schemas = {
    for pair in setproduct(var.domains, var.schemas) : "${pair[0]}.${pair[1]}" => {
      domain = pair[0]
      name   = pair[1]
    }
  }
}

# One per environment: wraps the access connector, which has blob access to the whole account
resource "databricks_storage_credential" "this" {
  name  = "sc_${var.prefix}_${var.environment}"
  owner = var.admin_group

  azure_managed_identity {
    access_connector_id = var.access_connector_id
  }

  comment = "Access connector for ${var.prefix} ${var.environment} lakehouse storage. Managed by Terraform."
}

resource "databricks_external_location" "domain" {
  for_each = var.domains

  name            = "el_${var.prefix}_${each.value}_${var.environment}"
  url             = "abfss://${each.value}@${var.storage_account_name}.dfs.core.windows.net/"
  credential_name = databricks_storage_credential.this.name
  owner           = var.admin_group
  comment         = "The ${each.value} container. Managed by Terraform."
}

resource "databricks_catalog" "domain" {
  for_each = var.domains

  name         = "${each.value}_${var.environment}"
  storage_root = "${databricks_external_location.domain[each.value].url}${each.value}_${var.environment}"
  owner        = var.admin_group
  comment      = "${each.value} data, ${var.environment}. Managed by Terraform."
}

resource "databricks_schema" "layer" {
  for_each = local.schemas

  catalog_name = databricks_catalog.domain[each.value.domain].name
  name         = each.value.name
  owner        = var.admin_group
  comment      = "Medallion ${each.value.name} layer. Managed by Terraform."
}

# Small, auto-terminating compute only. Admins can still bypass policies; everyone else can't.
resource "databricks_cluster_policy" "single_node" {
  name                  = "${var.prefix}-${var.environment}-single-node"
  max_clusters_per_user = 1

  definition = jsonencode({
    "cluster_type"                                = { type = "fixed", value = "all-purpose" }
    "spark_version"                               = { type = "unlimited", defaultValue = "auto:latest-lts" }
    "num_workers"                                 = { type = "fixed", value = 0, hidden = true }
    "spark_conf.spark.databricks.cluster.profile" = { type = "fixed", value = "singleNode", hidden = true }
    "spark_conf.spark.master"                     = { type = "fixed", value = "local[*,4]", hidden = true }
    "custom_tags.ResourceClass"                   = { type = "fixed", value = "SingleNode", hidden = true }
    "node_type_id"                                = { type = "allowlist", values = var.node_types, defaultValue = var.node_types[0] }
    "autotermination_minutes"                     = { type = "range", minValue = 10, maxValue = 60, defaultValue = 20 }
    "data_security_mode"                          = { type = "fixed", value = "SINGLE_USER" }
    "azure_attributes.availability"               = { type = "fixed", value = "ON_DEMAND_AZURE", hidden = true }
    "custom_tags.project"                         = { type = "fixed", value = "${var.prefix}-lakehouse-platform" }
  })
}

resource "databricks_cluster_policy" "jobs" {
  name = "${var.prefix}-${var.environment}-jobs"

  definition = jsonencode({
    "cluster_type"                  = { type = "fixed", value = "job" }
    "spark_version"                 = { type = "unlimited", defaultValue = "auto:latest-lts" }
    "node_type_id"                  = { type = "allowlist", values = var.node_types, defaultValue = var.node_types[0] }
    "num_workers"                   = { type = "range", minValue = 0, maxValue = 2, defaultValue = 1 }
    "autoscale.max_workers"         = { type = "range", maxValue = 2 }
    "data_security_mode"            = { type = "fixed", value = "SINGLE_USER" }
    "azure_attributes.availability" = { type = "fixed", value = "SPOT_WITH_FALLBACK_AZURE", hidden = true }
    "custom_tags.project"           = { type = "fixed", value = "${var.prefix}-lakehouse-platform" }
  })
}
