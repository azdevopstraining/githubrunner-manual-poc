variable "location" {
  type        = string
  description = "Azure region for the storage account."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group that will contain the storage account."
}

variable "storage_account_name" {
  type        = string
  description = "Globally unique storage account name (3-24 lowercase letters and numbers)."

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 lowercase letters and numbers."
  }
}

variable "sku_name" {
  type        = string
  description = "Storage account SKU (account tier + replication)."

  validation {
    condition = contains([
      "Standard_LRS",
      "Standard_GRS",
      "Standard_RAGRS",
      "Standard_ZRS",
      "Standard_GZRS",
      "Standard_RAGZRS",
      "Premium_LRS",
      "Premium_ZRS",
    ], var.sku_name)
    error_message = "sku_name must be a supported Azure Storage SKU."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment tag."
}
