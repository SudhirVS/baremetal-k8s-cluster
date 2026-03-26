terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ── Networking ────────────────────────────────────────────────────────────────
resource "aws_vpc" "k8s" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "k8s-vpc" }
}

resource "aws_internet_gateway" "k8s" {
  vpc_id = aws_vpc.k8s.id
  tags   = { Name = "k8s-igw" }
}

resource "aws_subnet" "k8s" {
  vpc_id                  = aws_vpc.k8s.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"
  tags                    = { Name = "k8s-subnet" }
}

resource "aws_route_table" "k8s" {
  vpc_id = aws_vpc.k8s.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s.id
  }
  tags = { Name = "k8s-rt" }
}

resource "aws_route_table_association" "k8s" {
  subnet_id      = aws_subnet.k8s.id
  route_table_id = aws_route_table.k8s.id
}

# ── Security Group ────────────────────────────────────────────────────────────
resource "aws_security_group" "k8s" {
  name   = "k8s-sg"
  vpc_id = aws_vpc.k8s.id

  # SSH from your IP only
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # Full traffic within the cluster subnet
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.1.0/24"]
  }

  # Kubernetes API server (for kubectl from your machine)
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # NodePort range (for app access)
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "k8s-sg" }
}

# ── Key Pair ──────────────────────────────────────────────────────────────────
resource "aws_key_pair" "k8s" {
  key_name   = "k8s-key"
  public_key = var.ssh_pubkey
}

# ── Nodes ─────────────────────────────────────────────────────────────────────
module "control_plane" {
  source            = "./modules/node"
  name              = "k8s-control-plane"
  instance_type     = var.control_plane_instance_type
  ami_id            = var.ami_id
  subnet_id         = aws_subnet.k8s.id
  security_group_id = aws_security_group.k8s.id
  key_name          = aws_key_pair.k8s.key_name
  role              = "control-plane"
  disk_gb           = 20
}

module "worker_nodes" {
  source            = "./modules/node"
  count             = var.worker_count
  name              = "k8s-worker-${count.index + 1}"
  instance_type     = var.worker_instance_type
  ami_id            = var.ami_id
  subnet_id         = aws_subnet.k8s.id
  security_group_id = aws_security_group.k8s.id
  key_name          = aws_key_pair.k8s.key_name
  role              = "worker"
  disk_gb           = 20
}
