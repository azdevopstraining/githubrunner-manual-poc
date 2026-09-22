output "storage_account_name" {
  description = "Name of the created storage account."
  value       = azurerm_storage_account.this.name
}

output "storage_account_id" {
  description = "Azure resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "primary_blob_endpoint" {
  description = "Blob service URL for the storage account."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}
