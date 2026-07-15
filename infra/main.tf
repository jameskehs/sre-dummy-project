// TODO: Create VPC with two subnets.
resource "aws_vpc" "app_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name    = "SRE-DUMMY-APP-VPC"
    Project = "SRE Dummy App"
  }
}

// TODO: Create subnets in different availability zones
resource "aws_subnet" "app_subnet_1" {
  vpc_id            = aws_vpc.app_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  map_public_ip_on_launch = true

  tags = {
    Name    = "SRE-DUMMY-APP-SUBNET-1"
    Project = "SRE Dummy App"
  }
}

resource "aws_subnet" "app_subnet_2" {
  vpc_id            = aws_vpc.app_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  map_public_ip_on_launch = true

  tags = {
    Name    = "SRE-DUMMY-APP-SUBNET-2"
    Project = "SRE Dummy App"
  }
}

// TODO: Create a load balancer to distribute traffic to 
// instances of the application in both subnets
resource "aws_lb" "app_lb" {
  name               = "app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_http.id]
  subnets            = [aws_subnet.app_subnet_1.id, aws_subnet.app_subnet_2.id]

  tags = {
    Name    = "SRE-DUMMY-APP-LB"
    Project = "SRE Dummy App"
  }
}

resource "aws_lb_target_group" "app_target_group" {
  name        = "app-target-group"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.app_vpc.id
  target_type = "instance"

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name    = "SRE-DUMMY-APP-TARGET-GROUP"
    Project = "SRE Dummy App"
  }
}

resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_target_group.arn
  }
}

resource "aws_security_group" "allow_http" {
  name        = "app-lb-sg"
  description = "Security group for the application load balancer"
  vpc_id      = aws_vpc.app_vpc.id

  tags = {
    Name    = "SRE-DUMMY-APP-allow_http"
    Project = "SRE Dummy App"

  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_rule" {
  security_group_id = aws_security_group.allow_http.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "tcp"
  from_port   = 80
  to_port     = 80

  tags = {
    Name    = "SRE-DUMMY-APP-allow_http"
    Project = "SRE Dummy App"
  }
}

resource "aws_vpc_security_group_egress_rule" "allow_http_egress_rule" {
  security_group_id            = aws_security_group.allow_http.id
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
  referenced_security_group_id = aws_security_group.app_instance_sg.id
}


resource "aws_internet_gateway" "app_igw" {
  vpc_id = aws_vpc.app_vpc.id

  tags = {
    Name    = "SRE-DUMMY-APP-IGW"
    Project = "SRE Dummy App"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.app_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app_igw.id
  }
}
resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.app_subnet_1.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.app_subnet_2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_launch_template" "app_launch_template" {
  name          = "app-launch-template"
  instance_type = "t3.micro"
  image_id      = "ami-0b6d9d3d33ba97d99"

  vpc_security_group_ids = [aws_security_group.app_instance_sg.id]

  user_data = base64encode(file("${path.module}/boot.sh"))

  tags = {
    Name    = "SRE-DUMMY-APP-LAUNCH-TEMPLATE"
    Project = "SRE Dummy App"
  }
}

resource "aws_security_group" "app_instance_sg" {
  name        = "app-ec2-sg"
  description = "Security group for the application instances"
  vpc_id      = aws_vpc.app_vpc.id

  tags = {
    Name    = "SRE-DUMMY-APP-INSTANCE-SG"
    Project = "SRE Dummy App"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_instance_ingress_rule" {
  security_group_id = aws_security_group.app_instance_sg.id

  referenced_security_group_id = aws_security_group.allow_http.id
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000

  tags = {
    Name    = "SRE-DUMMY-APP-INSTANCE-INGRESS-RULE"
    Project = "SRE Dummy App"
  }
}

resource "aws_vpc_security_group_egress_rule" "app_instance_egress_rule" {
  security_group_id = aws_security_group.app_instance_sg.id
  
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = {
    Name    = "SRE-DUMMY-APP-INSTANCE-EGRESS-RULE"
    Project = "SRE Dummy App"
  }
}
