resource "aws_security_group" "bormon_sg" {
  for_each = toset(["bastion-sg", "lb-sg", "k8s-master-sg", "k8s-worker-sg"])

  name        = each.key
  description = "Security group for ${each.key}"
  vpc_id      = aws_vpc.vpc.id
}


locals {
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

resource "aws_vpc_security_group_ingress_rule" "allow_tcp_ipv4" {
  for_each = local.k8s_ports

  security_group_id            = aws_security_group.bormon_sg[each.value.sg].id
  referenced_security_group_id = try(aws_security_group.bormon_sg[each.value.reference].id, null)
  cidr_ipv4                    = try(each.value.cidr_ipv4, null)
  ip_protocol                  = try(each.value.ip_protocol, "tcp")
  from_port                    = try(each.value.from_port, null)
  to_port                      = try(each.value.to_port, null)
  description                  = try(each.value.description, null)

}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  for_each = toset(["bastion-sg", "lb-sg", "k8s-master-sg", "k8s-worker-sg"])

  security_group_id = aws_security_group.bormon_sg[each.key].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}
