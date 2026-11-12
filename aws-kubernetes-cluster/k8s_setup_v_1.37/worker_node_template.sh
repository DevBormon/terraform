#!/bin/bash

set -euo pipefail

BASTION_HOST_PRIVATE_IP="${1:?BASTION_HOST_PRIVATE_IP is required}"
BUCKET="${2:?BUCKET is required}"
REGION="${3:?REGION is required}"
SSM_PARAMETER_PATH="${4:?SSM_PARAMETER_PATH is required}"
NODE_NAME="${5:?NODE_NAME is required}"
PROVIDER_ID="${6:?PROVIDER_ID is required}"

exec > >(tee -a /var/log/k8s-worker-setup.log) 2>&1

echo "Starting Kubernetes worker setup: $(date)"

# --------------------------------------------------
# 1. Install containerd
# --------------------------------------------------

echo "Installing containerd..."

bash /opt/k8s/k8s_setup/containerd.sh

# --------------------------------------------------
# 2. Configure containerd proxy
# --------------------------------------------------

echo "Configuring containerd proxy..."

mkdir -p /etc/systemd/system/containerd.service.d

tee /etc/systemd/system/containerd.service.d/http-proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=http://${BASTION_HOST_PRIVATE_IP}:3128"
Environment="HTTPS_PROXY=http://${BASTION_HOST_PRIVATE_IP}:3128"
Environment="NO_PROXY=localhost,127.0.0.1,.svc,.cluster.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
EOF

systemctl daemon-reload
systemctl restart containerd

echo "Containerd is running."

# --------------------------------------------------
# 3. Install Kubernetes components
# --------------------------------------------------

echo "Installing kubelet, kubeadm and kubectl..."

bash /opt/k8s/k8s_setup/kubeadm_kubelet_kubectl.sh

# Stop kubelet until kubeadm join generates its config.
echo "Stopping kubelet before cluster join..."

systemctl stop kubelet || true

# --------------------------------------------------
# 4. Retrieve Kubernetes join command from SSM
# --------------------------------------------------

echo "Retrieving Kubernetes join command from SSM..."

JOIN_CMD=""

while [ -z "$JOIN_CMD" ] || [ "$JOIN_CMD" = "None" ]; do

    JOIN_CMD=$(aws ssm get-parameter \
        --name "$SSM_PARAMETER_PATH" \
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

# --------------------------------------------------
# 5. Join Kubernetes cluster
# --------------------------------------------------

# 5. Extract discovery information from join command
# Expected format:
# kubeadm join ENDPOINT --token TOKEN \
# --discovery-token-ca-cert-hash sha256:HASH

JOIN_ARGS=()

read -r -a JOIN_ARGS <<< "$JOIN_CMD"

if [[ "${JOIN_ARGS[0]}" != "kubeadm" || "${JOIN_ARGS[1]}" != "join" ]]; then
    echo "ERROR: Invalid kubeadm join command."
    exit 1
fi

API_ENDPOINT=""
BOOTSTRAP_TOKEN=""
CA_HASH=""

# $ → Get the value.
# { } → Enclose the variable expression.
# # → Count the elements.
# JOIN_ARGS → Array name.
# [@] → All elements of the array.

# --token → Pattern to match.
# ) → End of the pattern and start of its commands.
# ;; → End of this case.
# esac → Ends the entire case statement (case backwards).

for ((i=1; i<${#JOIN_ARGS[@]}; i++)); do

    case "${JOIN_ARGS[$i]}" in

        join)
            i=$((i+1))
            API_ENDPOINT="${JOIN_ARGS[$i]}"
            ;;

        --token)
            i=$((i+1))
            BOOTSTRAP_TOKEN="${JOIN_ARGS[$i]}"
            ;;

        --discovery-token-ca-cert-hash)
            i=$((i+1))
            CA_HASH="${JOIN_ARGS[$i]}"
            ;;

    esac

done

if [[ -z "$API_ENDPOINT" || -z "$BOOTSTRAP_TOKEN" || -z "$CA_HASH" ]]; then
    echo "ERROR: Missing kubeadm discovery information."
    exit 1
fi

# 6. Create kubeadm JoinConfiguration
echo "Creating kubeadm JoinConfiguration..."

cat > /tmp/kubeadm-join.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: JoinConfiguration
discovery:
  bootstrapToken:
    apiServerEndpoint: "${API_ENDPOINT}"
    token: "${BOOTSTRAP_TOKEN}"
    caCertHashes:
      - "${CA_HASH}"
nodeRegistration:
  name: "${NODE_NAME}"
  kubeletExtraArgs:
    - name: provider-id
      value: "${PROVIDER_ID}"
  taints:
    - key: karpenter.sh/unregistered
      effect: NoExecute
EOF

chmod 600 /tmp/kubeadm-join.yaml

# 7. Join Kubernetes cluster
echo "Joining Kubernetes cluster..."

kubeadm join --config /tmp/kubeadm-join.yaml

echo "${NODE_NAME} join successfully."

# --------------------------------------------------
# 6. Configure kubelet
# --------------------------------------------------

echo "Configuring kubelet..."

KUBELET_CONFIG="/var/lib/kubelet/config.yaml"

if [[ ! -f "$KUBELET_CONFIG" ]]; then
    echo "ERROR: Kubelet config not generated."
    exit 1
fi

if grep -q "^serverTLSBootstrap:" "$KUBELET_CONFIG"; then
    sed -i 's/^serverTLSBootstrap:.*/serverTLSBootstrap: true/' "$KUBELET_CONFIG"
else
    echo "serverTLSBootstrap: true" >> "$KUBELET_CONFIG"
fi

echo "Kubelet configuration updated."

# --------------------------------------------------
# 7. Restart and verify kubelet
# --------------------------------------------------

echo "Starting kubelet..."

systemctl daemon-reload
systemctl restart kubelet

sleep 5

if systemctl is-active --quiet kubelet; then
    echo "Kubelet is running successfully."
else
    echo "ERROR: Kubelet failed to start."
    systemctl status kubelet --no-pager || true
    journalctl -u kubelet -n 50 --no-pager || true
    exit 1
fi

rm -f /tmp/kubeadm-join.yaml
rm -rf /opt/k8s/

echo "=============================================="
echo "Kubernetes worker setup completed successfully."
echo "Node Name: ${NODE_NAME}"
echo "=============================================="