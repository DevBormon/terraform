#!/bin/bash

# Exit immediately if any command fails
set -e

# swap memory desable
echo "[1/6] Disabling swap..."
sudo swapoff -a


echo "[2/6] Updating package list and installing prerequisites..."
sudo apt update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt install apt-transport-https ca-certificates gpg -y

# If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
# sudo mkdir -p -m 755 /etc/apt/keyrings

echo "[3/6] Downloading Kubernetes GPG key..."
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.37/deb/Release.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "[4/6] Adding Kubernetes apt repository..."
# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.37/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

echo "[5/6] Updating apt and installing Kubernetes components..."
sudo apt update
sudo apt install kubelet kubeadm kubectl -y
sudo apt-mark hold kubelet kubeadm kubectl

echo "[6/6] Enabling kubelet service..."
sudo systemctl enable --now kubelet
