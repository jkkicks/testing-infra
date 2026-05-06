#!/usr/bin/env bash
# Load `.env` from repo root and map Proxmox vars into what bpg/proxmox expects.
# SSH is required for uploading cloud-init snippets to Proxmox when using an API token,
# unless your setup uploads snippets another way.
#
# Usage (from repo root):
#   export PROXMOX_VE_SSH_PRIVATE_KEY="$(cat ~/.ssh/id_ed25519)"
#   ./scripts/with-proxmox-env.sh terraform -chdir=environments/pve1-testing1/terraform plan

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}. Copy .env.example and populate." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

normalize_endpoint() {
  local url="${PVE1_URL:?Set PVE1_URL in .env}"
  url="${url%/}"
  echo "${url}/"
}

export PROXMOX_VE_ENDPOINT="$(normalize_endpoint)"
export PROXMOX_VE_API_TOKEN="${PVE1_TOKEN_ID:?Set PVE1_TOKEN_ID in .env}=${PVE1_SECRET:?Set PVE1_SECRET in .env}"
export PROXMOX_VE_INSECURE="${PROXMOX_VE_INSECURE:-true}"
export PROXMOX_VE_SSH_USERNAME="${PROXMOX_VE_SSH_USERNAME:-root}"

if [[ -z "${PROXMOX_VE_SSH_PRIVATE_KEY:-}" && -n "${PVE1_SSH_PRIVATE_KEY_FILE:-}" ]]; then
  _key="${PVE1_SSH_PRIVATE_KEY_FILE/#\~/$HOME}"
  if [[ ! -r "${_key}" ]]; then
    echo "Cannot read PVE1_SSH_PRIVATE_KEY_FILE (${_key})." >&2
    exit 1
  fi
  export PROXMOX_VE_SSH_PRIVATE_KEY="$(cat "${_key}")"
fi

exec "$@"
