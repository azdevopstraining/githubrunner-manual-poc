locals {
  sku_parts                = split("_", var.sku_name)
  account_tier             = local.sku_parts[0]
  account_replication_type = local.sku_parts[1]
}

resource "azurerm_storage_account" "this" {
  name                              = var.storage_account_name
  resource_group_name               = var.resource_group_name
  location                          = var.location
  account_kind                      = "StorageV2"
  account_tier                      = local.account_tier
  account_replication_type          = local.account_replication_type
  access_tier                       = "Hot"
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  public_network_access_enabled     = false
  infrastructure_encryption_enabled = true
  local_user_enabled                = false
  cross_tenant_replication_enabled  = false

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = {
    environment = var.environment
    source      = "terraform-github-actions"
  }
}
