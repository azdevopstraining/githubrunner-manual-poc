variable "environment" {
  type        = string
  description = "Deployment environment. Drives resource group name and tags. GitHub Environments use the same values."

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "environment must be one of: dev, staging, production."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the resource group and storage account."
  default     = "eastus"
}

variable "storage_account_name" {
  type        = string
  description = "Globally unique storage account name (3-24 lowercase letters and numbers)."

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 lowercase letters and numbers."
  }
}

variable "storage_sku_name" {
  type        = string
  description = "Storage account SKU (account tier + replication), matching the Bicep storageSkuName values."
  default     = "Standard_LRS"

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
    ], var.storage_sku_name)
    error_message = "storage_sku_name must be a supported Azure Storage SKU."
  }
}
