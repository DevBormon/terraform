#!/bin/bash -l

# Stops execution if a command fails, an undefined variable is used, or a pipeline fails.
set -euo pipefail

PARAMETER_NAME="${1:?Parameter name is required}"
REGION="${2:?AWS region is required}"

# Generate a new bootstrap token valid for 24 hours.
JOIN_CMD=$(kubeadm token create --ttl 14h --print-join-command)

# Update the encrypted SSM parameter.
aws ssm put-parameter --name "$PARAMETER_NAME" --type SecureString --value "$JOIN_CMD" --overwrite --region "$REGION" >/dev/null

echo "Kubernetes worker join command refreshed successfully."