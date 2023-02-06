provider "aws" {
  region = "us-east-1"
  access_key = var.access_key
  secret_key = var.secret_key
}

# Create VPC
resource "aws_vpc" "Terraform_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "Terraform_vpc"
  }
}

# Create Internet Gateway

resource "aws_internet_gateway" "Terraform_internet_gateway" {
  vpc_id = aws_vpc.Terraform_vpc.id
  tags = {
    Name = "Terraform_internet_gateway"
  }
}

# Create public Route Table
resource "aws_route_table" "Terraform-route-table-public" {
  vpc_id = aws_vpc.Terraform_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.Terraform_internet_gateway.id
  }
  tags = {
    Name = "Terraform-route-table-public"
  }
}

# Associate public subnet 1 with public route table
resource "aws_route_table_association" "Terraform-public-subnet1-association" {
  subnet_id      = aws_subnet.Terraform-public-subnet1.id
  route_table_id = aws_route_table.Terraform-route-table-public.id
}

# Associate public subnet 2 with public route table
resource "aws_route_table_association" "Terraform-public-subnet2-association" {
  subnet_id      = aws_subnet.Terraform-public-subnet2.id
  route_table_id = aws_route_table.Terraform-route-table-public.id
}


# Create Public Subnet-1
resource "aws_subnet" "Terraform-public-subnet1" {
  vpc_id                  = aws_vpc.Terraform_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags = {
    Name = "Terraform-public-subnet1"
  }
}
# Create Public Subnet-2
resource "aws_subnet" "Terraform-public-subnet2" {
  vpc_id                  = aws_vpc.Terraform_vpc.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1b"
  tags = {
    Name = "Terraform-public-subnet2"
  }
}


# Create a security group for the load balancer
resource "aws_security_group" "Terraform-load_balancer_sg" {
  name        = "Terraform-load-balancer-sg"
  description = "Security group for the load balancer"
  vpc_id      = aws_vpc.Terraform_vpc.id
  
   ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    
  }
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create Security Group to allow port ssh, http and https
resource "aws_security_group" "Terraform-security-grp-rule" {
  name        = "allow_ssh_http_https"
  description = "Allow SSH, HTTP and HTTPS inbound traffic for private instances"
  vpc_id      = aws_vpc.Terraform_vpc.id

 ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    security_groups = [aws_security_group.Terraform-load_balancer_sg.id]
  }

 ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    security_groups = [aws_security_group.Terraform-load_balancer_sg.id]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
   
  }
  tags = {
    Name = "Terraform-security-grp-rule"
  }
}


# creating First Instance
resource "aws_instance" "Terraform1" {
  ami             = "ami-00874d747dde814fa"
  instance_type   = "t2.micro"
  key_name        = "TerraformKeys"
  security_groups = [aws_security_group.Terraform-security-grp-rule.id]
  subnet_id       = aws_subnet.Terraform-public-subnet1.id
  availability_zone = "us-east-1a"
  tags = {
    Name   = "Terraform-1"
    source = "Terraform"
  }
}
# creating Second Instance
 resource "aws_instance" "Terraform2" {
  ami             = "ami-00874d747dde814fa"
  instance_type   = "t2.micro"
  key_name        = "TerraformKeys"
  security_groups = [aws_security_group.Terraform-security-grp-rule.id]
  subnet_id       = aws_subnet.Terraform-public-subnet2.id
  availability_zone = "us-east-1b"
  tags = {
    Name   = "Terraform-2"
    source = "Terraform"
  }
}

# creating Third Instance
resource "aws_instance" "Terraform3" {
  ami             = "ami-00874d747dde814fa"
  instance_type   = "t2.micro"
  key_name        = "TerraformKeys"
  security_groups = [aws_security_group.Terraform-security-grp-rule.id]
  subnet_id       = aws_subnet.Terraform-public-subnet1.id
  availability_zone = "us-east-1a"
  tags = {
    Name   = "Terraform-3"
    source = "Terraform"
  }
}


# Create a file to store the IP addresses of the instances
resource "local_file" "Ip_address" {
  filename = "/vagrant/terraform/host-inventory"
  content  = <<EOT
${aws_instance.Terraform1.public_ip}
${aws_instance.Terraform2.public_ip}
${aws_instance.Terraform3.public_ip}
  EOT
}


# Create an Application Load Balancer
resource "aws_lb" "Terraform-load-balancer" {
  name               = "Terraform-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.Terraform-load_balancer_sg.id]
  subnets            = [aws_subnet.Terraform-public-subnet1.id, aws_subnet.Terraform-public-subnet2.id]
 #enable_cross_zone_load_balancing = true
  enable_deletion_protection = false
  depends_on                 = [aws_instance.Terraform1, aws_instance.Terraform2, aws_instance.Terraform3]
}


# Create target group
resource "aws_lb_target_group" "Terraform-target-group" {
  name     = "Terraform-target-group"
  target_type = "instance"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.Terraform_vpc.id
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

# Create the listener
resource "aws_lb_listener" "Terraform-listener" {
  load_balancer_arn = aws_lb.Terraform-load-balancer.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.Terraform-target-group.arn
  }
}
# Create the AWS Lb listener rule
resource "aws_lb_listener_rule" "Terraform-listener-rule" {
  listener_arn = aws_lb_listener.Terraform-listener.arn
  priority     = 1
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.Terraform-target-group.arn
  }
  condition {
    path_pattern {
      values = ["/"]
    }
  }
}


# Attach the target group to the load balancer
resource "aws_lb_target_group_attachment" "Terraform-target-group-attachment1" {
  target_group_arn = aws_lb_target_group.Terraform-target-group.arn
  target_id        = aws_instance.Terraform1.id
  port             = 80
}
resource "aws_lb_target_group_attachment" "Terraform-target-group-attachment2" {
  target_group_arn = aws_lb_target_group.Terraform-target-group.arn
  target_id        = aws_instance.Terraform2.id
  port             = 80
}
resource "aws_lb_target_group_attachment" "Terraform-target-group-attachment3" {
  target_group_arn = aws_lb_target_group.Terraform-target-group.arn
  target_id        = aws_instance.Terraform3.id
  port             = 80 
 
}

   
