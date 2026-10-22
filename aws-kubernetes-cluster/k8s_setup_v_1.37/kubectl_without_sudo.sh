#!/bin/bash

echo "kubectl run without sudo"
mkdir -p ~/.kube
sudo cp -i /etc/kubernetes/admin.conf ~/.kube/config
sudo chown `id -u`:`id -g` ~/.kube/config
