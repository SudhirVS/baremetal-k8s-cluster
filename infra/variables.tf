variable "control_plane_ip" {
  description = "Static IP for control plane node"
  type        = string
  default     = "192.168.122.10"
}

variable "worker_count" {
  description = "Number of worker nodes to provision"
  type        = number
  default     = 2
}

variable "worker_subnet" {
  description = "Subnet CIDR for worker node IPs"
  type        = string
  default     = "192.168.122.0/24"
}

variable "ssh_pubkey" {
  description = "SSH public key for node access"
  type        = string
}
