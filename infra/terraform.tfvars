# Copy your SSH public key here (cat ~/.ssh/id_rsa.pub)
ssh_pubkey = "ssh-rsa AAAA...your-public-key-here"

# Your public IP with /32 — find it with: curl ifconfig.me
allowed_ssh_cidr = "0.0.0.0/0"   # ← replace with your-ip/32 before deploying

aws_region                  = "us-east-1"
ami_id                      = "ami-0c7217cdde317cfec"   # Ubuntu 22.04 us-east-1
control_plane_instance_type = "t3.medium"
worker_instance_type        = "t3.medium"
worker_count                = 2
