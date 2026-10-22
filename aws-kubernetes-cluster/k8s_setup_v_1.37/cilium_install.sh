#!/bin/bash

# Exit immediately if any command fails
set -e

CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

echo "Install CILIUM"
cilium install \
 --set ipam.mode=cluster-pool \
 --set ipam.operator.clusterPoolIPv4PodCIDRList="{192.168.0.0/16}" \
 --set ipam.operator.clusterPoolIPv4MaskSize=24

