locals {
  common = {
    key_name = "aws-login"
  }

  k8s_config = {
    instance_type               = "c7i-flex.large"
    associate_public_ip_address = false
    volume_size                 = 8
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
        vpc_security_group_ids = [aws_security_group.bormon_sg["k8s-worker-sg"].id]
      }
    )
    worker-2 = merge(
      local.common, local.k8s_config,
      {
        subnet_id              = aws_subnet.subnet_private_2.id
        vpc_security_group_ids = [aws_security_group.bormon_sg["k8s-worker-sg"].id]
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

# master, worker-1 & worker-2 have private IP addresses and no NAT gateway is configured. Therefore, we need to set up a proxy server to provide internet access to these nodes

#Iinstalling the Squid proxy server | default port 3128
resource "terraform_data" "install_squid" {
  depends_on = [
    aws_instance.instances["bastion_host"]
  ]
  connection {
    type        = "ssh"
    host        = aws_instance.instances["bastion_host"].public_ip
    user        = "ubuntu"
    private_key = file("/home/bormon/.ssh/aws-login.pem")
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
      "sudo apt install squid -y",
      "sudo systemctl enable --now squid",

      # Remove any previous attempts if they exist to avoid duplicates
      "sudo sed -i '/my-vpc/d' /etc/squid/squid.conf",

      # 1. Insert the ACL and allow rules at the very top of squid.conf
      "sudo sed -i '1i acl my-vpc src ${aws_vpc.vpc.cidr_block}' /etc/squid/squid.conf",
      "sudo sed -i '2i http_access allow my-vpc' /etc/squid/squid.conf",

      "echo 'http_access deny all' | sudo tee -a /etc/squid/squid.conf",
      "sudo systemctl restart squid"
    ]
  }
}

# Update APT Config for access internet throw proxy
resource "terraform_data" "configure_squid" {
  for_each = toset(["master", "worker-1", "worker-2"])

  depends_on = [
    terraform_data.install_squid
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
      "echo 'Acquire::http::Proxy \"http://${aws_instance.instances["bastion_host"].private_ip}:3128/\";' | sudo tee /etc/apt/apt.conf.d/80proxy",
      "echo 'Acquire::https::Proxy \"http://${aws_instance.instances["bastion_host"].private_ip}:3128/\";' | sudo tee -a /etc/apt/apt.conf.d/80proxy"
    ]
  }
}

resource "terraform_data" "k8s_containerd_installation" {
  for_each = toset(["master", "worker-1", "worker-2"])

  depends_on = [
    terraform_data.configure_squid
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

  provisioner "file" {
    source      = "${path.module}/k8s_setup_v_1.37"
    destination = "/home/ubuntu/k8s_setup_v_1.37"
  }

  provisioner "remote-exec" {
    inline = [
      "bash /home/ubuntu/k8s_setup_v_1.37/containerd.sh"
    ]
  }
}

# Configure Containerd Proxy (Required for kubeadm init and pull for workload images)
resource "terraform_data" "configure_containerd_proxy" {
  for_each = toset(["master", "worker-1", "worker-2"])

  depends_on = [
    terraform_data.k8s_containerd_installation
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

      "sudo mkdir -p /etc/systemd/system/containerd.service.d",
      "echo '[Service]' | sudo tee /etc/systemd/system/containerd.service.d/http-proxy.conf",

      "echo 'Environment=\"HTTP_PROXY=http://${aws_instance.instances["bastion_host"].private_ip}:3128\"' | sudo tee -a /etc/systemd/system/containerd.service.d/http-proxy.conf",

      "echo 'Environment=\"HTTPS_PROXY=http://${aws_instance.instances["bastion_host"].private_ip}:3128\"' | sudo tee -a /etc/systemd/system/containerd.service.d/http-proxy.conf",

      "echo 'Environment=\"NO_PROXY=localhost,127.0.0.1,.svc,.cluster.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16\"' | sudo tee -a /etc/systemd/system/containerd.service.d/http-proxy.conf",

      # 3. Reload and restart containerd
      "sudo systemctl daemon-reload",
      "sudo systemctl restart containerd"
    ]
  }
}

resource "terraform_data" "k8s_kubes_installation" {
  for_each = toset(["master", "worker-1", "worker-2"])

  depends_on = [
    terraform_data.k8s_containerd_installation
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
      "bash /home/ubuntu/k8s_setup_v_1.37/kubeadm_kubelet_kubectl.sh ${aws_instance.instances["bastion_host"].private_ip}"
    ]
  }
}

resource "terraform_data" "kubeadm_init" {

  depends_on = [
    terraform_data.k8s_kubes_installation,
    terraform_data.configure_containerd_proxy
  ]

  connection {
    type        = "ssh"
    host        = aws_instance.instances["master"].private_ip
    user        = "ubuntu"
    private_key = file("/home/bormon/.ssh/aws-login.pem")

    bastion_host        = aws_instance.instances["bastion_host"].public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file("/home/bormon/.ssh/aws-login.pem")
  }

  provisioner "remote-exec" {
    inline = [
      "sudo kubeadm init --node-name=master",
      "bash /home/ubuntu/k8s_setup_v_1.37/kubectl_without_sudo.sh"
    ]
  }
}

resource "terraform_data" "cilium_installation" {

  depends_on = [terraform_data.kubeadm_init]

  connection {
    type        = "ssh"
    host        = aws_instance.instances["master"].private_ip
    user        = "ubuntu"
    private_key = file("/home/bormon/.ssh/aws-login.pem")

    bastion_host        = aws_instance.instances["bastion_host"].public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file("/home/bormon/.ssh/aws-login.pem")
  }

  provisioner "remote-exec" {
    inline = [
      "bash /home/ubuntu/k8s_setup_v_1.37/cilium_install.sh"
    ]
  }
}
