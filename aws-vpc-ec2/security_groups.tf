resource "aws_security_group" "bormon_sg" {
  for_each = toset(["bastion-sg", "lb-sg", "k8s-master-sg", "k8s-workar-sg"])

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
    ssh_bastion = {
      sg          = "bastion-sg"
      cidr_ipv4   = "0.0.0.0/0"
      from_port   = 22
      to_port     = 22
      description = "SSH access"
    }
    ssh_master = {
      sg          = "k8s-master-sg"
      cidr_ipv4   = "0.0.0.0/0"
      from_port   = 22
      to_port     = 22
      description = "SSH access"
    }
    ssh_workar = {
      sg          = "k8s-workar-sg"
      cidr_ipv4   = "0.0.0.0/0"
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

    kube_ctl_manager_workar = {
      sg          = "k8s-workar-sg"
      reference   = "k8s-master-sg"
      from_port   = 10257
      to_port     = 10257
      description = "kube controller manager"
    }
    kube_proxy_self = {
      sg          = "k8s-workar-sg"
      reference   = "k8s-workar-sg"
      from_port   = 10256
      to_port     = 10256
      description = "kube proxy"
    }
    kube_proxy_lb = {
      sg          = "k8s-workar-sg"
      reference   = "lb-sg"
      from_port   = 10256
      to_port     = 10256
      description = "kube proxy"
    }
    node_pod = {
      sg          = "k8s-workar-sg"
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
  for_each = toset(["bastion-sg", "lb-sg", "k8s-master-sg", "k8s-workar-sg"])

  security_group_id = aws_security_group.bormon_sg[each.key].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}
