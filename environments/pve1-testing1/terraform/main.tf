locals {
  ssh_public_key = trimspace(file(coalesce(var.ssh_public_key_file, "${path.module}/../../../id_ed25519.pub")))
  kube_public_ip = split("/", var.ipv4_address_cidr)[0]
}

resource "proxmox_virtual_environment_file" "meta_data" {
  content_type = "snippets"
  datastore_id = var.snippets_datastore_id
  node_name    = var.node_name

  source_raw {
    file_name = "pve1-testing1-${var.vm_id}-meta.yaml"
    data      = <<-EOF
#cloud-config
local-hostname: ${var.vm_hostname}
EOF
  }
}

resource "proxmox_virtual_environment_file" "user_data" {
  content_type = "snippets"
  datastore_id = var.snippets_datastore_id
  node_name    = var.node_name

  source_raw {
    file_name = "pve1-testing1-${var.vm_id}-user.yaml"
    data = templatefile("${path.module}/../bootstrap/cloud-init/user-data.yaml.tftpl", {
      hostname       = var.vm_hostname
      ssh_public_key = local.ssh_public_key
      kube_public_ip = local.kube_public_ip
      k3s_version    = var.k3s_version
    })
  }
}

resource "proxmox_virtual_environment_vm" "k3s" {
  name      = var.vm_name
  vm_id     = var.vm_id
  node_name = var.node_name

  stop_on_destroy = true

  clone {
    vm_id = var.template_vm_id
  }

  agent {
    enabled = true
  }

  cpu {
    cores = var.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.memory_mb
  }

  network_device {
    bridge = var.network_bridge
  }

  disk {
    datastore_id = var.disk_storage_id
    interface    = var.disk_interface
    size         = var.disk_size_gb
    discard      = "on"
    iothread     = true
  }

  initialization {
    datastore_id = var.disk_storage_id

    dns {
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = var.ipv4_address_cidr
        gateway = var.ipv4_gateway
      }
    }

    meta_data_file_id = proxmox_virtual_environment_file.meta_data.id
    user_data_file_id = proxmox_virtual_environment_file.user_data.id
  }

  started = true
}
