variable "prefix" {
  type    = string
  default = "gacme"
}

variable "location" {
  type    = string
  default = "westus2"
}

variable "storage_account_name" {
  description = "Set only if the default st<prefix>lake<env> name is taken"
  type        = string
  default     = null
}
