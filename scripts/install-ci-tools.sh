#!/usr/bin/env bash
# Install Python (uv), Terraform CLI, the azurerm provider, and optionally Azure CLI.
# Terraform zip assets are no longer attached to GitHub Releases (404).
# Official binaries come from releases.hashicorp.com. uv still comes from GitHub.
# azure/login needs the az binary on PATH; this runner image does not ship it.
set -euo pipefail

bin_dir="${HOME}/.local/bin"
mkdir -p "${bin_dir}"
export PATH="${bin_dir}:${PATH}"
if [ -n "${GITHUB_PATH:-}" ]; then
  echo "${bin_dir}" >> "${GITHUB_PATH}"
fi

TERRAFORM_VERSION="${TERRAFORM_VERSION:-1.10.5}"
AZURERM_PROVIDER_VERSION="${AZURERM_PROVIDER_VERSION:-4.37.0}"
INSTALL_AZURE_CLI="${INSTALL_AZURE_CLI:-false}"
export UV_TOOL_BIN_DIR="${bin_dir}"

if ! command -v uv >/dev/null 2>&1; then
  curl -fsSL "https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-unknown-linux-gnu.tar.gz" \
    -o /tmp/uv.tar.gz
  tar -xzf /tmp/uv.tar.gz -C /tmp
  uv_src="$(find /tmp -type f -name uv | head -n 1)"
  install -m 0755 "${uv_src}" "${bin_dir}/uv"
fi

uv python install 3.12
py="$(uv python find 3.12)"
ln -sf "${py}" "${bin_dir}/python3"
ln -sf "${py}" "${bin_dir}/python"
python3 --version

extract_zip() {
  python3 - "$1" "$2" <<'PY'
import sys, zipfile
from pathlib import Path
dest = Path(sys.argv[2])
dest.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(sys.argv[1]) as zf:
    zf.extractall(dest)
PY
}

download() {
  local url="$1"
  local dest="$2"
  echo "Downloading ${url}"
  curl -fL --retry 3 --retry-delay 2 -o "${dest}" "${url}"
}

if ! command -v terraform >/dev/null 2>&1 || ! terraform version | grep -q "Terraform v${TERRAFORM_VERSION}"; then
  download \
    "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    /tmp/terraform.zip
  rm -rf /tmp/terraform-cli
  extract_zip /tmp/terraform.zip /tmp/terraform-cli
  install -m 0755 /tmp/terraform-cli/terraform "${bin_dir}/terraform"
fi
terraform version

mirror_dir="${HOME}/.terraform.d/plugins/registry.terraform.io/hashicorp/azurerm/${AZURERM_PROVIDER_VERSION}/linux_amd64"
provider_bin="${mirror_dir}/terraform-provider-azurerm_v${AZURERM_PROVIDER_VERSION}"
if [ ! -x "${provider_bin}" ]; then
  mkdir -p "${mirror_dir}"
  download \
    "https://releases.hashicorp.com/terraform-provider-azurerm/${AZURERM_PROVIDER_VERSION}/terraform-provider-azurerm_${AZURERM_PROVIDER_VERSION}_linux_amd64.zip" \
    /tmp/azurerm.zip
  rm -rf /tmp/azurerm-provider
  extract_zip /tmp/azurerm.zip /tmp/azurerm-provider
  src="$(find /tmp/azurerm-provider -type f -name 'terraform-provider-azurerm*' | head -n 1)"
  install -m 0755 "${src}" "${provider_bin}"
fi

tf_rc="${HOME}/.terraformrc.ci"
cat > "${tf_rc}" <<EOF
provider_installation {
  filesystem_mirror {
    path    = "${HOME}/.terraform.d/plugins"
    include = ["registry.terraform.io/*/*"]
  }
  direct {
    exclude = ["registry.terraform.io/*/*"]
  }
}
EOF

export TF_CLI_CONFIG_FILE="${tf_rc}"
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "TF_CLI_CONFIG_FILE=${tf_rc}" >> "${GITHUB_ENV}"
fi

if [ "${INSTALL_AZURE_CLI}" = "true" ]; then
  if ! command -v az >/dev/null 2>&1; then
    echo "Installing Azure CLI via uv (no Docker / no apt)"
    uv tool install azure-cli
  fi
  az version
fi
