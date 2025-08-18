MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==NITRO_ENCLAVES=="

--==NITRO_ENCLAVES==
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash

# Nitro Enclaves Setup Script for EKS Nodes
# This script configures EC2 instances to support Nitro Enclaves

set -e

# Log all output
exec > >(tee /var/log/nitro-enclaves-setup.log)
exec 2>&1

echo "Starting Nitro Enclaves setup at $(date)"

# Install Nitro Enclaves CLI and development tools
echo "Installing Nitro Enclaves CLI..."
amazon-linux-extras install aws-nitro-enclaves-cli -y
yum install aws-nitro-enclaves-cli-devel -y

# Add ec2-user to nitro enclaves group
echo "Configuring user permissions..."
usermod -aG ne ec2-user
usermod -aG docker ec2-user

# Configure Nitro Enclaves allocator
echo "Configuring Nitro Enclaves allocator..."
# Allocate 3GB of memory for enclaves (adjust based on instance size)
sed -i 's/memory_mib: 512/memory_mib: 3072/g' /etc/nitro_enclaves/allocator.yaml

# Configure CPU allocation (reserve 1 CPU for enclaves)
sed -i 's/cpu_count: 2/cpu_count: 1/g' /etc/nitro_enclaves/allocator.yaml

# Enable and start Nitro Enclaves allocator service
echo "Starting Nitro Enclaves services..."
systemctl start nitro-enclaves-allocator.service
systemctl enable nitro-enclaves-allocator.service

# Enable and start Docker
echo "Configuring Docker..."
systemctl start docker
systemctl enable docker

# Configure hugepages (required for Nitro Enclaves)
echo "Configuring hugepages..."
echo 'vm.nr_hugepages = 1536' >> /etc/sysctl.conf
sysctl -p

# Create hugepages mount point
mkdir -p /dev/hugepages-1Gi
mount -t hugetlbfs -o pagesize=1G none /dev/hugepages-1Gi

# Add hugepages mount to fstab for persistence
echo 'none /dev/hugepages-1Gi hugetlbfs pagesize=1G 0 0' >> /etc/fstab

# Install additional tools for debugging (optional)
echo "Installing additional tools..."
yum install -y htop iotop

# Configure Docker daemon for better enclave support
echo "Configuring Docker daemon..."
cat > /etc/docker/daemon.json << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF

# Restart Docker with new configuration
systemctl restart docker

# Verify Nitro Enclaves installation
echo "Verifying Nitro Enclaves installation..."
nitro-cli --version

# Check allocator status
echo "Checking Nitro Enclaves allocator status..."
systemctl status nitro-enclaves-allocator.service

# Display allocated resources
echo "Nitro Enclaves resource allocation:"
nitro-cli describe-enclaves

echo "Nitro Enclaves setup completed successfully at $(date)"

--==NITRO_ENCLAVES==-- 