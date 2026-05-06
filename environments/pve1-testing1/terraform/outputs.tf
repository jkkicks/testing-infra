output "vm_id" {
  description = "Proxmox VM ID."
  value       = proxmox_virtual_environment_vm.k3s.vm_id
}

output "guest_ipv4" {
  description = "Configured static IPv4 (management/Kubernetes API)."
  value       = local.kube_public_ip
}

output "ssh_command" {
  description = "SSH to ubuntu user once cloud-init finishes."
  value       = "ssh ubuntu@${local.kube_public_ip}"
}

output "kubectl_hint" {
  description = "Copy kubeconfig from the guest after k3s has installed."
  value       = "scp ubuntu@${local.kube_public_ip}:/home/ubuntu/.kube/config ./kubeconfig.pve1-testing1 && kubectl --kubeconfig kubeconfig.pve1-testing1 get nodes"
}
