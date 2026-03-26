variable "name"       { type = string }
variable "vcpu"       { type = number }
variable "memory_mb"  { type = number }
variable "disk_gb"    { type = number }
variable "base_image" { type = string }
variable "ip_address" { type = string }
variable "role"       { type = string }
variable "ssh_pubkey" { type = string }

# Per-node disk cloned from base image
resource "libvirt_volume" "disk" {
  name           = "${var.name}.qcow2"
  pool           = "default"
  base_volume_id = var.base_image
  size           = var.disk_gb * 1073741824
  format         = "qcow2"
}

# cloud-init user-data
resource "libvirt_cloudinit_disk" "init" {
  name = "${var.name}-init.iso"
  pool = "default"

  user_data = <<-EOF
    #cloud-config
    hostname: ${var.name}
    users:
      - name: ubuntu
        sudo: ALL=(ALL) NOPASSWD:ALL
        ssh_authorized_keys:
          - ${var.ssh_pubkey}
    packages:
      - curl
      - apt-transport-https
    runcmd:
      - swapoff -a
      - sed -i '/swap/d' /etc/fstab
      - modprobe overlay
      - modprobe br_netfilter
      - |
        cat > /etc/sysctl.d/k8s.conf <<SYSCTL
        net.bridge.bridge-nf-call-iptables  = 1
        net.bridge.bridge-nf-call-ip6tables = 1
        net.ipv4.ip_forward                 = 1
        SYSCTL
      - sysctl --system
      - curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      - echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable" > /etc/apt/sources.list.d/docker.list
      - apt-get update -y
      - apt-get install -y containerd.io
      - mkdir -p /etc/containerd
      - containerd config default > /etc/containerd/config.toml
      - sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
      - systemctl restart containerd && systemctl enable containerd
      - curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
      - echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
      - apt-get update -y
      - apt-get install -y kubelet kubeadm kubectl
      - apt-mark hold kubelet kubeadm kubectl
  EOF

  network_config = <<-EOF
    version: 2
    ethernets:
      ens3:
        addresses: [${var.ip_address}/24]
        gateway4: 192.168.122.1
        nameservers:
          addresses: [8.8.8.8]
  EOF
}

resource "libvirt_domain" "node" {
  name   = var.name
  vcpu   = var.vcpu
  memory = var.memory_mb

  disk {
    volume_id = libvirt_volume.disk.id
  }

  cloudinit = libvirt_cloudinit_disk.init.id

  network_interface {
    network_name   = "default"
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }
}

output "ip_address" {
  value = var.ip_address
}
