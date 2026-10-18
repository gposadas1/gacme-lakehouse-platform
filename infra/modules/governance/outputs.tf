output "catalog_names" {
  value = [for c in databricks_catalog.domain : c.name]
}

output "external_location_urls" {
  value = { for d, l in databricks_external_location.domain : d => l.url }
}

output "cluster_policy_ids" {
  value = {
    single_node = databricks_cluster_policy.single_node.id
    jobs        = databricks_cluster_policy.jobs.id
  }
}

output "schema_storage_roots" {
  value = { for k, s in databricks_schema.layer : k => s.storage_root }
}
