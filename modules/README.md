# modules — Terraform resource modules

This folder holds **resource-group scoped** Terraform modules. Root `main.tf` creates the resource group (subscription-level work), then calls a module here to create resources *inside* that group.

```text
20260922-terraform/
  main.tf                             ← resource group + module call
  modules/
    storage_account/                  ← storage account
    README.md                         ← this file
  params/
    dev.tfvars
    staging.tfvars
    prod.tfvars
```

A storage account is **not** a subscription-level resource. That is why it is not declared directly next to the resource group without a module boundary. The root module creates the group, then deploys this module into it.

---

## 1. Files in this folder

| File | What it deploys |
|---|---|
| `storage_account/` | One Azure Storage account (`azurerm_storage_account`) |

---

## 2. How `main.tf` calls this module

```hcl
module "storage_account" {
  source = "./modules/storage_account"

  location             = var.location
  resource_group_name  = azurerm_resource_group.this.name
  storage_account_name = var.storage_account_name
  sku_name             = var.storage_sku_name
  environment          = var.environment
}
```

| Field | Meaning |
|---|---|
| `source` | Local module path |
| `resource_group_name` | Deploy into the resource group created in `main.tf` |
| other inputs | Values passed from root variables / `params/*.tfvars` |

---

## 3. `storage_account` parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `location` | string | yes | Azure region for the storage account |
| `resource_group_name` | string | yes | Resource group that contains the account |
| `storage_account_name` | string | yes | Globally unique name, 3–24 lowercase letters and numbers |
| `sku_name` | string | yes | Replication / performance SKU (see allowed list below) |
| `environment` | string | yes | Tag value: `dev`, `staging`, or `production` |

Allowed `sku_name` values (same list as the Bicep module):

- `Standard_LRS`
- `Standard_GRS`
- `Standard_RAGRS`
- `Standard_ZRS`
- `Standard_GZRS`
- `Standard_RAGZRS`
- `Premium_LRS`
- `Premium_ZRS`

`sku_name` is split into `account_tier` + `account_replication_type` for the AzureRM provider.

These values are **not** set in the module. They come from root `main.tf`, which reads them from the environment tfvars files.

---

## 4. Environment param files (what each environment creates)

| File | Resource group | Storage account name | SKU |
|---|---|---|---|
| `params/dev.tfvars` | `rg-terraform-github-actions-dev` | `sttfpojdev` | `Standard_ZRS` |
| `params/staging.tfvars` | `rg-terraform-github-actions-staging` | `sttfpojstg` | `Standard_GRS` |
| `params/prod.tfvars` | `rg-terraform-github-actions-production` | `sttfpojprod` | `Standard_GRS` |

Names differ from the Bicep accounts (`stcajpoc*`) so the two stacks can coexist in the same subscription.

Override `storage_account_name` with GitHub Environment secret `STORAGE_ACCOUNT_NAME` if you need a different name.

---

## 5. What the storage account is configured with

| Setting | Value | Why |
|---|---|---|
| `account_kind` | `StorageV2` | General-purpose v2 account |
| `access_tier` | `Hot` | Default blob access tier |
| `allow_nested_items_to_be_public` | `false` | Blobs are not anonymously public |
| `shared_access_key_enabled` | `false` | Access is Azure AD / OAuth only |
| `https_traffic_only_enabled` | `true` | HTTP is rejected |
| `min_tls_version` | `TLS1_2` | Older TLS is rejected |
| `public_network_access_enabled` | `false` | No public endpoint (Checkov / private-by-default) |
| `network_rules.default_action` | `Deny` | Default network rule denies traffic |
| `network_rules.bypass` | `AzureServices` | Trusted Azure services can reach the account |
| `infrastructure_encryption_enabled` | `true` | Double encryption at rest |
| Tags | `environment`, `source: terraform-github-actions` | Same tagging pattern as the resource group |

---

## 6. Module outputs

Root `outputs.tf` surfaces these:

| Output | Meaning |
|---|---|
| `storage_account_name` | Name of the created account |
| `storage_account_id` | Azure resource ID |
| `primary_blob_endpoint` | Blob service URL |

---

## 7. Adding another resource later

1. Add a new folder in this directory, for example `modules/key_vault/`.
2. Call it from `main.tf` with the resource group name, the same pattern as the storage module.
3. Add any new variables to `variables.tf` and to `params/dev.tfvars`, `params/staging.tfvars`, and `params/prod.tfvars`.

---

## 8. Local check (validate only)

From the repo root:

```bash
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
```

That compiles the root module **and** `modules/storage_account`. It does not create Azure resources.

To preview or apply, use the commands in the root [README.md](../README.md) (`terraform plan` / `terraform apply`).
