
# Create a new key pair
#resource "aws_key_pair" "new_key_pair" {
#  key_name   = "my-keypair"
#  public_key = file("~/.ssh/my-keypair.pub") # Update with the path to your public key
#}

# Create a VPC
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"

 tags = {
    Name = "tvp-vpc"
  }
}
# Retrieve availability zones
data "aws_availability_zones" "available" {}

# Create public subnets
resource "aws_subnet" "tvp-public_subnet" {
  count                  = 1
  vpc_id                 = aws_vpc.my_vpc.id
  cidr_block             = "10.0.${count.index}.0/24"
  map_public_ip_on_launch = true
  availability_zone      = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "tvp-public subnets"
  }
}

# Create private subnets
resource "aws_subnet" "private_subnet" {
  count                  = 1
  vpc_id                 = aws_vpc.my_vpc.id
  cidr_block             = "10.0.${count.index + 2}.0/24"
  map_public_ip_on_launch = false
  availability_zone      = element(data.aws_availability_zones.available.names, count.index)
   tags = {
    Name = "tvp-private subnets"
  }

}
resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id
}

# Create a security group for the EC2 instance
resource "aws_security_group" "globalrelay_sg" {
  name        = "golbal-relay-security-group"
  description = "security group for EC2 instance"
  vpc_id      =  aws_vpc.my_vpc.id 

  # Allow SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    #cidr_blocks = [aws_subnet.public_subnet[0].cidr_block, aws_subnet.public_subnet[1].cidr_block]
  }
    ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  
    #cidr_blocks = [aws_subnet.public_subnet[0].cidr_block, aws_subnet.public_subnet[1].cidr_block]
  }

  // Egress rule (Allow all outbound traffic)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
   tags = {
    Name = "global-relay-security group"
  }
}

resource "tls_private_key" "oskey" {
  algorithm = "RSA"
}

resource "local_file" "myterrakey" {
  content  = tls_private_key.oskey.private_key_pem
  filename = "myterrakey.pem"
}

resource "aws_key_pair" "key121" {
  key_name   = "myterrakey"
  public_key = tls_private_key.oskey.public_key_openssh
}

resource "aws_instance" "my_instance" {
  ami           = lookup(var.AMIS, var.AWS_REGION)
  instance_type = "t2.micro"
  key_name      = aws_key_pair.key121.key_name
  subnet_id     = aws_subnet.tvp-public_subnet[0].id
  vpc_security_group_ids = [ "${aws_security_group.globalrelay_sg.id}" ]
  iam_instance_profile = aws_iam_instance_profile.globalrelay_s3_access_profile.name  # Adding IAM role to the instance
  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install -y \
                  apt-transport-https \
                  ca-certificates \
                  curl \
                  software-properties-common

              # Add Docker's official GPG key:
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

              # Add the Docker repository to Apt sources:
              sudo add-apt-repository \
                  "deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/ubuntu \
                  $(lsb_release -cs) \
                  stable" -y

              # Update the package index:
              sudo apt update -y

              # Install Docker:
              sudo apt install -y docker-ce

              # Add your user to the docker group:
              sudo usermod -aG docker $USER
              EOF
  tags = {
    Name = "global-relay"
  }
}

# Create two route tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.my_vpc.id
  tags = {
    Name = "tvp-public_route_table"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.my_vpc.id
   tags = {
    Name = "tvp-public_route_table"
  }
}

# Associate public subnets with the public route table
resource "aws_route_table_association" "public_route_table_association" {
  count          = 1
  subnet_id      = aws_subnet.tvp-public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
  
}

# Associate private subnets with the private route table
resource "aws_route_table_association" "private_route_table_association" {
  count          = 1
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table.id
  
}

# Create a NAT Gateway
resource "aws_nat_gateway" "my_nat_gateway" {
  allocation_id = aws_eip.my_eip.id
  subnet_id     = aws_subnet.tvp-public_subnet[0].id # Choose one of your public subnets
}

# Create a new Elastic IP address
resource "aws_eip" "my_eip" {
  vpc = true
}

# Update the route table for the private subnets to route internet-bound traffic through the NAT Gateway
resource "aws_route" "private_route_to_nat" {
  route_table_id            = aws_route_table.private_route_table.id
  destination_cidr_block    = "0.0.0.0/0"
  nat_gateway_id            = aws_nat_gateway.my_nat_gateway.id
}

# Update the route table for the public subnets to route internet-bound traffic directly
resource "aws_route" "public_route_to_internet" {
  route_table_id            = aws_route_table.public_route_table.id
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id                = aws_internet_gateway.my_igw.id
}

#output "instance_key_pair" {
#  value = aws_key_pair.myterrakey.key_name
#}

# S3 Bucket
resource "aws_s3_bucket" "global-relay_xml_files" {
  bucket = "global-relay-xml-files-demo"
}

# ECR Repository
resource "aws_ecr_repository" "global-relay" {
  name                 = "global-relay"
  image_scanning_configuration {
    scan_on_push = true
  }
  image_tag_mutability = "MUTABLE"
}

# IAM User
# IAM Instance Profile
resource "aws_iam_instance_profile" "globalrelay_s3_access_profile" {
  name = "globalrelay-s3-access-profile"
  role = aws_iam_role.globalrelay_s3_access_role.name
}
# IAM Role
resource "aws_iam_role" "globalrelay_s3_access_role" {
  name = "globalrelay-s3-access-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action    = "sts:AssumeRole"
    }]
  })
}


# Attach policies to the IAM role
resource "aws_iam_role_policy_attachment" "attach_s3_full_access" {
  role       = aws_iam_role.globalrelay_s3_access_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "attach_ecr_full_access" {
  role       = aws_iam_role.globalrelay_s3_access_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}
