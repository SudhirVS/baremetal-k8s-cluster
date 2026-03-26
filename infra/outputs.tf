output "control_plane_public_ip" {
  description = "Public IP of the control plane — use for SSH and kubeconfig"
  value       = module.control_plane.public_ip
}

output "control_plane_private_ip" {
  description = "Private IP of the control plane — used by kubeadm internally"
  value       = module.control_plane.private_ip
}

output "worker_public_ips" {
  description = "Public IPs of worker nodes"
  value       = [for w in module.worker_nodes : w.public_ip]
}

output "worker_private_ips" {
  description = "Private IPs of worker nodes"
  value       = [for w in module.worker_nodes : w.private_ip]
}
