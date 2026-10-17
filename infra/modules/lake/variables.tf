variable "prefix" {
  description = "Organization prefix, e.g. gacme. Names follow <type>-<prefix>-<workload>-<environment>."
  type        = string
}

variable "environment" {
  type = string
}

variable "location" {
  type = string
}

variable "storage_account_name" {
  description = "Override for the ADLS Gen2 account name (globally unique, 3-24 lowercase letters and digits). Defaults to st<prefix>lake<environment>."
  type        = string
  default     = null
}

variable "containers" {
  description = "One container per data domain; each becomes a Unity Catalog external location."
  type        = set(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
