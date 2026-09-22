<<<<<<< HEAD
# Terraform CI/CD (from the Bicep pipeline)

This folder is a Terraform translation of the Bicep GitHub Actions layout in `containerapp-jobs-poc-githubrunner`.

| Bicep | Terraform |
|---|---|
| `.github/workflows/multistage-cicd-pipeline.yml` | same path, Terraform jobs |
| `main.bicep` | `main.tf` + `variables.tf` + `outputs.tf` + `versions.tf` |
| `modules/storageAccount.bicep` | `modules/storage_account/` |
| `params/*.bicepparam` | `params/*.tfvars` |
| `bicep build` / `az deployment sub validate` | `terraform fmt` + `terraform validate` |
| `az deployment sub what-if` | `terraform plan` |
| `az deployment sub create` | `terraform apply` |

PRs run lint, Checkov, and plan. They do **not** apply. Merge (or push) to `main` and manual runs apply, one environment at a time: dev → staging → production.

---

## GitHub runner

All jobs use **`runs-on: [ci]`** on the Azure Container Apps job `github-actions-runner-job`.

`azdevopstraining` is a GitHub **user account**, not an organization. A personal account cannot register org-level runners (`/orgs/.../registration-token` returns 404). This job must stay **repo-scoped** to `terraform-poc`:

| Item | Value |
|---|---|
| Job | `github-actions-runner-job` |
| Environment | `dev-github-runners` |
| Label | `ci` (not `self-hosted`) |
| Scope | repo |
| `GH_URL` | `https://github.com/azdevopstraining/terraform-poc` |
| Registration API | `https://api.github.com/repos/azdevopstraining/terraform-poc/actions/runners/registration-token` |

The PAT on the job needs repository **Administration** Read and write, **Actions** Read-only, and **Metadata** Read-only on `terraform-poc`.

To run the same image for another repo (`kopius`, `containerapp-jobs-poc-githubrunner`), create a **second** Container Apps job with that repo’s `GH_URL`. One runner process can register to only one repo.

Do not change the workflow to `ubuntu-latest` or `self-hosted`. Container Apps jobs have no Docker daemon, so Docker actions (`azure/cli@v2`, `checkov-action`, containerized `setup-terraform`) will fail.

---

## GitHub Environment secrets

Create environments named exactly `dev`, `staging`, and `production`.

| Secret | Required | Purpose |
|---|---|---|
| `AZURE_CLIENT_ID` | yes | OIDC app (federated credential subject `repo:ORG/REPO:environment:<name>`) |
| `AZURE_TENANT_ID` | yes | Azure tenant |
| `AZURE_SUBSCRIPTION_ID` | yes | Target subscription |
| `TF_STATE_RESOURCE_GROUP` | yes | Resource group of the **state** storage account (not the app RG) |
| `TF_STATE_STORAGE_ACCOUNT` | yes | Existing storage account used only for Terraform state |
| `TF_STATE_CONTAINER` | no | Blob container; defaults to `tfstate` |
| `STORAGE_ACCOUNT_NAME` | no | Overrides `storage_account_name` in `params/*.tfvars` |

The OIDC identity needs:

- **Contributor** on the target subscription (to create `rg-terraform-github-actions-*` and the storage accounts)
- **Storage Blob Data Contributor** on the state storage account (backend uses Azure AD, not account keys)

Do not put passwords or tokens in `params/*.tfvars`.

---

## State backend (one-time)

Terraform needs remote state. Create a dedicated account **outside** this stack (do not reuse `sttfpojdev` / `sttfpojstg` / `sttfpojprod`):

```bash
az group create --name rg-tfstate --location eastus
az storage account create \
  --name sttfstate<unique> \
  --resource-group rg-tfstate \
  --location eastus \
  --sku Standard_LRS
az storage container create \
  --name tfstate \
  --account-name sttfstate<unique> \
  --auth-mode login
```

State keys written by the pipeline:

- `dev.terraform.tfstate`
- `staging.terraform.tfstate`
- `production.terraform.tfstate`

---

## What each environment creates

| File | Resource group | Storage account | SKU |
|---|---|---|---|
| `params/dev.tfvars` | `rg-terraform-github-actions-dev` | `sttfpojdev` | `Standard_ZRS` |
| `params/staging.tfvars` | `rg-terraform-github-actions-staging` | `sttfpojstg` | `Standard_GRS` |
| `params/prod.tfvars` | `rg-terraform-github-actions-production` | `sttfpojprod` | `Standard_GRS` |

Names are intentionally different from the Bicep accounts (`stcajpoc*`) so both stacks can exist in the same subscription.

---

## Local commands

```bash
az login
export ARM_SUBSCRIPTION_ID="<subscription-id>"

terraform init -backend=false
terraform fmt -check -recursive
terraform validate

terraform plan -var-file=params/dev.tfvars
terraform apply -var-file=params/dev.tfvars
```

Keep `TERRAFORM_VERSION` / `AZURERM_PROVIDER_VERSION` in the workflow in sync with `required_providers` in `versions.tf`.

Checkov uses the same skips as the Bicep workflow, plus `CKV2_AZURE_1` (CMK) and `CKV2_AZURE_33` (private endpoint). The Bicep storage module also does not deploy those.
=======
##
>>>>>>> 5d41da0a220488abf17bd2cfcaec63d3640b81cb
