resource "aws_instance" "instances" {
  for_each = local.instances

  ami                         = "ami-0199ac7c9fbf9ed83"
  instance_type               = each.value.instance_type
  subnet_id                   = each.value.subnet_id
  vpc_security_group_ids      = each.value.vpc_security_group_ids
  associate_public_ip_address = each.value.associate_public_ip_address
  iam_instance_profile        = each.key == "master" ? aws_iam_instance_profile.master_profile.name : each.key == "worker-1" ? aws_iam_instance_profile.worker_profile.name : null
  key_name                    = each.value.key_name
  root_block_device {
    volume_size = each.value.volume_size
    volume_type = each.value.volume_type
  }
  tags = {
    Name = each.key
  }
}

resource "terraform_data" "upload_pem" {
  depends_on = [aws_instance.instances["bastion_host"]]
  connection {
    type        = "ssh"
    host        = aws_instance.instances["bastion_host"].public_ip
    user        = "ubuntu"
    private_key = file(local.access_key)
  }

  provisioner "file" {
    source      = local.access_key
    destination = "/home/ubuntu/.ssh/aws-login.pem"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 400 /home/ubuntu/.ssh/aws-login.pem"
    ]
  }
}

resource "terraform_data" "upload_k8s_setup_to_s3" {
  depends_on = [aws_s3_bucket.k8s_bucket]
  triggers_replace = [
    jsonencode(local.k8s_setup_hashes)
  ]

  provisioner "local-exec" {
    command = "aws s3 sync ${path.module}/k8s_setup_v_1.37 s3://${aws_s3_bucket.k8s_bucket.bucket}/k8s_setup/"
  }
}
resource "terraform_data" "upload_manifests_to_s3" {
  depends_on = [aws_s3_bucket.k8s_bucket]
  triggers_replace = [
    jsonencode(local.manifests_hashes)
  ]

  provisioner "local-exec" {
    command = "aws s3 sync ${path.module}/manifests s3://${aws_s3_bucket.k8s_bucket.bucket}/k8s_manifest/"
  }
}

# master, workers have private IP addresses and no NAT gateway is configured. Therefore, we need to set up a proxy server to provide internet access to these nodes

#Iinstalling the Squid proxy server | default port 3128
resource "terraform_data" "install_squid" {
  depends_on = [
    aws_instance.instances["bastion_host"]
  ]
  connection {
    type        = "ssh"
    host        = aws_instance.instances["bastion_host"].public_ip
    user        = "ubuntu"
    private_key = file(local.access_key)
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
      "sudo apt install squid -y",
      "sudo systemctl enable --now squid",

      # Remove any previous attempts if they exist to avoid duplicates
      "sudo sed -i '/my-vpc/d' /etc/squid/squid.conf",

      # 1. Insert the ACL and allow rules at the very top of squid.conf
      "sudo sed -i '1i acl my-vpc src ${aws_vpc.vpc.cidr_block}' /etc/squid/squid.conf",
      "sudo sed -i '2i http_access allow my-vpc' /etc/squid/squid.conf",

      /*
      grep – Searches for the specified line.
      -q – Quiet mode; doesn't display output.
      -x – Matches the entire line, not just part of it.
      -F – Treats the search string as fixed text.
      || – Executes the next command only if the previous command fails.
      tee -a – Appends the line to the file. 
      */
      "grep -qxF 'http_access deny all' /etc/squid/squid.conf || echo 'http_access deny all' | sudo tee -a /etc/squid/squid.conf",
      "sudo systemctl restart squid"
    ]
  }
}

# Update APT Config for access internet throw proxy
resource "terraform_data" "configure_apt_proxy" {
  for_each = toset(["master", "worker-1"])

  depends_on = [
    terraform_data.install_squid
  ]

  connection {
    type        = "ssh"
    host        = aws_instance.instances[each.key].private_ip
    user        = "ubuntu"
    private_key = file(local.access_key)

    bastion_host        = aws_instance.instances["bastion_host"].public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(local.access_key)
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Acquire::http::Proxy \"http://${aws_instance.instances["bastion_host"].private_ip}:3128/\";' | sudo tee /etc/apt/apt.conf.d/80proxy",
      "echo 'Acquire::https::Proxy \"http://${aws_instance.instances["bastion_host"].private_ip}:3128/\";' | sudo tee -a /etc/apt/apt.conf.d/80proxy"
    ]
  }
}

# Configure curl to use the bastion proxy and IPv4
resource "terraform_data" "configure_curl_proxy" {
  for_each = toset(["master", "worker-1"])

  connection {
    type        = "ssh"
    host        = aws_instance.instances[each.key].private_ip
    user        = "ubuntu"
    private_key = file(local.access_key)

    bastion_host        = aws_instance.instances["bastion_host"].public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(local.access_key)
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
      "sudo apt install curl -y",
      <<-EOT
      sudo tee ~/.curlrc > /dev/null <<'EOF'
      proxy = "http://${aws_instance.instances["bastion_host"].private_ip}:3128"
      ipv4
      EOF
      EOT
    ]
  }
}

resource "terraform_data" "install_and_configure_aws_cli_proxy" {
  for_each = toset(["master", "worker-1"])
  depends_on = [
    terraform_data.configure_apt_proxy,
    terraform_data.configure_curl_proxy
  ]

  connection {
    type        = "ssh"
    host        = aws_instance.instances[each.key].private_ip
    user        = "ubuntu"
    private_key = file(local.access_key)

    bastion_host        = aws_instance.instances["bastion_host"].public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(local.access_key)
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
      "sudo apt install awscli -y",
      # When a user logs in using SSH, /etc/profile.d is normally executed
      <<-EOT
        sudo tee /etc/profile.d/k8s-proxy.sh <<'EOF'
        export HTTP_PROXY=http://${aws_instance.instances["bastion_host"].private_ip}:3128
        export HTTPS_PROXY=http://${aws_instance.instances["bastion_host"].private_ip}:3128
        export NO_PROXY=169.254.169.254,localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,.svc,.cluster.local
        EOF
      EOT
      ,
      "sudo chmod +x /etc/profile.d/k8s-proxy.sh",

      # Configure sudo to preserve proxy environment variables
      <<-EOT
        sudo tee /etc/sudoers.d/proxy <<'EOF'
        Defaults env_keep += "HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy"
        EOF
      EOT
    ]
  }
}

resource "terraform_data" "install_containerd" {
  for_each = toset(["master", "worker-1"])
  depends_on = [
    terraform_data.configure_apt_proxy,
    terraform_data.upload_k8s_setup_to_s3,
    terraform_data.install_and_configure_aws_cli_proxy
  ]

  connection {
    type        = "ssh"
    host        = aws_instance.instances[each.key].private_ip
    user        = "ubuntu"
    private_key = file(local.access_key)

    bastion_host        = aws_instance.instances["bastion_host"].public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(local.access_key)
  }

  provisioner "remote-exec" {
    inline = [
      # Terraform uses that first line as the script's shebang. The -l flag makes bash a login shell, so it reads /etc/profile, which loads /etc/profile.d/k8s-proxy.sh
      "#!/bin/bash -l",
      "set -e",
      "echo '===== CHECK CURRENT SHELL PROXY ====='",
      "env | grep -i proxy || true",

      "echo '===== SUDO CHECK CURRENT SHELL PROXY ====='",
      "sudo env | grep -i proxy || true",

      "echo '===== DIR CREATED ====='",
      "sudo mkdir -p /opt/k8s/k8s_setup",

      "echo '===== GET CALLER IDENTITY ====='",
      "aws sts get-caller-identity",

      "echo '===== AWS SYNC ====='",
      "sudo aws s3 sync s3://${aws_s3_bucket.k8s_bucket.bucket}/k8s_setup/ /opt/k8s/k8s_setup/",

      "echo '===== CONTAINERD INSTALL ====='",
      "bash /opt/k8s/k8s_setup/containerd.sh"
    ]
  }
}

# Configure Proxy for Containerd (Required for kubeadm init and pull for workload images)
resource "terraform_data" "configure_containerd_proxy" {
  for_each = toset(["master", "worker-1"])
  depends_on = [
    terraform_data.install_containerd
  ]

  connection {
    type        = "ssh"
    host        = aws_instance.instances[each.key].private_ip
    user        = "ubuntu"
    private_key = file(local.access_key)

    bastion_host        = aws_instance.instances["bastion_host"].public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(local.access_key)
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /etc/systemd/system/containerd.service.d",
      <<-EOT
        sudo tee /etc/systemd/system/containerd.service.d/http-proxy.conf <<'EOF'
        [Service]
        Environment="HTTP_PROXY=http://${aws_instance.instances["bastion_host"].private_ip}:3128"
        Environment="HTTPS_PROXY=http://${aws_instance.instances["bastion_host"].private_ip}:3128"
        Environment="NO_PROXY=localhost,127.0.0.1,.svc,.cluster.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
        EOF
      EOT
      ,

      # 3. Reload and restart containerd
      "sudo systemctl daemon-reload",
      "sudo systemctl restart containerd"
    ]
  }
}

resource "terraform_data" "kubes_install" {
  for_each = toset(["master", "worker-1"])
  depends_on = [
    terraform_data.install_containerd,
    terraform_data.configure_containerd_proxy,
    terraform_data.configure_curl_proxy
  ]

  connection {
    type        = "ssh"
    host        = aws_instance.instances[each.key].private_ip
    user        = "ubuntu"
    private_key = file(local.access_key)

    bastion_host        = aws_instance.instances["bastion_host"].public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(local.access_key)
  }

  provisioner "remote-exec" {
    inline = [
      "bash /opt/k8s/k8s_setup/kubeadm_kubelet_kubectl.sh"
    ]
  }
}

resource "terraform_data" "kubeadm_init" {
  depends_on = [
    terraform_data.kubes_install,
    terraform_data.configure_containerd_proxy,
    terraform_data.upload_k8s_setup_to_s3
  ]

  connection {
    type        = "ssh"
    host        = aws_instance.instances["master"].private_ip
    user        = "ubuntu"
    private_key = file(local.access_key)

    bastion_host        = aws_instance.instances["bastion_host"].public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(local.access_key)
  }

  provisioner "remote-exec" {
    inline = [
      # Initialize cluster with OIDC issuer flags pointing to your public S3 bucket
      "sudo kubeadm init --node-name=master",

      # Update OIDC issuer configuration
      <<-EOT
        MANIFEST=/etc/kubernetes/manifests/kube-apiserver.yaml

        sudo sed -i 's|--service-account-issuer=.*|--service-account-issuer=https://${aws_s3_bucket.k8s_bucket.bucket}.s3.${data.aws_region.current.region}.amazonaws.com|' "$MANIFEST"

        if ! sudo grep -q -- '--service-account-jwks-uri=' "$MANIFEST"; then
          sudo sed -i '/- kube-apiserver/a \    - --service-account-jwks-uri=https://${aws_s3_bucket.k8s_bucket.bucket}.s3.${data.aws_region.current.region}.amazonaws.com/openid/v1/jwks' "$MANIFEST"
        else
          sudo sed -i 's|--service-account-jwks-uri=.*|--service-account-jwks-uri=https://${aws_s3_bucket.k8s_bucket.bucket}.s3.${data.aws_region.current.region}.amazonaws.com/openid/v1/jwks|' "$MANIFEST"
        fi
      EOT
      ,
      "sudo systemctl restart kubelet"
    ]
  }
}

resource "terraform_data" "config_kubectl" {
  depends_on = [
    terraform_data.kubeadm_init
  ]

  connection {
    type        = "ssh"
    host        = aws_instance.instances["master"].private_ip
    user        = "ubuntu"
    private_key = file(local.access_key)

    bastion_host        = aws_instance.instances["bastion_host"].public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(local.access_key)
  }

  provisioner "remote-exec" {
    inline = [
      "bash /opt/k8s/k8s_setup/kubectl_without_sudo.sh"
    ]
  }
}

resource "terraform_data" "config_oidc" {
  depends_on = [
    terraform_data.config_kubectl,
    terraform_data.install_and_configure_aws_cli_proxy
  ]

  connection {
    type        = "ssh"
    host        = aws_instance.instances["master"].private_ip
    user        = "ubuntu"
    private_key = file(local.access_key)

    bastion_host        = aws_instance.instances["bastion_host"].public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(local.access_key)
  }

  provisioner "remote-exec" {
    inline = [
      # Enable command tracing and capture all stdout/stderr to a log file

      # -e (errexit): Stops the script immediately if any individual command fails.
      # -o pipefail: Forces the pipeline to fail if any command in the chain (kubectl or aws) fails, rather than just looking at the final command.
      "#!/bin/bash -l",
      "set -eo pipefail",

      "echo 'Waiting for Kubernetes API server to become ready...'",
      "until kubectl version --client=false >/dev/null 2>&1; do sleep 5; done",

      "echo 'Fetching and Upload OIDC configuration ...'",
      "kubectl get --raw /.well-known/openid-configuration | aws s3 cp - s3://${aws_s3_bucket.k8s_bucket.bucket}/.well-known/openid-configuration",

      # Command 2 with logging
      "echo 'Fetching and Upload JWKS ...'",
      "kubectl get --raw /openid/v1/jwks | aws s3 cp - s3://${aws_s3_bucket.k8s_bucket.bucket}/openid/v1/jwks",

      "echo 'Successfully synced OIDC and JWKS to S3!'"
    ]
  }
}

resource "terraform_data" "cilium_installation" {
  depends_on = [
    terraform_data.config_oidc,
    terraform_data.configure_curl_proxy
  ]

  connection {
    type        = "ssh"
    host        = aws_instance.instances["master"].private_ip
    user        = "ubuntu"
    private_key = file(local.access_key)

    bastion_host        = aws_instance.instances["bastion_host"].public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(local.access_key)
  }

  provisioner "remote-exec" {
    inline = [
      "bash /opt/k8s/k8s_setup/cilium_install.sh"
    ]
  }
}

resource "terraform_data" "join_token_refresh" {
  depends_on = [
    terraform_data.cilium_installation
  ]

  connection {
    type        = "ssh"
    host        = aws_instance.instances["master"].private_ip
    user        = "ubuntu"
    private_key = file(local.access_key)

    bastion_host        = aws_instance.instances["bastion_host"].public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(local.access_key)
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOT
        sudo tee /etc/systemd/system/kubeadm_join_refresh.service <<'EOF'
        [Unit]
        Description=Refresh Kubernetes worker join command in SSM
        After=network-online.target
        Wants=network-online.target
        
        [Service]
        Type=oneshot
        User=root
        
        ExecStart=/opt/k8s/k8s_setup/kubeadm_join_command.sh ${local.ssm_parameter_path} ${data.aws_region.current.region}
        EOF
      EOT
      ,
      <<-EOT
        sudo tee /etc/systemd/system/kubeadm_join_refresh.timer <<'EOF'
        [Unit]
        Description=Kubernetes worker join token refresh timer

        [Timer]
        OnBootSec=2min
        OnUnitActiveSec=12h
        Persistent=true

        [Install]
        WantedBy=timers.target
        EOF
      EOT
      ,

      "sudo chmod +x /opt/k8s/k8s_setup/kubeadm_join_command.sh",

      # Reload systemd configuration
      "sudo systemctl daemon-reload",

      # Enable and start the timer
      "sudo systemctl enable --now kubeadm_join_refresh.timer",

      # Run the service immediately
      "sudo systemctl start kubeadm_join_refresh.service"
    ]
  }
}

resource "terraform_data" "join_worker" {
  depends_on = [
    terraform_data.kubes_install,
    terraform_data.kubeadm_init,
    terraform_data.join_token_refresh
  ]

  connection {
    type        = "ssh"
    host        = aws_instance.instances["worker-1"].private_ip
    user        = "ubuntu"
    private_key = file(local.access_key)

    bastion_host        = aws_instance.instances["bastion_host"].public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(local.access_key)
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOT
        #!/bin/bash -l
        set -e

        # Fetch Join Command from SSM Parameter Store and Join Cluster
        JOIN_CMD=""

        while [ -z "$JOIN_CMD" ]; do
            JOIN_CMD=$(aws ssm get-parameter \
                --name "${local.ssm_parameter_path}" \
                --with-decryption \
                --query "Parameter.Value" \
                --output text \
                --region "${data.aws_region.current.region}" 2>/dev/null || true)

            if [ -z "$JOIN_CMD" ] || [ "$JOIN_CMD" = "None" ]; then
                echo "Waiting for Kubernetes join command..."
                JOIN_CMD=""
                sleep 10
            fi
        done

        # Join this worker node with k8s admin as NODE_NAME
        sudo $JOIN_CMD --node-name="worker-1"
      EOT
    ]
  }
}



resource "terraform_data" "configure_node_zones" {
  depends_on = [
    terraform_data.join_worker
  ]

  connection {
    type        = "ssh"
    host        = aws_instance.instances["master"].private_ip
    user        = "ubuntu"
    private_key = file(local.access_key)

    bastion_host        = aws_instance.instances["bastion_host"].public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(local.access_key)
  }

  provisioner "remote-exec" {
    inline = [
      "kubectl label nodes \"master\" topology.kubernetes.io/zone=\"${aws_instance.instances["master"].availability_zone}\" --overwrite",
      "kubectl label nodes \"worker-1\" topology.kubernetes.io/zone=\"${aws_instance.instances["worker-1"].availability_zone}\" --overwrite"
    ]
  }
}

resource "terraform_data" "server_tls_bootstrap_worker" {
  depends_on = [terraform_data.join_worker]

  connection {
    type        = "ssh"
    host        = aws_instance.instances["worker-1"].private_ip
    user        = "ubuntu"
    private_key = file(local.access_key)

    bastion_host        = aws_instance.instances["bastion_host"].public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(local.access_key)
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOT
        #!/bin/bash -l
        set -e
        CONFIG=/var/lib/kubelet/config.yaml

        if grep -q '^serverTLSBootstrap:' "$CONFIG"; then
            sudo sed -i 's/^serverTLSBootstrap:.*/serverTLSBootstrap: true/' "$CONFIG"
        else
            echo 'serverTLSBootstrap: true' | sudo tee -a "$CONFIG"
        fi

        sudo systemctl restart kubelet
      EOT
    ]
  }
}

resource "terraform_data" "helm_install" {
  depends_on = [
    terraform_data.join_token_refresh,
    terraform_data.join_worker
  ]

  connection {
    type        = "ssh"
    host        = aws_instance.instances["master"].private_ip
    user        = "ubuntu"
    private_key = file(local.access_key)

    bastion_host        = aws_instance.instances["bastion_host"].public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(local.access_key)
  }
  provisioner "remote-exec" {
    inline = [
      "bash /opt/k8s/k8s_setup/helm_install.sh ${aws_instance.instances["bastion_host"].private_ip}"
    ]
  }
}

resource "terraform_data" "kubelet_csr_approver" {
  depends_on = [
    terraform_data.kubeadm_init,
    terraform_data.join_worker,
    terraform_data.helm_install
  ]

  connection {
    type        = "ssh"
    host        = aws_instance.instances["master"].private_ip
    user        = "ubuntu"
    private_key = file(local.access_key)

    bastion_host        = aws_instance.instances["bastion_host"].public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(local.access_key)
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOT
        #!/bin/bash -l
        helm repo add kubelet-csr-approver https://postfinance.github.io/kubelet-csr-approver
        helm repo update
        helm upgrade --install kubelet-csr-approver kubelet-csr-approver/kubelet-csr-approver -n kube-system \
          --set providerRegex='^worker-([0-9]+|i-[a-f0-9]+)$' \
          --set providerIpPrefixes='${aws_vpc.vpc.cidr_block}' \
          --set maxExpirationSeconds='86400' \
          --set bypassDnsResolution='true'
      EOT
    ]
  }
}

resource "terraform_data" "metrics_server" {
  depends_on = [
    terraform_data.cilium_installation,
    terraform_data.kubeadm_init,
    terraform_data.join_worker,
    terraform_data.server_tls_bootstrap_worker,
    terraform_data.kubelet_csr_approver,
    terraform_data.helm_install
  ]

  connection {
    type        = "ssh"
    host        = aws_instance.instances["master"].private_ip
    user        = "ubuntu"
    private_key = file(local.access_key)

    bastion_host        = aws_instance.instances["bastion_host"].public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(local.access_key)
  }

  provisioner "remote-exec" {
    inline = [
      "#!/bin/bash -l",

      "set -e",

      "echo '===== ADD METRICS SERVER HELM REPOSITORY ====='",
      "helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update",

      "echo '===== UPDATE HELM REPOSITORIES ====='",
      "helm repo update",

      "echo '===== INSTALL METRICS SERVER ====='",
      "helm upgrade --install metrics-server metrics-server/metrics-server --version 3.14.0 --namespace kube-system --create-namespace --wait",

      "echo 'METRICS SERVER INSTALLATION COMPLETED'"
    ]
  }
}

resource "terraform_data" "karpenter_deploying" {
  depends_on = [
    terraform_data.join_worker,
    terraform_data.helm_install,
    terraform_data.kubelet_csr_approver,
    terraform_data.metrics_server,
    terraform_data.configure_node_zones
  ]

  connection {
    type        = "ssh"
    host        = aws_instance.instances["master"].private_ip
    user        = "ubuntu"
    private_key = file(local.access_key)

    bastion_host        = aws_instance.instances["bastion_host"].public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(local.access_key)
  }

  provisioner "remote-exec" {
    inline = [
      "#!/bin/bash -l",

      # Logout of helm registry to perform an unauthenticated pull against the public ECR
      "helm registry logout public.ecr.aws",

      <<-EOT
        helm upgrade --install karpenter \
          oci://public.ecr.aws/karpenter/karpenter \
          --version 1.15.1 \
          --namespace ${local.karpenter_ns} \
          --create-namespace \
          --set settings.clusterName=${local.cluster_name} \
          --set settings.clusterEndpoint="https://${aws_instance.instances["master"].private_ip}:6443" \
          --set replicas=1 \
          --set serviceAccount.create=true \
          --set serviceAccount.name=${local.karpenter_service_account_name} \
          --set controller.env[0].name=AWS_ROLE_ARN \
          --set controller.env[0].value="${aws_iam_role.karpenter_role.arn}" \
          --set controller.env[1].name=AWS_WEB_IDENTITY_TOKEN_FILE \
          --set controller.env[1].value="/var/run/secrets/aws/token" \
          --set controller.env[2].name=AWS_REGION \
          --set controller.env[2].value="${data.aws_region.current.region}" \
          --set controller.env[3].name=HTTP_PROXY \
          --set controller.env[3].value="http://${aws_instance.instances["bastion_host"].private_ip}:3128" \
          --set controller.env[4].name=HTTPS_PROXY \
          --set controller.env[4].value="http://${aws_instance.instances["bastion_host"].private_ip}:3128" \
          --set controller.env[5].name=NO_PROXY \
          --set controller.env[5].value="169.254.169.254\,localhost\,127.0.0.1\,10.0.0.0/8\,172.16.0.0/12\,192.168.0.0/16\,.svc\,.cluster.local" \
          --set controller.extraVolumeMounts[0].name=aws-iam-token \
          --set controller.extraVolumeMounts[0].mountPath=/var/run/secrets/aws \
          --set controller.extraVolumeMounts[0].readOnly=true \
          --set extraVolumes[0].name=aws-iam-token \
          --set extraVolumes[0].projected.sources[0].serviceAccountToken.audience=sts.amazonaws.com \
          --set extraVolumes[0].projected.sources[0].serviceAccountToken.expirationSeconds=3600 \
          --set extraVolumes[0].projected.sources[0].serviceAccountToken.path=token \
          --wait
      EOT

    ]
  }
}

resource "terraform_data" "karpenter_manifest_apply" {
  depends_on = [
    terraform_data.karpenter_deploying,
    terraform_data.upload_manifests_to_s3
  ]

  connection {
    type        = "ssh"
    host        = aws_instance.instances["master"].private_ip
    user        = "ubuntu"
    private_key = file(local.access_key)

    bastion_host        = aws_instance.instances["bastion_host"].public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(local.access_key)
  }

  provisioner "remote-exec" {
    inline = [
      "#!/bin/bash -l",
      "sudo mkdir -p /opt/k8s/k8s_manifest",
      "sudo aws s3 sync s3://${aws_s3_bucket.k8s_bucket.bucket}/k8s_manifest/ /opt/k8s/k8s_manifest/",

      # Install envsubst
      "sudo apt install gettext-base -y",

      # Pass Terraform values as environment variables
      <<-EOT
        export BASTION_HOST_PRIVATE_IP="${aws_instance.instances["bastion_host"].private_ip}"
        export BUCKET="${aws_s3_bucket.k8s_bucket.bucket}"
        export REGION="${data.aws_region.current.region}"
        export STM_PARAMETER_PATH="${local.ssm_parameter_path}"

        # replace all variables with their value
        envsubst < /opt/k8s/k8s_manifest/karpenter/karpenter-nodeclass.yaml > /tmp/karpenter-nodeclass.yaml

        # Apply EC2NodeClass & NodePool
        kubectl apply -f /tmp/karpenter-nodeclass.yaml
        kubectl apply -f /opt/k8s/k8s_manifest/karpenter/karpenter-nodepool.yaml
      EOT
    ]
  }
}
