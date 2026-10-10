resource "aws_instance" "basion_host" {
  ami = "ami-0199ac7c9fbf9ed83"
  instance_type = "t3.micro"
  subnet_id = aws_subnet.subnet_public_1.id
  tags = {
    Name = "basion-host"
  }
}