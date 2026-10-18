output "basion_host_public_ip" {
  value = aws_instance.instances["basion_host"].public_ip
}
output "master_private_ip" {
  value = aws_instance.instances["master"].private_ip
}
output "workar_1_private_ip" {
  value = aws_instance.instances["worker-1"].private_ip
}
output "workar_2_private_ip" {
  value = aws_instance.instances["worker-2"].private_ip
}
