resource "aws_security_group" "allow_ssh_sg" {
  name        = "allow_ssh_sg"
  description = "Allow TCP inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.vpc.id
}

resource "aws_vpc_security_group_ingress_rule" "allow_tcp_ipv4" {
  security_group_id = aws_security_group.allow_ssh_sg.id
  cidr_ipv4         = aws_subnet.subnet_public_1.cidr_block
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22

}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_ssh_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}
