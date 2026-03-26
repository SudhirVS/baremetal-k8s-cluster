terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# Base OS image (Ubuntu 22.04 cloud image)
resource "libvirt_volume" "base_image" {
  name   = "ubuntu-22.04-base.qcow2"
  pool   = "default"
  source = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  format = "qcow2"
}

module "control_plane" {
  source     = "./modules/node"
  name       = "k8s-control-plane"
  vcpu       = 2
  memory_mb  = 2048
  disk_gb    = 20
  base_image = libvirt_volume.base_image.id
  ip_address = var.control_plane_ip
  role       = "control-plane"
  ssh_pubkey = var.ssh_pubkey
}

module "worker_nodes" {
  source     = "./modules/node"
  count      = var.worker_count
  name       = "k8s-worker-${count.index + 1}"
  vcpu       = 2
  memory_mb  = 2048
  disk_gb    = 20
  base_image = libvirt_volume.base_image.id
  ip_address = cidrhost(var.worker_subnet, count.index + 10)
  role       = "worker"
  ssh_pubkey = var.ssh_pubkey
}
