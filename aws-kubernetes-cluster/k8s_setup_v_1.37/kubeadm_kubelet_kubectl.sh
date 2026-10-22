#!/bin/bash

# Exit immediately if any command fails
set -e

BASTION_PRIVATE_IP="$1"

if [ -z "$BASTION_PRIVATE_IP" ]; then
    echo "Error: Bastion private IP was not provided."
    exit 1
fi

# swap memory desable
echo "[1/7] Disabling swap..."
sudo swapoff -a


echo "[2/7] Updating package list and installing prerequisites..."
sudo apt update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt install apt-transport-https ca-certificates curl gpg -y

# Update CURL Config for access internet throw proxy
echo "[3/7] Update the cURL configuration to connect through the bastion host proxy and use IPv4"
# Create curl config file
touch ~/.curlrc

# Configure curl to use the bastion proxy and IPv4
sudo tee ~/.curlrc > /dev/null <<EOF
proxy = "http://${BASTION_PRIVATE_IP}:3128"
ipv4
EOF

# If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
# sudo mkdir -p -m 755 /etc/apt/keyrings

echo "[4/7] Downloading Kubernetes GPG key..."
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.37/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "[5/7] Adding Kubernetes apt repository..."
# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.37/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

echo "[6/7] Updating apt and installing Kubernetes components..."
sudo apt update
sudo apt install kubelet kubeadm kubectl -y
sudo apt-mark hold kubelet kubeadm kubectl

echo "[7/7] Enabling kubelet service..."
sudo systemctl enable --now kubelet
