#!/bin/bash

# Check containerd configuration | SystemdCgroup is set to true
echo "[1/8] SystemdCgroup is set to true"
sudo grep 'SystemdCgroup' /etc/containerd/config.toml
printf '\n\n\n'

# Check Kubernetes versions | version is 1.37
echo "[2/8] Check kubeadm version"
kubeadm version
printf '\n\n\n'

echo "[3/8] Check kubelet version"
kubelet --version
printf '\n\n\n'

echo "[4/8] Check kubectl version"
kubectl version --client
printf '\n\n\n'

echo "[5/8] Check IP forwarding is set to 1"
# Check IP forwarding is set to 1
sysctl net.ipv4.ip_forward
printf '\n\n\n'

echo "[6/8] Check swap is disabled | no output expected"
# Check swap is disabled
swapon --show
printf '\n\n\n'

echo "[7/8] Check loaded networking modules"
# Check loaded networking modules | The required kernel modules are loaded | The Kubernetes packages are installed
lsmod | grep -E 'overlay|br_netfilter'
printf '\n\n\n'

echo "[8/9] Validate CILIUM Status"
# Validate the Installation
cilium status --wait

echo "[9/9] Check containerd is active"
# Check containerd is active
sudo systemctl status containerd




