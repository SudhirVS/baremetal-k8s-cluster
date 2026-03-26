output "control_plane_ip" {
  value = module.control_plane.ip_address
}

output "worker_ips" {
  value = [for w in module.worker_nodes : w.ip_address]
}
