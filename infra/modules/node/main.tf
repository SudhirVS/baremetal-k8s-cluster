variable "name"              { type = string }
variable "instance_type"     { type = string }
variable "ami_id"            { type = string }
variable "subnet_id"         { type = string }
variable "security_group_id" { type = string }
variable "key_name"          { type = string }
variable "role"              { type = string }
variable "disk_gb"           { type = number }

resource "aws_instance" "node" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = var.key_name

  root_block_device {
    volume_size = var.disk_gb
    volume_type = "gp3"
  }

  # Install containerd + kubeadm on first boot
  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail
    hostnamectl set-hostname ${var.name}

    swapoff -a
    sed -i '/swap/d' /etc/fstab

    modprobe overlay
    modprobe br_netfilter
    cat > /etc/sysctl.d/k8s.conf <<SYSCTL
    net.bridge.bridge-nf-call-iptables  = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward                 = 1
    SYSCTL
    sysctl --system

    # containerd
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu jammy stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y containerd.io
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    systemctl restart containerd && systemctl enable containerd

    # kubeadm / kubelet / kubectl
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key \
      | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
      https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" \
      > /etc/apt/sources.list.d/kubernetes.list
    apt-get update -y
    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl

    touch /tmp/node-ready
  EOF

  tags = {
    Name = var.name
    Role = var.role
  }
}

output "public_ip"  { value = aws_instance.node.public_ip }
output "private_ip" { value = aws_instance.node.private_ip }
output "instance_id" { value = aws_instance.node.id }
