locals {
  common = {
    key_name = "aws-login"
  }

  k8s_config = {
    instance_type               = "c7i-flex.large"
    associate_public_ip_address = false
    volume_size                 = 10
    volume_type                 = "gp3"
  }
  instances = {
    bastion_host = merge(local.common, {
      instance_type               = "t3.micro"
      subnet_id                   = aws_subnet.subnet_public_1.id
      vpc_security_group_ids      = [aws_security_group.bormon_sg["bastion-sg"].id]
      associate_public_ip_address = true
      volume_size                 = 8
      volume_type                 = "gp3"
    })
    master = merge(
      local.common, local.k8s_config,
      {
        subnet_id              = aws_subnet.subnet_private_1.id
        vpc_security_group_ids = [aws_security_group.bormon_sg["k8s-master-sg"].id]
      }
    )
    worker-1 = merge(
      local.common, local.k8s_config,
      {
        subnet_id              = aws_subnet.subnet_private_1.id
        vpc_security_group_ids = [aws_security_group.bormon_sg["k8s-workar-sg"].id]
      }
    )
    worker-2 = merge(
      local.common, local.k8s_config,
      {
        subnet_id              = aws_subnet.subnet_private_2.id
        vpc_security_group_ids = [aws_security_group.bormon_sg["k8s-workar-sg"].id]
      }
    )
  }
}

resource "aws_instance" "instances" {
  for_each                    = local.instances
  ami                         = "ami-0199ac7c9fbf9ed83"
  instance_type               = each.value.instance_type
  subnet_id                   = each.value.subnet_id
  vpc_security_group_ids      = each.value.vpc_security_group_ids
  associate_public_ip_address = each.value.associate_public_ip_address
  key_name                    = each.value.key_name
  root_block_device {
    volume_size = each.value.volume_size
    volume_type = each.value.volume_type
  }
  tags = {
    Name = each.key
  }
}

resource "terraform_data" "upload_pem" {
  depends_on = [aws_instance.instances["bastion_host"]]
  connection {
    type        = "ssh"
    host        = aws_instance.instances["bastion_host"].public_ip
    user        = "ubuntu"
    private_key = file("/home/bormon/.ssh/aws-login.pem")
  }

  provisioner "file" {
    source      = "/home/bormon/.ssh/aws-login.pem"
    destination = "/home/ubuntu/.ssh/aws-login.pem"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 400 /home/ubuntu/.ssh/aws-login.pem"
    ]
  }
}

resource "terraform_data" "edit_hosts" {
  for_each = toset(["master", "worker-1", "worker-2"])

  depends_on = [
    terraform_data.upload_pem,
    aws_instance.instances["master"],
    aws_instance.instances["worker-1"],
    aws_instance.instances["worker-2"]
  ]
  connection {
    type        = "ssh"
    host        = aws_instance.instances[each.key].private_ip
    user        = "ubuntu"
    private_key = file("/home/bormon/.ssh/aws-login.pem")

    bastion_host        = aws_instance.instances["bastion_host"].public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file("/home/bormon/.ssh/aws-login.pem")
  }
  provisioner "remote-exec" {
    inline = [
      "sudo sed -i '/master$/d; /workar1$/d; /workar2$/d' /etc/hosts",
      "echo '${aws_instance.instances["master"].private_ip} master' | sudo tee -a /etc/hosts",
      "echo '${aws_instance.instances["worker-1"].private_ip} workar1' | sudo tee -a /etc/hosts",
      "echo '${aws_instance.instances["worker-2"].private_ip} workar2' | sudo tee -a /etc/hosts"
    ]
  }
}
