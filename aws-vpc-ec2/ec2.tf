locals {
  common = {
    vpc_security_group_ids = [aws_security_group.bormon_sg.id]
    key_name               = "aws-login"
  }

  k8s_config = {
    instance_type               = "c7i-flex.large"
    associate_public_ip_address = false
  }
  instances = {
    basion_host = merge(local.common, {
      "instance_type"               = "t3.micro"
      "subnet_id"                   = aws_subnet.subnet_public_1.id
      "associate_public_ip_address" = true
    })
    master = merge(
      local.common, local.k8s_config,
      {
        "subnet_id" = aws_subnet.subnet_private_1.id
      }
    )
    worker-1 = merge(
      local.common, local.k8s_config,
      {
        "subnet_id" = aws_subnet.subnet_private_1.id
      }
    )
    worker-2 = merge(
      local.common, local.k8s_config,
      {
        "subnet_id" = aws_subnet.subnet_private_2.id
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

  tags = {
    Name = each.key
  }
}

resource "terraform_data" "upload_pem" {
  depends_on = [aws_instance.instances["basion_host"]]
  connection {
    type        = "ssh"
    host        = aws_instance.instances["basion_host"].public_ip
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



