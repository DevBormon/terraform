resource "aws_security_group" "bormon_sg" {
  name        = "bormon_sg"
  description = "Allow TCP inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.vpc.id
}

locals {
  cidr_common = {
    cidr_ipv4 = "0.0.0.0/0"
  }
  k8s_ports = {
    ssh = merge(local.cidr_common, {
      from_port   = 22
      to_port     = 22
      description = "SSH access"
    })
    api_server = merge(local.cidr_common, {
      from_port   = 6443
      to_port     = 6443
      description = "Kubernetes API server"
    })
    etcd = merge(local.cidr_common, {
      from_port   = 2379
      to_port     = 2380
      description = "etcd server client API"
    })
    kubelet = merge(local.cidr_common, {
      from_port   = 10250
      to_port     = 10250
      description = "Kubelet API"
    })
    kube_scheduler = merge(local.cidr_common, {
      from_port   = 10259
      to_port     = 10259
      description = "kube scheduler"
    })
    kube_controller_manager = merge(local.cidr_common, {
      from_port   = 10257
      to_port     = 10257
      description = "kube controller manager"
    })

    kube_proxy = merge(local.cidr_common, {
      from_port   = 10256
      to_port     = 10256
      description = "kube proxy"
    })
    kube_proxy = merge(local.cidr_common, {
      from_port   = 30000
      to_port     = 32767
      description = "NodePort Services"
    })
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_tcp_ipv4" {
  for_each = local.k8s_ports

  security_group_id = aws_security_group.bormon_sg.id
  cidr_ipv4         = each.value.cidr_ipv4
  from_port         = each.value.from_port
  ip_protocol       = "tcp"
  to_port           = each.value.to_port
  description       = each.value.description

}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.bormon_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}
