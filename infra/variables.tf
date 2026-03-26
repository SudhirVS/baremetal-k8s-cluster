variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "ami_id" {
  description = "Ubuntu 22.04 LTS AMI ID (region-specific)"
  type        = string
  # us-east-1 Ubuntu 22.04 official AMI — update if using a different region
  default     = "ami-0c7217cdde317cfec"
}

variable "control_plane_instance_type" {
  description = "EC2 instance type for control plane"
  type        = string
  default     = "t3.medium"   # 2 vCPU, 4 GB RAM
}

variable "worker_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.medium"   # 2 vCPU, 4 GB RAM
}

variable "worker_count" {
  description = "Number of worker nodes to provision"
  type        = number
  default     = 2
}

variable "ssh_pubkey" {
  description = "SSH public key content for EC2 key pair"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "Your public IP in CIDR notation for SSH/API access (e.g. 1.2.3.4/32)"
  type        = string
}
