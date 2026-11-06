#!/bin/bash

# Exit immediately if any command fails
set -e

BASTION_HOST_PRIVATE_IP="${1:?BASTION_HOST_PRIVATE_IP is required}"
BUCKET="${2:?BUCKET is required}"
REGION="${3:?REGION is required}"
STM_PARAMETER_PATH="${4:?STM_PARAMETER_PATH is required}"

exec > >(tee -a /var/log/k8s-worker-setup.log) 2>&1

echo "Starting Kubernetes setup: $(date)"

# Install Containerd
bash /opt/k8s/k8s_setup/containerd.sh

# Configure Containerd proxy (Required for pull for workload images)
sudo mkdir -p /etc/systemd/system/containerd.service.d

sudo tee /etc/systemd/system/containerd.service.d/http-proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=http://${BASTION_HOST_PRIVATE_IP}:3128"
Environment="HTTPS_PROXY=http://${BASTION_HOST_PRIVATE_IP}:3128"
Environment="NO_PROXY=localhost,127.0.0.1,.svc,.cluster.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
EOF

sudo systemctl daemon-reload
sudo systemctl restart containerd

# Install kube config
bash /opt/k8s/k8s_setup/kubeadm_kubelet_kubectl.sh

# Certificet created by Kubernetes CSR mechanism
# CSR: Certificate Signing Request
# SAN: Subject Alternative Name
# SAN tells the client which IP addresses or domain names belong to the server presenting the certificate
CONFIG=/var/lib/kubelet/config.yaml

if grep -q "^serverTLSBootstrap:" "$CONFIG"; then
    sudo sed -i "s/^serverTLSBootstrap:.*/serverTLSBootstrap: true/" "$CONFIG"
else
    echo "serverTLSBootstrap: true" | sudo tee -a "$CONFIG"
fi

sudo systemctl restart kubelet

# Fetch Join Command from SSM Parameter Store and Join Cluster
JOIN_CMD=""

while [ -z "$JOIN_CMD" ]; do
    JOIN_CMD=$(aws ssm get-parameter \
        --name "$STM_PARAMETER_PATH" \
        --with-decryption \
        --query "Parameter.Value" \
        --output text \
        --region "$REGION" 2>/dev/null || true)

    if [ -z "$JOIN_CMD" ] || [ "$JOIN_CMD" = "None" ]; then
        echo "Waiting for Kubernetes join command..."
        JOIN_CMD=""
        sleep 10
    fi
done
echo "Join command retrieved successfully."

# Get the EC2 instance ID using IMDSv2
TOKEN=$(curl -s -X PUT \
    "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

# Get Instance Availability Zone using IMDSv2
AZ=$(curl -s \
    -H "X-aws-ec2-metadata-token: $TOKEN" \
    "http://169.254.169.254/latest/meta-data/placement/availability-zone")


INSTANCE_ID=$(curl -s \
    -H "X-aws-ec2-metadata-token: $TOKEN" \
    "http://169.254.169.254/latest/meta-data/instance-id")


# Generate a unique Kubernetes node name
NODE_NAME="worker-${INSTANCE_ID}"

# Update EC2 instance Name tag
aws ec2 create-tags --resources "$INSTANCE_ID" --tags "Key=Name,Value=${NODE_NAME}" --region "$REGION"

# Join this worker node with k8s admin as NODE_NAME
sudo $JOIN_CMD --node-name="${NODE_NAME}"

echo "New node ($NODE_NAME) Join successfully."
