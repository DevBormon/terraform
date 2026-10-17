resource "aws_instance" "basion_host" {
  ami           = "ami-0199ac7c9fbf9ed83"
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.subnet_public_1.id
  vpc_security_group_ids = [ aws_security_group.allow_ssh_sg.id ]
  associate_public_ip_address = true
  key_name = "aws-login"
  tags = {
    Name = "basion-host"
  }

  user_data = <<-EOF
    #!/bin/bash
    scp -i .ssh/aws-login.pem .ssh/aws-login.pem DevBormon@ec2-public-ip:.ssh/
    EOF

}
