variable "node_name" {
  description = "Proxmox node where the VM is placed."
  type        = string
  default     = "pve1"
}

variable "proxmox_ssh_host" {
  description = <<-EOT
    Optional IPv4 or hostname used for SSH to this node when uploading snippets (same machine as API URL if unsure).
    Leave empty to let the provider resolve node_name via API/DNS.
  EOT
  type        = string
  default     = ""
}

variable "template_vm_id" {
  description = "VM ID of the Ubuntu 24.04 cloud-init template to clone."
  type        = number
}

variable "vm_id" {
  description = "Numeric VM ID for this environment's guest."
  type        = number
  default     = 701
}

variable "vm_name" {
  description = "Guest display name in Proxmox."
  type        = string
  default     = "pve1-testing1-k3s"
}

variable "vm_hostname" {
  description = "Guest hostname applied via cloud-init."
  type        = string
  default     = "pve1-testing1-k3s"
}

variable "network_bridge" {
  description = "Host bridge attached to the guest NIC."
  type        = string
  default     = "vmbr0"
}

variable "ipv4_address_cidr" {
  description = "Static IPv4 address with prefix length."
  type        = string
  default     = "10.0.0.205/24"
}

variable "ipv4_gateway" {
  type    = string
  default = "10.0.0.1"
}

variable "dns_servers" {
  type        = list(string)
  description = "DNS servers passed to Proxmox cloud-init (Quad9 + Google)."
  default = [
    "9.9.9.9",
    "149.112.112.112",
    "8.8.8.8",
    "8.8.4.4",
  ]
}

variable "disk_storage_id" {
  description = "Proxmox storage ID for guest disks (thin pool)."
  type        = string
  default     = "nvme-thin"
}

variable "disk_interface" {
  description = <<-EOT
    Proxmox disk slot for the OS disk (`disk` block). Must match your template’s boot disk or Terraform adds a second unused disk.
    Ubuntu cloud templates on Proxmox often use VirtIO SCSI with the OS on scsi0 (guest: /dev/sda). virtio-only templates use virtio0 (/dev/vda).
  EOT
  type        = string
  default     = "scsi0"
}

variable "disk_size_gb" {
  description = "Boot/system disk size after clone."
  type        = number
  default     = 60
}

variable "snippets_datastore_id" {
  description = <<-EOT
    Proxmox storage ID where cloud-init snippets are uploaded (must have "Snippets"
    enabled under Datacenter → Storage). The API token's role needs Datastore privileges
    on this storage (at minimum Datastore.AllocateSpace and Datastore.Audit), or uploads fail with HTTP 403.
  EOT
  type        = string
  default     = "local"
}

variable "cpu_cores" {
  description = "vCPU count (t3a.medium = 2)."
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "Dedicated RAM in MiB (t3a.medium = 4096)."
  type        = number
  default     = 4096
}

variable "k3s_version" {
  description = "Pinned k3s release (git tag without leading v), e.g. v1.30.4+k3s1 → pass value matching INSTALL_K3S_VERSION env format."
  type        = string
  default     = "v1.30.5+k3s1"
}

variable "ssh_public_key_file" {
  description = "Path to SSH public key for the ubuntu user (repo-root default)."
  type        = string
  default     = null
}
