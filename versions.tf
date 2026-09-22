terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.37.0"
    }
  }

  # Partial config. CI supplies -backend-config from GitHub Environment secrets.
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
  use_oidc = true
}
