terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.49.0"
    }
  }
  required_version = ">= 1.1.0"
}

# Configure the AWS Provider
provider "aws" {
  region = var.region
}

resource "aws_vpc" "main" {
  cidr_block = var.cidr_block

  tags = var.tags
}

resource "aws_subnet" "public_subnets" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = element(var.public_subnet_cidrs, count.index)
  availability_zone       = element(var.azs, count.index)
  map_public_ip_on_launch = "true"

  tags = {
    Name = "myweb-subnet-public-${element(var.azs, count.index + 1)}"
  }
}

resource "aws_subnet" "private_subnets" {
  count                   = length(var.private_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = element(var.private_subnet_cidrs, count.index)
  availability_zone       = element(var.azs, count.index)
  map_public_ip_on_launch = "false"

  tags = {
    Name = "myweb-subnet-private-${element(var.azs, count.index + 1)}"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "myweb-IGW"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "myweb-rtb-public"
  }
}

resource "aws_route_table_association" "associate_public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = element(aws_subnet.public_subnets[*].id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "myweb-instance-SG" {
  name        = "sever-SG"
  description = "allow inbound/outbound traffic for the webservers"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "allow inbound HTTPS/TLS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "allow inbound HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "allow inbound SSH traffic"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "myweb-instance_SG"
  }
}

resource "aws_instance" "myweb-instance" {
  count                       = length(var.public_subnet_cidrs)
  ami                         = var.ami
  instance_type               = "t2.micro"
  associate_public_ip_address = true
  user_data                   = file("script.sh")
  key_name                    = "TerraformKeys"
  vpc_security_group_ids      = [aws_security_group.myweb-instance-SG.id]
  subnet_id                   = element(aws_subnet.public_subnets[*].id, count.index)


  tags = {
    Name = "myweb-instance-a${count.index + 1}"
  }

}

resource "aws_security_group" "myweb-instance_lb_SG" {
  name        = "myweb-instance-lb-sg"
  description = "Allow inbound/oubound traffic for the load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "allow inbound HTTPS/TLS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "allow inbound HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lb-sg"
  }
}

resource "aws_lb" "myweb-instance_lb" {
  name               = "myweb-instance-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.myweb-instance_lb_SG.id]
  subnets            = aws_subnet.public_subnets[*].id

}

resource "aws_lb_target_group" "myweb-instance_lb_TG" {
  name     = "myweb-instance-lb-TG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.myweb-instance_lb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:us-east-1:625319181025:certificate/c864f8b5-2a8b-4b49-894c-8d19b7311f23"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.myweb-instance_lb_TG.arn
  }
}

resource "aws_lb_target_group_attachment" "myweb-instance_lb_TG_ATT" {
  count            = length(var.public_subnet_cidrs)
  target_group_arn = aws_lb_target_group.myweb-instance_lb_TG.arn
  target_id        = element(aws_instance.myweb-instance[*].id, count.index)
  port             = 80
}

data "aws_route53_zone" "zone" {
  zone_id      = var.zone_id
  private_zone = false
}

resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = "terraform-test.bleuche.online"
  type    = "A"
  allow_overwrite = true

  alias {
    name                   = aws_lb.myweb-instance_lb.dns_name
    zone_id                = aws_lb.myweb-instance_lb.zone_id
    evaluate_target_health = false
  }
}


# inventory file 
resource "local_file" "ip_output" {
  content  = <<EOT
  [all]
  ${aws_instance.myweb-instance.*.public_ip[0]}
  ${aws_instance.myweb-instance.*.public_ip[1]}
  ${aws_instance.myweb-instance.*.public_ip[2]}
  [all:vars]
  ansible_user=ubuntu
  ansible_ssh_private_key_file=../ansible/TerraformKeys.pem
  ansible_ssh_common_args='-o StrictHostKeyChecking=no'
  EOT
  
  filename = "../ansible/host-inventory"
  directory_permission = "777"
  file_permission = "777"

  provisioner "local-exec" {
    command = "ansible-playbook -i ../ansible/host-inventory ../ansible/playbook.yml"
  }
}
