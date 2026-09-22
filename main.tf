locals {
  resource_group_name = "rg-terraform-github-actions-${var.environment}"
}

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags = {
    environment = var.environment
    source      = "terraform-github-actions"
  }
}

module "storage_account" {
  source = "./modules/storage_account"

  location             = var.location
  resource_group_name  = azurerm_resource_group.this.name
  storage_account_name = var.storage_account_name
  sku_name             = var.storage_sku_name
  environment          = var.environment
}
