# GitHub runner on Container Apps Jobs — Azure portal (manual)

Same resources and order as `github-runner.md`. Create everything in the portal unless a step says otherwise.
Do not reuse names from the existing set (`containerapps-jobs-rg`, `vnet-github-runners`, `containerappsgithubacr`, `dev-github-runners`).

Do not skip ahead: environment must use `snet-aca-fw` before the job is created, and firewall allow rules must exist before the route table is attached to that subnet.
Do not use ACR Tasks (`az acr build`) — this subscription returns TasksOperationsNotAllowed. Push the image with Docker from your laptop while ACR public access is still on.
Do not store a GitHub registration token in Azure — store the PAT. The job fetches a short-lived token at runtime.
The final state disables public access on both the Container Apps environment
and ACR, and uses `id-github-runner-fw` for managed-identity image pulls.

Azure Firewall Standard is billed hourly even when idle. Confirm cost before step 8.

--------------------------------------------------------------------------------
0. Names (use these exactly)
--------------------------------------------------------------------------------

Region: West US

| What | Name |
| --- | --- |
| Resource group | github-runners-fw-rg |
| Container Apps environment | env-github-runners-fw |
| Container Apps job | github-actions-runner-job-fw |
| Container registry | azdtghrunnerfwacr |
| Image | azdtghrunnerfwacr.azurecr.io/github-actions-runner:2.337.0-1 |
| User-assigned identity | id-github-runner-fw |
| GitHub owner / repo | azdevopstraining / githubrunner-manual-poc |
| Virtual network | vnet-github-runners-fw (10.30.0.0/16) |
| Private endpoint subnet | snet-aca-pe-fw (10.30.0.0/27) |
| Container Apps subnet | snet-aca-fw (10.30.1.0/27) delegated Microsoft.App/environments |
| Firewall subnet | AzureFirewallSubnet (10.30.2.0/26) — this name cannot change |
| ACR private endpoint | pe-acr-fw / pe-conn-acr-fw |
| ACR private DNS zone | privatelink.azurecr.io (Azure-required name) |
| ACR DNS link | dns-link-acr-fw |
| Environment private endpoint | pe-env-github-runners-fw / pe-conn-env-github-runners-fw |
| ACA private DNS zone | privatelink.westus.azurecontainerapps.io (Azure-required name) |
| ACA DNS link | dns-link-aca-fw |
| Firewall public IP | pip-afw-github-runners-fw |
| Firewall | afw-github-runners-fw |
| Firewall policy | afwp-standard-github-runners-fw |
| Route table | rt-aca-github-runners-fw |
| Runner source (laptop) | C:\Users\HP\Documents\github-runner\container-apps-ci-cd-runner-tutorial |

PAT: paste your token when the job secret is created. Administration on the repo must be Read and write.

--------------------------------------------------------------------------------
1. Portal and resource providers (once)
--------------------------------------------------------------------------------

1. Open https://portal.azure.com and sign in.
2. Search **Subscriptions** → your subscription → **Resource providers**.
3. Register if Status is not Registered:
   - Microsoft.App
   - Microsoft.OperationalInsights
   - Microsoft.ContainerRegistry
   - Microsoft.Network
4. Search **Cloud Shell** is not required. Stay in the portal for the rest except the Docker push in step 12.

--------------------------------------------------------------------------------
2. Prove the PAT (GitHub website)
--------------------------------------------------------------------------------

1. GitHub → Settings → Developer settings → Personal access tokens.
2. For a fine-grained PAT, select repository
   `azdevopstraining/githubrunner-manual-poc` and grant:
   - **Administration: Read and write** (runner registration token)
   - **Actions: Read-only** (KEDA queue polling)
   - **Metadata: Read-only**
   For a classic PAT on a private repository, grant `repo`.
3. Open https://github.com/azdevopstraining/githubrunner-manual-poc → Settings → Actions → Runners.
4. You should be able to see the Runners page (no 403). Do not create a runner by hand. The job does that.
5. Before saving the PAT in Azure, validate it from PowerShell. Run the first
   line exactly, then paste the PAT only at the hidden prompt:

   ```powershell
   $securePat = Read-Host -Prompt "Enter GitHub PAT" -AsSecureString
   $GITHUB_PAT = [Net.NetworkCredential]::new("", $securePat).Password
   $headers = @{
     Accept = "application/vnd.github+json"
     Authorization = "Bearer $GITHUB_PAT"
     "X-GitHub-Api-Version" = "2022-11-28"
   }
   $validation = Invoke-RestMethod -Method Post -Headers $headers `
     -Uri "https://api.github.com/repos/azdevopstraining/githubrunner-manual-poc/actions/runners/registration-token"

   if ([string]::IsNullOrWhiteSpace($validation.token)) {
     throw "PAT validation failed: GitHub returned no registration token."
   }
   Write-Host "PAT validated successfully. Registration token expires at $($validation.expires_at)."
   Remove-Variable validation
   ```

   A `401`, `403`, or `404` means the PAT is invalid or does not include this
   repository. The temporary registration token is deliberately not printed.

--------------------------------------------------------------------------------
3. Resource group
--------------------------------------------------------------------------------

1. Search **Resource groups** → **Create**.
2. Subscription: yours.
3. Resource group: `github-runners-fw-rg`
4. Region: **West US**
5. Review + create → Create.

--------------------------------------------------------------------------------
4. Virtual network and subnets
--------------------------------------------------------------------------------

Do not put private endpoints on `snet-aca-fw`. /27 is the minimum for workload profiles.

1. Search **Virtual networks** → **Create**.
2. Basics:
   - Resource group: `github-runners-fw-rg`
   - Name: `vnet-github-runners-fw`
   - Region: **West US**
3. IP addresses:
   - Delete the default 10.0.0.0/16 space if the wizard added it.
   - IPv4 address space: `10.30.0.0/16`
   - Remove the default subnet.
   - Add subnet **snet-aca-pe-fw**
     - Starting address: `10.30.0.0`
     - Size: **/27** (`10.30.0.0/27`)
     - Private endpoint network policy: **Disabled** (or leave default Disabled)
     - Do not add a subnet delegation.
   - Add subnet **snet-aca-fw**
     - Starting address: `10.30.1.0`
     - Size: **/27** (`10.30.1.0/27`)
     - Subnet delegation: **Microsoft.App/environments**
   - Add subnet **AzureFirewallSubnet** (name must match exactly)
     - Starting address: `10.30.2.0`
     - Size: **/26** (`10.30.2.0/26`)
     - No delegation.
4. Security / Bastion / Firewall in the VNet wizard: leave off. Firewall is created in step 8.
5. Review + create → Create.

6. After deployment: open the VNet → **Subnets** and confirm:

| Subnet | Prefix | Notes |
| --- | --- | --- |
| snet-aca-pe-fw | 10.30.0.0/27 | PEs only |
| snet-aca-fw | 10.30.1.0/27 | Delegated Microsoft.App/environments |
| AzureFirewallSubnet | 10.30.2.0/26 | Firewall only |

If `snet-aca-fw` has no delegation: Subnet → Edit → Delegate subnet to a service → **Microsoft.App/environments** → Save.

--------------------------------------------------------------------------------
5. Azure Container Registry (keep public access ON)
--------------------------------------------------------------------------------

1. Search **Container registries** → **Create**.
2. Basics:
   - Resource group: `github-runners-fw-rg`
   - Registry name: `azdtghrunnerfwacr` (globally unique, no hyphens)
   - Location: **West US**
   - SKU: **Premium** (required for private endpoint + data endpoint)
3. Networking: **Public access** (you will lock this in step 14b after the job
   switches to managed identity).
4. Review + create → Create.

5. Open `azdtghrunnerfwacr` → **Networking**:
   - Public network access: **All networks** (still)
   - Enable dedicated data endpoint: **On** → Save.

6. The portal currently might not show **Authentication as ARM** on the registry.
   This is a preview ACR configuration and is **enabled by default**. Check it in
   Azure Cloud Shell or PowerShell with:

   `az acr config authentication-as-arm show --registry azdtghrunnerfwacr --resource-group github-runners-fw-rg --query status -o tsv`

   Expected output: `enabled`.

   Only if it returns `disabled`, enable it with:

   `az acr config authentication-as-arm update --registry azdtghrunnerfwacr --resource-group github-runners-fw-rg --status enabled`

   This setting is different from **Access keys → Admin user**. Keep the admin
   user disabled; the Container Apps job authenticates with its managed identity
   and the `AcrPull` role configured in the next section.

--------------------------------------------------------------------------------
6. Managed identity with AcrPull
--------------------------------------------------------------------------------

1. Search **Managed Identities** → **Create**.
2. Resource group: `github-runners-fw-rg`
3. Region: **West US**
4. Name: `id-github-runner-fw`
5. Review + create → Create.

6. Open `azdtghrunnerfwacr` → **Access control (IAM)** → **Add** → **Add role assignment**.
7. Role: **AcrPull**
8. Members: **Managed identity** → Select → `id-github-runner-fw`
9. Review + assign.

--------------------------------------------------------------------------------
7. ACR private endpoint and DNS (do not disable public access yet)
--------------------------------------------------------------------------------

1. Open `azdtghrunnerfwacr` → **Networking** → **Private access** → **+ Create a private endpoint**
   (or search **Private endpoints** → Create).
2. Basics:
   - Resource group: `github-runners-fw-rg`
   - Name: `pe-acr-fw`
   - Network interface name: leave default
   - Region: **West US**
3. Resource:
   - Target: this registry
   - Target sub-resource: **registry**
   - Connection name if asked: `pe-conn-acr-fw`
4. Virtual network:
   - VNet: `vnet-github-runners-fw`
   - Subnet: `snet-aca-pe-fw` (not snet-aca-fw)
5. DNS:
   - Integrate with private DNS zone: **Yes**
   - Subscription: yours
   - Private DNS zone: create **privatelink.azurecr.io** in `github-runners-fw-rg`
6. Review + create → Create.

7. Open the new private DNS zone **privatelink.azurecr.io** → **Virtual network links**:
   - Link name: `dns-link-acr-fw` (rename/create if the wizard used another name)
   - VNet: `vnet-github-runners-fw`
   - Enable auto-registration: **No**
8. Open **Overview** / **Record sets** and confirm A records exist for the registry and data endpoint.
9. Open `pe-acr-fw` → confirm Connection status **Approved** and a private IP is shown.

--------------------------------------------------------------------------------
8. Azure Firewall and allow rules (before the route table)
--------------------------------------------------------------------------------

Attach the UDR only to `snet-aca-fw`. Never attach it to `snet-aca-pe-fw` or `AzureFirewallSubnet`.
ACR private-endpoint traffic stays in `10.30.0.0/27` and does not hairpin through the firewall.

### 8a. Public IP

1. Search **Public IP addresses** → **Create**.
2. Resource group: `github-runners-fw-rg`
3. Region: **West US**
4. Name: `pip-afw-github-runners-fw`
5. SKU: **Standard**
6. Assignment: **Static**
7. Review + create → Create.

### 8b. Firewall policy (rules first)

1. Search **Firewall policies** → **Create**.
2. Resource group: `github-runners-fw-rg`
3. Name: `afwp-standard-github-runners-fw`
4. Region: **West US**
5. Policy tier: **Standard**
6. Review + create → Create (you can skip parent policy / threat intel extras).

7. Open `afwp-standard-github-runners-fw` → **Application rules** → **Add a rule collection**.

**Collection 1 — aca-platform**
- Name: `aca-platform`
- Priority: `110`
- Action: **Allow**
- Rule collection group: DefaultApplicationRuleCollectionGroup
- Rule name: `aca-required`
- Source type: IP Address
- Source: `10.30.1.0/27`
- Protocol: Http:80, Https:443
- Destination type: FQDN
- Destination:
  `mcr.microsoft.com,*.data.mcr.microsoft.com,packages.aks.azure.com,acs-mirror.azureedge.net,*.azurecontainerapps.dev`
- Add.

In the same `aca-platform` collection, add a second application rule:

- Rule name: `acr-runner-registry`
- Source: `10.30.1.0/27`
- Protocol: Https:443
- Destination type: FQDN
- Destination:
  `azdtghrunnerfwacr.azurecr.io,azdtghrunnerfwacr.westus.data.azurecr.io`
- Add.

This exact ACR allow rule is required even with the ACR private endpoint. Normal
image traffic resolves privately, but Container Apps image validation and
fallback paths can still require the routed registry/data endpoint.

**Collection 2 — github-runner**
- Name: `github-runner`
- Priority: `200`
- Action: **Allow**
- Rule name: `github-actions`
- Source: `10.30.1.0/27`
- Protocol: Http:80, Https:443
- Destination FQDNs:
  `github.com,api.github.com,*.github.com,*.actions.githubusercontent.com,*.githubusercontent.com,ghcr.io,*.pkg.github.com,pkg-containers.githubusercontent.com,releases.astral.sh,releases.hashicorp.com,*.blob.core.windows.net`
- Add.

**Collection 3 — azure-identity**
- Name: `azure-identity`
- Priority: `210`
- Action: **Allow**
- Rule name: `aad-mi`
- Source: `10.30.1.0/27`
- Protocol: Https:443
- Destination FQDNs:
  `login.microsoft.com,*.login.microsoft.com,login.microsoftonline.com,*.login.microsoftonline.com,*.identity.azure.net`
- Add.

8. **Network rules** → **Add a rule collection**.

**Collection — azure-platform**
- Name: `azure-platform`
- Priority: `100`
- Action: **Allow**
- Rule name: `aad`
- Source: `10.30.1.0/27`
- Protocol: TCP
- Destination ports: `443`
- Destination type: Service Tag
- Destination: **AzureActiveDirectory**
- Add.

### 8c. Firewall

1. Search **Firewalls** → **Create**.
2. Resource group: `github-runners-fw-rg`
3. Name: `afw-github-runners-fw`
4. Region: **West US**
5. Availability: none / zone redundant as you prefer (none is fine for this POC).
6. Firewall SKU: **Standard**
7. Under **Firewall Management NIC**, leave **Enable Firewall Management NIC**
   **unchecked**. In the current portal this is how you keep the firewall's
   forced-tunneling capability disabled; there might not be a separate
   **Forced tunneling** switch. It is different from the route table in step 9.
   Enabling the management NIC requires another `/26` subnet named
   `AzureFirewallManagementSubnet` and another public IP, which this design
   does not use.
8. Firewall management: **Use a Firewall Policy** → `afwp-standard-github-runners-fw`
9. Choose a virtual network: **Use existing** → `vnet-github-runners-fw`
   (AzureFirewallSubnet must already exist; the create blade fails without it.)
10. Public IP: `pip-afw-github-runners-fw`
11. Review + create → Create. Wait until **Succeeded** (often 10–20 minutes).

12. Open `afw-github-runners-fw` → Overview. Copy:
    - **Firewall private IP** (needed in step 9)
    - Public IP on `pip-afw-github-runners-fw`
13. Verify **Firewall policy** is `afwp-standard-github-runners-fw`, not blank. The
    policy and firewall must both be **Standard**. A policy that exists but is
    not attached has no effect and produces `Deny. No rule matched` in logs.
    Azure cannot attach a Premium policy to a Standard firewall.

    If the policy field is blank, attach it before creating the route table:

    ```powershell
    $POLICY_ID = az network firewall policy show `
      --resource-group github-runners-fw-rg `
      --name afwp-standard-github-runners-fw `
      --query id -o tsv

    az network firewall update `
      --resource-group github-runners-fw-rg `
      --name afw-github-runners-fw `
      --firewall-policy $POLICY_ID

    az network firewall show `
      --resource-group github-runners-fw-rg `
      --name afw-github-runners-fw `
      --query "{state:provisioningState,tier:sku.tier,policy:firewallPolicy.id}" `
      --output json
    ```

    Continue only when state is `Succeeded`, tier is `Standard`, and policy
    ends in `/afwp-standard-github-runners-fw`. Do not try to downgrade an
    existing Premium policy; create this separate Standard policy instead.

--------------------------------------------------------------------------------
9. Route table — attach to snet-aca-fw last
--------------------------------------------------------------------------------

1. Search **Route tables** → **Create**.
2. Resource group: `github-runners-fw-rg`
3. Region: **West US**
4. Name: `rt-aca-github-runners-fw`
5. Propagate gateway routes: **No**
6. Review + create → Create.

7. Open the route table → **Routes** → **Add**.

Route 1
- Name: `to-azure-firewall`
- Address prefix: `0.0.0.0/0`
- Next hop type: **Virtual appliance**
- Next hop address: the firewall **private** IP from step 8c
- Add.

Route 2
- Name: `firewall-pip-internet`
- Address prefix: `<firewall-public-ip>/32` (example `20.x.x.x/32`)
- Next hop type: **Internet**
- Add.

8. Before associating the route table, confirm:
   - `afw-github-runners-fw` provisioning status is **Succeeded**.
   - Route 1 uses the firewall **private IP**, not its public IP.
   - The firewall policy contains the Container Apps, GitHub and identity allow
     rules from step 8b. Associating before these rules exist can block the
     environment and runner.
9. Open `rt-aca-github-runners-fw` → **Subnets** → **Associate**.
10. In **Associate subnet**, select:
    - Virtual network: `vnet-github-runners-fw`
    - Subnet: **snet-aca-fw**
    - Select **OK**.

    This association is required. The `0.0.0.0/0` route applies to resources in
    `snet-aca-fw` only and sends their outbound traffic to the firewall.
11. Verify the association:
    - Open `vnet-github-runners-fw` → **Subnets**.
    - `snet-aca-fw` must show route table `rt-aca-github-runners-fw`.
    - `snet-aca-pe-fw` and `AzureFirewallSubnet` must show no route table.

    Do not associate this route table with `snet-aca-pe-fw` or
    `AzureFirewallSubnet`.

--------------------------------------------------------------------------------
10. Container Apps environment on snet-aca-fw
--------------------------------------------------------------------------------

The **Container Apps Environments** list in some portal versions has no
**Create** button. If you see the same list-only page, create the environment
from Azure Cloud Shell instead:

1. Select the **Cloud Shell** (`>_`) icon at the top of the Azure portal and
   choose **PowerShell**.
2. Run:

   ```powershell
   az extension add --name containerapp --upgrade
   az provider register --namespace Microsoft.App

   $ACA_SUBNET_ID = az network vnet subnet show `
     --resource-group github-runners-fw-rg `
     --vnet-name vnet-github-runners-fw `
     --name snet-aca-fw `
     --query id -o tsv

   az containerapp env create `
     --name env-github-runners-fw `
     --resource-group github-runners-fw-rg `
     --location westus `
     --infrastructure-subnet-resource-id $ACA_SUBNET_ID
   ```

   This creates the default **workload profiles** environment with an external
   virtual IP. Do not add `--internal-only`; public network access is disabled
   and the private endpoint is added in step 11.
3. Verify that the environment uses the intended subnet:

   ```powershell
   az containerapp env show `
     --name env-github-runners-fw `
     --resource-group github-runners-fw-rg `
     --query "properties.vnetConfiguration" -o json
   ```

   `infrastructureSubnetId` must contain `snet-aca-fw` and must not be null.

If your portal does display **Create**, the equivalent portal settings are:

1. Select **Create**.
2. Basics:
   - Resource group: `github-runners-fw-rg`
   - Environment name: `env-github-runners-fw`
   - Region: **West US**
   - Environment type: **Workload profiles** (default). Consumption-only does not support UDR.
3. Monitoring: leave a new Log Analytics workspace, or pick one in this RG.
4. Networking:
   - Use your own virtual network: **Yes**
   - Virtual network: `vnet-github-runners-fw`
   - Infrastructure subnet: **snet-aca-fw** (`10.30.1.0/27`)
   - Virtual IP: **External** (you disable public access in the next step; this matches the CLI path, not `--internal-only`)
   - Public network access: you can leave Enabled here and disable in step 11, or set Disabled now if the blade allows it with a private endpoint.
5. Review + create → Create. Wait until Succeeded.

6. Open `env-github-runners-fw` → **Networking**. Confirm the infrastructure subnet is `snet-aca-fw`, not empty.
7. The environment now has a Log Analytics workspace. Complete Appendix A to
   enable firewall diagnostics before testing the runner.

--------------------------------------------------------------------------------
11. Lock down inbound: disable public access, ACA private endpoint + DNS
--------------------------------------------------------------------------------

1. Open `env-github-runners-fw` → **Networking**.
2. Public network access: **Disabled** → Save.
   Private endpoints are only valid when public access is Disabled.

3. Same Networking blade → **Add** private endpoint (or Create a private endpoint).
   - Resource group: `github-runners-fw-rg`
   - Name: `pe-env-github-runners-fw`
   - Region: **West US**
   - Target sub-resource: **managedEnvironments**
   - Connection name: `pe-conn-env-github-runners-fw`
   - VNet: `vnet-github-runners-fw`
   - Subnet: `snet-aca-pe-fw`
   - Integrate with private DNS zone: **Yes** if the blade offers `privatelink.westus.azurecontainerapps.io`
4. Review + create → Create.

If the wizard did **not** write the ACA private DNS A record (common), finish DNS by hand:

5. Search **Private DNS zones** → **Create**.
   - Resource group: `github-runners-fw-rg`
   - Name: `privatelink.westus.azurecontainerapps.io` (must match West US)
6. After create → **Virtual network links** → Add:
   - Link name: `dns-link-aca-fw`
   - VNet: `vnet-github-runners-fw`
   - Auto-registration: **No**
7. Open `pe-env-github-runners-fw` → copy the private IP (Custom DNS configs).
8. Open `env-github-runners-fw` → Overview → copy **Default domain** (looks like `whitedesert-xxxx.westus.azurecontainerapps.io`).
   DNS record set name is the **first label only** (the part before `.westus.azurecontainerapps.io`).
9. Private DNS zone → **Recordsets** → **+ Record set**:
   - Name: that first label (not `@`, not the full FQDN)
   - Type: **A**
   - IP: the private endpoint IP
   - TTL: 3600
10. Confirm environment **Public network access** = Disabled and PE connection **Approved**.

--------------------------------------------------------------------------------
12. Build and push the runner image (laptop — not the portal)
--------------------------------------------------------------------------------

ACR Tasks are blocked. Public ACR access must still be **All networks**. Docker Desktop must be running.

PowerShell on the laptop:

```
Set-Location "C:\Users\HP\Documents\github-runner"
$RUNNER_SRC = Join-Path (Get-Location) "container-apps-ci-cd-runner-tutorial"

# Download the official sample here on the first run. Keep the local runner
# version/label changes on later runs; the commands below refresh those values.
if (Test-Path $RUNNER_SRC) {
  Write-Host "Reusing existing runner source at $RUNNER_SRC"
}
else {
  git clone https://github.com/Azure-Samples/container-apps-ci-cd-runner-tutorial.git $RUNNER_SRC
}

$entrypoint = Join-Path $RUNNER_SRC "github-actions-runner\entrypoint.sh"
$text = [System.IO.File]::ReadAllText((Resolve-Path $entrypoint))
$text = $text -replace `
  '\./config\.sh --url \$GH_URL --token \$REGISTRATION_TOKEN --unattended --ephemeral && \./run\.sh', `
  './config.sh --url "$GH_URL" --token "$REGISTRATION_TOKEN" --labels "$RUNNER_LABELS" --unattended --ephemeral && ./run.sh'
[System.IO.File]::WriteAllText((Resolve-Path $entrypoint), ($text -replace "`r`n", "`n"))

$dockerfile = Join-Path $RUNNER_SRC "Dockerfile.github"
$RUNNER_VERSION = ((Invoke-RestMethod `
  -Uri "https://api.github.com/repos/actions/runner/releases/latest").tag_name).TrimStart("v")
$IMAGE_TAG = "$RUNNER_VERSION-1"
$FULL_IMAGE = "azdtghrunnerfwacr.azurecr.io/github-actions-runner:$IMAGE_TAG"

$dockerfileText = [System.IO.File]::ReadAllText((Resolve-Path $dockerfile))
$dockerfileText = $dockerfileText -replace `
  'FROM ghcr\.io/actions/actions-runner:[^\r\n]+', `
  "FROM ghcr.io/actions/actions-runner:$RUNNER_VERSION"
[System.IO.File]::WriteAllText((Resolve-Path $dockerfile), ($dockerfileText -replace "`r`n", "`n"))

az acr login --name azdtghrunnerfwacr
docker build `
  --pull `
  -f (Join-Path $RUNNER_SRC "Dockerfile.github") `
  -t $FULL_IMAGE `
  $RUNNER_SRC
docker push $FULL_IMAGE
Write-Host "Use this exact image in the job: $FULL_IMAGE"
```

This downloads the official sample into
`C:\Users\HP\Documents\github-runner\container-apps-ci-cd-runner-tutorial`.
`--pull` refreshes the Docker base image, and the Dockerfile downloads/installs
its required runner dependencies while building.

The resulting image is stored in Docker Desktop's local image store, not as a
normal file in this folder, and is then pushed to ACR. A separate `docker save`
is only needed if you want an offline image archive.

Use the exact image printed by the script (currently
`azdtghrunnerfwacr.azurecr.io/github-actions-runner:2.337.0-1`). Do not double
`.azurecr.io`. A new version-specific tag prevents old replicas from reusing a
stale image.

Portal check: `azdtghrunnerfwacr` → **Repositories** →
`github-actions-runner` → the `$IMAGE_TAG` printed in step 12.

--------------------------------------------------------------------------------
13. Keep ACR public access temporarily for job bootstrap
--------------------------------------------------------------------------------

The image now exists, but leave ACR → **Networking** → Public network access as
**All networks** through step 14a. This avoids initial control-plane image
validation failures. Step 14b switches the existing job to user-assigned
managed identity and then disables ACR public access.

--------------------------------------------------------------------------------
14. Create the GitHub runner job (once)
--------------------------------------------------------------------------------

The tested path for this environment is step 14a (CLI with a repository-scoped
ACR pull token). The following portal fields are included for reference, but do
not submit the portal form because its managed-identity image validation failed.

1. Search **Container Apps Jobs** (or open `env-github-runners-fw` → Jobs → Create).
2. **Basics**
   - Resource group: `github-runners-fw-rg`
   - Job name: `github-actions-runner-job-fw`
   - Region: **West US**
   - Container Apps environment: `env-github-runners-fw`
3. **Configuration / execution**
   - Replica timeout: `1800`
   - Replica retry limit: `0`
   - Replica completion count: `1`
   - Parallelism: `1`
   - Trigger type: **Event**
   - Min executions: `0`
   - Max executions: `10`
   - Polling interval: `30` seconds
4. **Scale rule**
   - Name: `github-runner`
   - Type: `github-runner`
   - Authentication: trigger parameter `personalAccessToken` → secret `personal-access-token`
   - Metadata:

| Key | Value |
| --- | --- |
| githubApiURL | https://api.github.com |
| owner | azdevopstraining |
| runnerScope | repo |
| repos | githubrunner-manual-poc |
| labels | ci |
| noDefaultLabels | true |
| targetWorkflowQueueLength | 1 |

5. **Secrets**
   - Name: `personal-access-token`
   - Value: your GitHub PAT
6. **Identity** (job-level) — configure this before selecting the private image:
   - Under **User assigned**, add `id-github-runner-fw`.
   - Do not use **System assigned** or **system-environment** for ACR.
7. **Container**
   - Name: `github-actions-runner-job-fw` (or leave default)
   - Image: paste `$FULL_IMAGE` printed by step 12
   - CPU: `2.0`
   - Memory: `4Gi`
   - Environment variables:
     - `GITHUB_PAT` = secret reference `personal-access-token`
     - `RUNNER_LABELS` = `ci`
     - `GH_URL` = `https://github.com/azdevopstraining/githubrunner-manual-poc`
     - `REGISTRATION_TOKEN_API_URL` = `https://api.github.com/repos/azdevopstraining/githubrunner-manual-poc/actions/runners/registration-token`
8. **Registry**
   - Server: `azdtghrunnerfwacr.azurecr.io`
   - Authentication: **Managed identity**
   - Identity: **User assigned** → `id-github-runner-fw`
9. Do not finish portal creation in this environment. The portal's managed
   identity image validation failed despite correct RBAC and private DNS.
   Continue with the tested command-line path in step 14a.

Initial image validation failed while creating the job directly with managed
identity. Use the repository-scoped token below only to bootstrap job creation,
then switch the existing job to user-assigned managed identity in step 14b.
This avoids storing registry credentials in the final job configuration.

### 14a. Command-line creation with repository-scoped ACR pull token

Run this in PowerShell. The PAT is requested as a secure value and is not
written literally into the command history.

```powershell
# One-time, least-privilege ACR token resources. These commands safely reuse
# the resources if they were already created during troubleshooting.
$SCOPE_MAP = az acr scope-map show `
  --registry azdtghrunnerfwacr `
  --name github-runner-pull-scope `
  --query name -o tsv 2>$null

if ([string]::IsNullOrWhiteSpace($SCOPE_MAP)) {
  az acr scope-map create `
    --resource-group github-runners-fw-rg `
    --registry azdtghrunnerfwacr `
    --name github-runner-pull-scope `
    --repository github-actions-runner content/read metadata/read `
    --output none
}

$ACR_TOKEN = az acr token show `
  --registry azdtghrunnerfwacr `
  --name github-runner-pull-token `
  --query name -o tsv 2>$null

if ([string]::IsNullOrWhiteSpace($ACR_TOKEN)) {
  az acr token create `
    --resource-group github-runners-fw-rg `
    --registry azdtghrunnerfwacr `
    --name github-runner-pull-token `
    --scope-map github-runner-pull-scope `
    --output none
}

$REGISTRY_USERNAME = "github-runner-pull-token"
$REGISTRY_PASSWORD = az acr token credential generate `
  --resource-group github-runners-fw-rg `
  --registry azdtghrunnerfwacr `
  --name $REGISTRY_USERNAME `
  --password1 `
  --expiration-in-days 90 `
  --query "passwords[0].value" -o tsv 2>$null

if ([string]::IsNullOrWhiteSpace($REGISTRY_PASSWORD)) {
  throw "ACR repository pull-token password generation failed."
}

# Run this line exactly as written. Do NOT replace "Enter GitHub PAT" with the
# token. When the separate hidden prompt appears, paste the PAT there and press
# Enter. PowerShell intentionally displays no characters while you type/paste.
$securePat = Read-Host -Prompt "Enter GitHub PAT" -AsSecureString
$GITHUB_PAT = [Net.NetworkCredential]::new("", $securePat).Password

if ([string]::IsNullOrWhiteSpace($GITHUB_PAT)) {
  throw "GitHub PAT is empty. Run the secure prompt again and enter the token."
}

if ([string]::IsNullOrWhiteSpace($FULL_IMAGE)) {
  $RUNNER_VERSION = ((Invoke-RestMethod `
    -Uri "https://api.github.com/repos/actions/runner/releases/latest").tag_name).TrimStart("v")
  $FULL_IMAGE = "azdtghrunnerfwacr.azurecr.io/github-actions-runner:$RUNNER_VERSION-1"
}

$IDENTITY_ID = az identity show `
  --resource-group github-runners-fw-rg `
  --name id-github-runner-fw `
  --query id -o tsv

if ([string]::IsNullOrWhiteSpace($IDENTITY_ID)) {
  throw "Managed identity id-github-runner-fw was not found."
}

az containerapp job create `
  --name github-actions-runner-job-fw `
  --resource-group github-runners-fw-rg `
  --environment env-github-runners-fw `
  --trigger-type Event `
  --replica-timeout 1800 `
  --replica-retry-limit 0 `
  --replica-completion-count 1 `
  --parallelism 1 `
  --image $FULL_IMAGE `
  --min-executions 0 `
  --max-executions 10 `
  --polling-interval 30 `
  --scale-rule-name github-runner `
  --scale-rule-type github-runner `
  --scale-rule-metadata "githubApiURL=https://api.github.com" "owner=azdevopstraining" "runnerScope=repo" "repos=githubrunner-manual-poc" "labels=ci" "noDefaultLabels=true" "targetWorkflowQueueLength=1" `
  --scale-rule-auth "personalAccessToken=personal-access-token" `
  --cpu 2.0 `
  --memory 4Gi `
  --secrets "personal-access-token=$GITHUB_PAT" `
  --env-vars "GITHUB_PAT=secretref:personal-access-token" "RUNNER_LABELS=ci" "GH_URL=https://github.com/azdevopstraining/githubrunner-manual-poc" "REGISTRATION_TOKEN_API_URL=https://api.github.com/repos/azdevopstraining/githubrunner-manual-poc/actions/runners/registration-token" `
  --registry-server azdtghrunnerfwacr.azurecr.io `
  --registry-username $REGISTRY_USERNAME `
  --registry-password $REGISTRY_PASSWORD `
  --mi-user-assigned $IDENTITY_ID

$JOB_CREATE_EXIT = $LASTEXITCODE
Remove-Variable GITHUB_PAT, securePat, REGISTRY_PASSWORD
if ($JOB_CREATE_EXIT -ne 0) {
  throw "Container Apps job creation failed with exit code $JOB_CREATE_EXIT."
}
```

`id-github-runner-fw` remains assigned to the job for runtime Azure access.
The ACR token is a bootstrap credential only; do not stop here.

### 14b. Switch image pull to managed identity and keep all public access disabled

Run this in the same PowerShell window immediately after step 14a:

```powershell
$IDENTITY_ID = az identity show `
  --resource-group github-runners-fw-rg `
  --name id-github-runner-fw `
  --query id -o tsv

$IDENTITY_PRINCIPAL_ID = az identity show `
  --resource-group github-runners-fw-rg `
  --name id-github-runner-fw `
  --query principalId -o tsv

$ACR_ID = az acr show `
  --resource-group github-runners-fw-rg `
  --name azdtghrunnerfwacr `
  --query id -o tsv

# Verify AcrPull. Create it only if it is missing.
$ACR_PULL = az role assignment list `
  --assignee-object-id $IDENTITY_PRINCIPAL_ID `
  --scope $ACR_ID `
  --query "[?roleDefinitionName=='AcrPull'].roleDefinitionName | [0]" `
  -o tsv

if ($ACR_PULL -ne "AcrPull") {
  az role assignment create `
    --assignee-object-id $IDENTITY_PRINCIPAL_ID `
    --assignee-principal-type ServicePrincipal `
    --role AcrPull `
    --scope $ACR_ID `
    --output none
}

# Managed-identity pulls require ACR to accept ARM-audience tokens.
az acr config authentication-as-arm update `
  --registry azdtghrunnerfwacr `
  --status enabled

# Replace the bootstrap username/password registry entry with the UAMI.
$BOOTSTRAP_REGISTRY_SECRET = az containerapp job registry list `
  --resource-group github-runners-fw-rg `
  --name github-actions-runner-job-fw `
  --query "[?server=='azdtghrunnerfwacr.azurecr.io'].passwordSecretRef | [0]" `
  -o tsv

az containerapp job registry set `
  --resource-group github-runners-fw-rg `
  --name github-actions-runner-job-fw `
  --server azdtghrunnerfwacr.azurecr.io `
  --identity $IDENTITY_ID

if ($LASTEXITCODE -ne 0) {
  throw "Could not switch the job registry to id-github-runner-fw."
}

# Disable inbound public access to the Container Apps environment.
az containerapp env update `
  --resource-group github-runners-fw-rg `
  --name env-github-runners-fw `
  --public-network-access Disabled

# Disable ACR public access. Image pulls now use its private endpoint and DNS.
az acr update `
  --resource-group github-runners-fw-rg `
  --name azdtghrunnerfwacr `
  --public-network-enabled false

# Final verification.
az containerapp env show `
  --resource-group github-runners-fw-rg `
  --name env-github-runners-fw `
  --query properties.publicNetworkAccess -o tsv

az acr show `
  --resource-group github-runners-fw-rg `
  --name azdtghrunnerfwacr `
  --query "{publicNetworkAccess:publicNetworkAccess,defaultAction:networkRuleSet.defaultAction}" `
  --output json

az containerapp job registry list `
  --resource-group github-runners-fw-rg `
  --name github-actions-runner-job-fw `
  --output json

az network private-dns record-set a list `
  --resource-group github-runners-fw-rg `
  --zone-name privatelink.azurecr.io `
  --query "[].{name:name,ips:aRecords[].ipv4Address}" `
  --output json
```

Expected results:
- Container Apps environment public network access: `Disabled`
- ACR `publicNetworkAccess`: `Disabled`
- Job registry `identity`: full resource ID ending in
  `/userAssignedIdentities/id-github-runner-fw`
- Private DNS records for `azdtghrunnerfwacr` and
  `azdtghrunnerfwacr.westus.data`, both resolving to `10.30.0.x`

Keep the ACR token resources temporarily as rollback until one workflow
successfully pulls the image through managed identity. They are no longer
referenced by the job after `job registry set` succeeds.

--------------------------------------------------------------------------------
15. Verify a workflow run
--------------------------------------------------------------------------------

Workflow `runs-on` must be:

```
runs-on: [ci]
```

1. GitHub repo → Actions → push to main or **Re-run jobs**. Wait about 30 seconds.
2. Portal → `github-actions-runner-job-fw` → **Execution history**. A new execution should appear.
3. Open the execution → **Logs** for container `github-actions-runner-job-fw`.
4. GitHub → Settings → Actions → Runners: an ephemeral runner with label `ci` appears while the job runs, then disappears.

After GitHub confirms that a workflow successfully started with managed
identity, remove the unused bootstrap registry credential:

```powershell
$MANAGED_IDENTITY_PULL_CONFIRMED = Read-Host `
  "Did a workflow successfully start after step 14b? Type YES to delete bootstrap ACR credentials"

if ($MANAGED_IDENTITY_PULL_CONFIRMED -ceq "YES") {
  if (-not [string]::IsNullOrWhiteSpace($BOOTSTRAP_REGISTRY_SECRET)) {
    az containerapp job secret remove `
      --resource-group github-runners-fw-rg `
      --name github-actions-runner-job-fw `
      --secret-names $BOOTSTRAP_REGISTRY_SECRET `
      --yes
  }

  az acr token delete `
    --resource-group github-runners-fw-rg `
    --registry azdtghrunnerfwacr `
    --name github-runner-pull-token `
    --yes

  az acr scope-map delete `
    --resource-group github-runners-fw-rg `
    --registry azdtghrunnerfwacr `
    --name github-runner-pull-scope `
    --yes
}
```

Use these exact checks if the workflow is still queued:

```powershell
# Confirm the deployed image, normal scale-to-zero value, and scaler metadata.
az containerapp job show `
  --resource-group github-runners-fw-rg `
  --name github-actions-runner-job-fw `
  --query "{image:properties.template.containers[0].image,min:properties.configuration.eventTriggerConfig.scale.minExecutions,max:properties.configuration.eventTriggerConfig.scale.maxExecutions,rules:properties.configuration.eventTriggerConfig.scale.rules}" `
  --output json

az containerapp job execution list `
  --resource-group github-runners-fw-rg `
  --name github-actions-runner-job-fw `
  --output table

$LATEST_EXECUTION = az containerapp job execution list `
  --resource-group github-runners-fw-rg `
  --name github-actions-runner-job-fw `
  --query "[0].name" -o tsv

if (-not [string]::IsNullOrWhiteSpace($LATEST_EXECUTION)) {
  az containerapp job logs show `
    --resource-group github-runners-fw-rg `
    --name github-actions-runner-job-fw `
    --execution $LATEST_EXECUTION `
    --container github-actions-runner-job-fw `
    --tail 100
}
```

If there is no execution, temporarily force one runner. This separates a KEDA
polling problem from runner startup/network problems. Restore `0` immediately
after collecting logs:

```powershell
az containerapp job update `
  --resource-group github-runners-fw-rg `
  --name github-actions-runner-job-fw `
  --min-executions 1

Start-Sleep -Seconds 60

az containerapp job execution list `
  --resource-group github-runners-fw-rg `
  --name github-actions-runner-job-fw `
  --output table

az containerapp job update `
  --resource-group github-runners-fw-rg `
  --name github-actions-runner-job-fw `
  --min-executions 0
```

If the workflow remains queued and Container Apps shows no execution, replace
the job PAT. This commonly happens after revoking an exposed token or when a
fine-grained PAT is still scoped to a different repository:

```powershell
$securePat = Read-Host -Prompt "Enter replacement GitHub PAT" -AsSecureString
$GITHUB_PAT = [Net.NetworkCredential]::new("", $securePat).Password

if ([string]::IsNullOrWhiteSpace($GITHUB_PAT)) {
  throw "GitHub PAT is empty."
}

# Validate the same PAT against the exact registration API used by the runner.
$headers = @{
  Accept = "application/vnd.github+json"
  Authorization = "Bearer $GITHUB_PAT"
  "X-GitHub-Api-Version" = "2022-11-28"
}
$validation = Invoke-RestMethod -Method Post -Headers $headers `
  -Uri "https://api.github.com/repos/azdevopstraining/githubrunner-manual-poc/actions/runners/registration-token"

if ([string]::IsNullOrWhiteSpace($validation.token)) {
  throw "PAT validation failed: GitHub returned no registration token."
}
Write-Host "PAT validated successfully. Registration token expires at $($validation.expires_at)."
Remove-Variable validation

# Only run this after PAT validation succeeds.
az containerapp job secret set `
  --name github-actions-runner-job-fw `
  --resource-group github-runners-fw-rg `
  --secrets "personal-access-token=$GITHUB_PAT"

Remove-Variable GITHUB_PAT, securePat
```

KEDA polls every 30 seconds. A workflow already queued for `[ci]` should create
an execution shortly after the secret is replaced. Keep `minExecutions` at `0`;
setting it to `1` is only a diagnostic override.

If it hangs on register/poll: firewall denied a GitHub FQDN. Open `afw-github-runners-fw` → Logs / Log Analytics `AZFWApplicationRule` and add the denied FQDN to collection `github-runner`.
If logs show `Deny. No rule matched` although the rule exists, verify the policy is attached to the firewall and both tiers are Standard.
If GitHub says the runner version is out of date, rebuild step 12 from the current official `actions-runner` image.
If a runner listens but the job remains queued, verify its registration logs contain `Arg 'labels': 'ci'`. The `RUNNER_LABELS` environment variable does nothing unless `entrypoint.sh` passes `--labels "$RUNNER_LABELS"` to `config.sh`.
If the runner shows `curl: (35) ... SSL_ERROR_SYSCALL`, this is normally an
Azure Firewall deny—not an invalid PAT. Query the firewall log for
`api.github.com`; the decision must be `Allow` and show rule `github-actions`.
If `Install CI tools` exits with code `35`, confirm `releases.astral.sh` and
`releases.hashicorp.com` are allowed by step 8b.
If image pull failed: `privatelink.azurecr.io` DNS is broken. Do not open public `*.azurecr.io` unless you intend public ACR.
npm / NuGet / Maven / your APIs are not in the firewall rules. Add FQDNs as jobs fail.

--------------------------------------------------------------------------------
16. Later: refresh PAT, image, or scale rule
--------------------------------------------------------------------------------

PAT: job → **Secrets** → update `personal-access-token`.

Image (laptop, ACR public must be on for a laptop push):
1. ACR → Networking → Public network access **All networks** → Save.
2. Repeat step 12 so a new version-specific image tag is built and pushed.
3. ACR → Networking → Public network access **Disabled** → Save.
4. Job → Containers → paste the new `$FULL_IMAGE` printed by step 12 → Save.
5. Stop any executions that were already running during the image update;
   updating the job does not replace them:

```powershell
$RUNNING_EXECUTIONS = az containerapp job execution list `
  --resource-group github-runners-fw-rg `
  --name github-actions-runner-job-fw `
  --query "[?properties.status=='Running'].name" -o tsv

foreach ($EXECUTION in $RUNNING_EXECUTIONS) {
  az containerapp job stop `
    --resource-group github-runners-fw-rg `
    --name github-actions-runner-job-fw `
    --job-execution-name $EXECUTION `
    --output none
}

az containerapp job update `
  --resource-group github-runners-fw-rg `
  --name github-actions-runner-job-fw `
  --min-executions 0
```

Env / scale: job → Containers / Scale — keep `RUNNER_LABELS=ci` and scale metadata `labels=ci`, `noDefaultLabels=true`.

--------------------------------------------------------------------------------
Appendix A. Firewall diagnostics
--------------------------------------------------------------------------------

1. Open `afw-github-runners-fw` → **Diagnostic settings** → **Add diagnostic setting**.
2. Name: `afw-to-law`
3. Categories: AZFWApplicationRule, AZFWNetworkRule, AZFWThreatIntel
4. Destination: Log Analytics workspace created with the Container Apps environment.
5. Save before testing the workflow. Allow several minutes for initial ingestion.
6. Open that Log Analytics workspace → **Logs** and run:

```kusto
AzureDiagnostics
| where TimeGenerated > ago(30m)
| where msg_s contains "api.github.com"
    or msg_s contains "releases.astral.sh"
    or msg_s contains "releases.hashicorp.com"
| project TimeGenerated, msg_s
| order by TimeGenerated desc
```

Successful GitHub rows show `Action: Allow`, policy
`afwp-standard-github-runners-fw`, collection `github-runner`, and rule
`github-actions` or `ci-tool-downloads`. `Action: Deny. No rule matched`
identifies either an unattached policy or a missing destination rule.

--------------------------------------------------------------------------------
Appendix B. Portal create shortcuts
--------------------------------------------------------------------------------

| Resource | Portal search |
| --- | --- |
| Resource group | Resource groups |
| VNet | Virtual networks |
| ACR | Container registries |
| Identity | Managed Identities |
| Private endpoint | Private endpoints |
| Private DNS | Private DNS zones |
| Public IP | Public IP addresses |
| Firewall policy | Firewall policies |
| Firewall | Firewalls |
| Route table | Route tables |
| Environment | Container Apps Environments |
| Job | Container Apps Jobs |
