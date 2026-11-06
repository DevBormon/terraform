# Configure the AWS VPC
resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "k8s-vpc"
  }
}

# Configure the AWS igw
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "k8s-igw"
  }
}

# Configure the AWS subnet
resource "aws_subnet" "subnet_public_1" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.0.0/20"
  availability_zone = "ap-south-2a"
  tags = {
    Name = "k8s-subnet-public-1-ap-south-2a"
  }
}

resource "aws_subnet" "subnet_public_2" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.16.0/20"
  availability_zone = "ap-south-2b"
  tags = {
    Name = "k8s-subnet-public-2-ap-south-2b"
  }
}

resource "aws_subnet" "subnet_private_1" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.128.0/20"
  availability_zone = "ap-south-2a"
  tags = {
    Name = "k8s-subnet-private-1-ap-south-2a"
  }
}

resource "aws_subnet" "subnet_private_2" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.144.0/20"
  availability_zone = "ap-south-2b"
  tags = {
    Name = "k8s-subnet-private-2-ap-south-2b"
  }
}

resource "aws_route_table" "route_table_public" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "k8s-rtb-public"
  }
}

resource "aws_route_table" "route_table_private_1" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "k8s-rtb-private-1-ap-south-2a"
  }
}

resource "aws_route_table" "route_table_private_2" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "k8s-rtb-private-1-ap-south-2b"
  }
}

resource "aws_route_table_association" "table_associate_public_1" {
  subnet_id      = aws_subnet.subnet_public_1.id
  route_table_id = aws_route_table.route_table_public.id
}
resource "aws_route_table_association" "table_associate_public_2" {
  subnet_id      = aws_subnet.subnet_public_2.id
  route_table_id = aws_route_table.route_table_public.id
}

resource "aws_route_table_association" "table_associate_private_1" {
  subnet_id      = aws_subnet.subnet_private_1.id
  route_table_id = aws_route_table.route_table_private_1.id
}

resource "aws_route_table_association" "table_associate_private_2" {
  subnet_id      = aws_subnet.subnet_private_2.id
  route_table_id = aws_route_table.route_table_private_2.id
}