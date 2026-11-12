#!/bin/bash

echo "kubectl run without sudo"
mkdir -p ~/.kube
sudo cp -f /etc/kubernetes/admin.conf ~/.kube/config
sudo chown `id -u`:`id -g` ~/.kube/config

echo "set alias (k) for kunectl"
echo 'alias k=kubectl' >> ~/.bashrc
source ~/.bashrc
