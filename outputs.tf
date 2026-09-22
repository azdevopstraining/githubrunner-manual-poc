output "resource_group_name" {
  description = "Name of the created resource group."
  value       = azurerm_resource_group.this.name
}

output "storage_account_name" {
  description = "Name of the created storage account."
  value       = module.storage_account.storage_account_name
}

output "storage_account_id" {
  description = "Azure resource ID of the storage account."
  value       = module.storage_account.storage_account_id
}

output "primary_blob_endpoint" {
  description = "Blob service URL for the storage account."
  value       = module.storage_account.primary_blob_endpoint
}
