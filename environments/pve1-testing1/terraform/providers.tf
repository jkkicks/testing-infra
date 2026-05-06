provider "proxmox" {
  # Credentials via env (PROXMOX_VE_ENDPOINT, PROXMOX_VE_API_TOKEN, PROXMOX_VE_INSECURE).
  # Snippet uploads with API tokens typically require SSH; use PROXMOX_VE_SSH_USERNAME / PROXMOX_VE_SSH_PRIVATE_KEY.
  ssh {
    dynamic "node" {
      for_each = var.proxmox_ssh_host != "" ? [1] : []
      content {
        name    = var.node_name
        address = var.proxmox_ssh_host
      }
    }
  }
}
