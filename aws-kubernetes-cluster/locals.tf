locals {
  common = {
    key_name = "aws-login"
  }

  access_key                     = "/home/bormon/.ssh/${local.common.key_name}.pem"
  cluster_name                   = "k8s-worker-cluster"
  karpenter_ns                   = "karpenter"
  karpenter_service_account_name = "karpenter"

  ssm_parameter_path = "/k8s-worker/join-command"

  # Use fileset() and filesha256() to detect changes in files.
  # Kubernetes setup scripts
  k8s_setup_files = fileset("${path.module}/k8s_setup_v_1.37", "**")

  k8s_setup_hashes = {
    for file in local.k8s_setup_files :
    file => filesha256("${path.module}/k8s_setup_v_1.37/${file}")
  }

  # Kubernetes manifests
  manifests_files = fileset("${path.module}/manifests", "**")

  manifests_hashes = {
    for file in local.manifests_files :
    file => filesha256("${path.module}/manifests/${file}")
  }

  k8s_config = {
    instance_type               = "c7i-flex.large"
    associate_public_ip_address = false
    volume_size                 = 8
    volume_type                 = "gp3"
  }

  instances = {
    bastion_host = merge(local.common, {
      instance_type               = "t3.micro"
      subnet_id                   = aws_subnet.subnet_public_1.id
      vpc_security_group_ids      = [aws_security_group.my_sg["bastion-sg"].id]
      associate_public_ip_address = true
      volume_size                 = 8
      volume_type                 = "gp3"
    })
    master = merge(local.common, local.k8s_config, {
      subnet_id              = aws_subnet.subnet_private_1.id
      vpc_security_group_ids = [aws_security_group.my_sg["k8s-master-sg"].id]
      }
    )
    worker-1 = merge(
      local.common, local.k8s_config,
      {
        subnet_id              = aws_subnet.subnet_private_1.id
        vpc_security_group_ids = [aws_security_group.my_sg["k8s-worker-sg"].id]
      }
    )
  }
  # for Security group
  k8s_ports = {
    lb = {
      sg          = "lb-sg"
      cidr_ipv4   = "0.0.0.0/0"
      ip_protocol = "-1"
      description = "Allow all traffic for LB"
    }
    squid_proxy = {
      sg          = "bastion-sg"
      cidr_ipv4   = "10.0.0.0/16"
      from_port   = 3128
      to_port     = 3128
      description = "HTTP proxy from VPC instances"
    }
    ssh_bastion = {
      sg          = "bastion-sg"
      cidr_ipv4   = "0.0.0.0/0"
      from_port   = 22
      to_port     = 22
      description = "SSH access"
    }
    ssh_master = {
      sg          = "k8s-master-sg"
      reference   = "bastion-sg"
      from_port   = 22
      to_port     = 22
      description = "SSH access"
    }
    ssh_worker = {
      sg          = "k8s-worker-sg"
      reference   = "bastion-sg"
      from_port   = 22
      to_port     = 22
      description = "SSH access"
    }
    api_server = {
      sg          = "k8s-master-sg"
      cidr_ipv4   = "0.0.0.0/0"
      from_port   = 6443
      to_port     = 6443
      description = "Kubernetes API server"
    }
    etcd = {
      sg          = "k8s-master-sg"
      reference   = "k8s-master-sg"
      from_port   = 2379
      to_port     = 2380
      description = "etcd server client API"
    }
    vxlan_master = {
      sg          = "k8s-master-sg"
      reference   = "k8s-master-sg"
      ip_protocol = "udp"
      from_port   = 8472
      to_port     = 8472
      description = "VXLAN overlay"
    }
    vxlan_master_to_worker = {
      sg          = "k8s-master-sg"
      reference   = "k8s-worker-sg"
      ip_protocol = "udp"
      from_port   = 8472
      to_port     = 8472
      description = "VXLAN overlay"
    }
    helth_check_master = {
      sg          = "k8s-master-sg"
      reference   = "k8s-master-sg"
      from_port   = 4240
      to_port     = 4240
      description = "health checks"
    }
    helth_check_master_to_worker = {
      sg          = "k8s-master-sg"
      reference   = "k8s-worker-sg"
      from_port   = 4240
      to_port     = 4240
      description = "health checks"
    }
    icmp_master = {
      sg          = "k8s-master-sg"
      reference   = "k8s-master-sg"
      ip_protocol = "icmp"
      from_port   = 8
      to_port     = 0
      description = "Allow ICMP echo requests from master nodes for health checks"
    }
    icmp_master_to_worker = {
      sg          = "k8s-master-sg"
      reference   = "k8s-worker-sg"
      ip_protocol = "icmp"
      from_port   = 8
      to_port     = 0
      description = "Allow ICMP echo requests from master to worker nodes for health checks"
    }
    kubelet = {
      sg          = "k8s-master-sg"
      reference   = "k8s-master-sg"
      from_port   = 10250
      to_port     = 10250
      description = "Kubelet API"
    }
    kubelet_master_to_worket = {
      sg          = "k8s-master-sg"
      reference   = "k8s-worker-sg"
      from_port   = 10250
      to_port     = 10250
      description = "Allow worker nodes to access control plane kubelet"
    }
    kube_scheduler = {
      sg          = "k8s-master-sg"
      reference   = "k8s-master-sg"
      from_port   = 10259
      to_port     = 10259
      description = "kube scheduler"
    }
    kube_ctl_manager_master = {
      sg          = "k8s-master-sg"
      reference   = "k8s-master-sg"
      from_port   = 10257
      to_port     = 10257
      description = "kube controller manager"
    }


    vxlan_worker = {
      sg          = "k8s-worker-sg"
      reference   = "k8s-worker-sg"
      ip_protocol = "udp"
      from_port   = 8472
      to_port     = 8472
      description = "VXLAN overlay"
    }
    vxlan_worker_to_master = {
      sg          = "k8s-worker-sg"
      reference   = "k8s-master-sg"
      ip_protocol = "udp"
      from_port   = 8472
      to_port     = 8472
      description = "VXLAN overlay"
    }
    helth_check_worker = {
      sg          = "k8s-worker-sg"
      reference   = "k8s-worker-sg"
      from_port   = 4240
      to_port     = 4240
      description = "health checks"
    }
    helth_check_worker_to_master = {
      sg          = "k8s-worker-sg"
      reference   = "k8s-master-sg"
      from_port   = 4240
      to_port     = 4240
      description = "health checks"
    }
    icmp_worker = {
      sg          = "k8s-worker-sg"
      reference   = "k8s-worker-sg"
      ip_protocol = "icmp"
      from_port   = 8
      to_port     = 0
      description = "Allow ICMP echo requests from worker nodes for health checks"
    }
    icmp_worker_to_master = {
      sg          = "k8s-worker-sg"
      reference   = "k8s-master-sg"
      ip_protocol = "icmp"
      from_port   = 8
      to_port     = 0
      description = "Allow ICMP echo requests from worker to master nodes for health checks"
    }
    kubelet_worker_self = {
      sg          = "k8s-worker-sg"
      reference   = "k8s-worker-sg"
      from_port   = 10250
      to_port     = 10250
      description = "Allow kubelet API from self"
    }
    kubelet_worker_to_master = {
      sg          = "k8s-worker-sg"
      reference   = "k8s-master-sg"
      from_port   = 10250
      to_port     = 10250
      description = "Allow kubelet API from control plane"
    }
    kube_ctl_manager_worker = {
      sg          = "k8s-worker-sg"
      reference   = "k8s-master-sg"
      from_port   = 10257
      to_port     = 10257
      description = "kube controller manager"
    }
    kube_proxy_self = {
      sg          = "k8s-worker-sg"
      reference   = "k8s-worker-sg"
      from_port   = 10256
      to_port     = 10256
      description = "kube proxy"
    }
    kube_proxy_lb = {
      sg          = "k8s-worker-sg"
      reference   = "lb-sg"
      from_port   = 10256
      to_port     = 10256
      description = "kube proxy"
    }
    node_pod = {
      sg          = "k8s-worker-sg"
      cidr_ipv4   = "0.0.0.0/0"
      from_port   = 30000
      to_port     = 32767
      description = "NodePort Services"
    }
  }
}
