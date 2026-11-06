resource "aws_security_group" "my_sg" {
  for_each = toset(["bastion-sg", "lb-sg", "k8s-master-sg", "k8s-worker-sg"])

  name        = each.key
  description = "Security group for ${each.key}"
  vpc_id      = aws_vpc.vpc.id
}

resource "aws_vpc_security_group_ingress_rule" "allow_tcp_ipv4" {
  for_each = local.k8s_ports

  security_group_id            = aws_security_group.my_sg[each.value.sg].id
  referenced_security_group_id = try(aws_security_group.my_sg[each.value.reference].id, null)
  cidr_ipv4                    = try(each.value.cidr_ipv4, null)
  ip_protocol                  = try(each.value.ip_protocol, "tcp")
  from_port                    = try(each.value.from_port, null)
  to_port                      = try(each.value.to_port, null)
  description                  = try(each.value.description, null)

}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  for_each = toset(["bastion-sg", "lb-sg", "k8s-master-sg", "k8s-worker-sg"])

  security_group_id = aws_security_group.my_sg[each.key].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}
