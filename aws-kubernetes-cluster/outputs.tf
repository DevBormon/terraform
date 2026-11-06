output "basion_host_public_ip" {
  value = aws_instance.instances["bastion_host"].public_ip
}
output "master_private_ip" {
  value = aws_instance.instances["master"].private_ip
}
output "workar_1_private_ip" {
  value = aws_instance.instances["worker-1"].private_ip
}

output "current_region" {
  value = data.aws_region.current.region
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "ami_root_device_name" {
  value = data.aws_ami.selected.root_device_name
}

output "oidc_connect_url" {
  value = "https://${aws_s3_bucket.k8s_bucket.bucket}.s3.${data.aws_region.current.region}.amazonaws.com/.well-known/openid-configuration"
}

output "oidc_jwks" {
  value = "https://${aws_s3_bucket.k8s_bucket.bucket}.s3.${data.aws_region.current.region}.amazonaws.com/openid/v1/jwks"
}