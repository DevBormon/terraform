output "public_ip" {
  description = "Public ip for EC2 Instance"
  value = aws_instance.basion_host.public_ip
}

output "instance_url" {
  description = "The URL to access the server"
  value = "https://${aws_instance.basion_host.public_ip}"
}