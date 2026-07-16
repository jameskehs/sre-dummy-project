resource "aws_vpc" "app_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "SRE-DUMMY-APP-VPC"
  }
}

resource "aws_subnet" "app_subnet_1" {
  vpc_id            = aws_vpc.app_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  map_public_ip_on_launch = true

  tags = {
    Name = "SRE-DUMMY-APP-SUBNET-1"
  }
}

resource "aws_subnet" "app_subnet_2" {
  vpc_id            = aws_vpc.app_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  map_public_ip_on_launch = true

  tags = {
    Name = "SRE-DUMMY-APP-SUBNET-2"
  }
}

resource "aws_lb" "app_lb" {
  name               = "app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_http.id]
  subnets            = [aws_subnet.app_subnet_1.id, aws_subnet.app_subnet_2.id]

  tags = {
    Name = "SRE-DUMMY-APP-LB"
  }
}

resource "aws_lb_target_group" "app_target_group" {
  name        = "app-target-group"
  port        = var.app_port
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
    Name = "SRE-DUMMY-APP-TARGET-GROUP"
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
    Name = "SRE-DUMMY-APP-allow_http"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_rule" {
  security_group_id = aws_security_group.allow_http.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "tcp"
  from_port   = 80
  to_port     = 80

  tags = {
    Name = "SRE-DUMMY-APP-allow_http"
  }
}

resource "aws_vpc_security_group_egress_rule" "allow_http_egress_rule" {
  security_group_id            = aws_security_group.allow_http.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.app_instance_sg.id
}


resource "aws_internet_gateway" "app_igw" {
  vpc_id = aws_vpc.app_vpc.id

  tags = {
    Name = "SRE-DUMMY-APP-IGW"
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
  instance_type = var.instance_type
  image_id      = data.aws_ami.ubuntu.id
  iam_instance_profile {
    name = aws_iam_instance_profile.app_instance_profile.name
  }

  vpc_security_group_ids = [aws_security_group.app_instance_sg.id]

  user_data = base64encode(file("${path.module}/boot.sh"))

  tags = {
    Name = "SRE-DUMMY-APP-LAUNCH-TEMPLATE"
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "SRE-DUMMY-APP-INSTANCE"
    }
  }
}

resource "aws_security_group" "app_instance_sg" {
  name        = "app-ec2-sg"
  description = "Security group for the application instances"
  vpc_id      = aws_vpc.app_vpc.id

  tags = {
    Name = "SRE-DUMMY-APP-INSTANCE-SG"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_instance_ingress_rule" {
  security_group_id = aws_security_group.app_instance_sg.id

  referenced_security_group_id = aws_security_group.allow_http.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port

  tags = {
    Name = "SRE-DUMMY-APP-INSTANCE-INGRESS-RULE"
  }
}

resource "aws_vpc_security_group_egress_rule" "app_instance_egress_rule" {
  security_group_id = aws_security_group.app_instance_sg.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"

  tags = {
    Name = "SRE-DUMMY-APP-INSTANCE-EGRESS-RULE"
  }
}

resource "aws_autoscaling_group" "app_asg" {
  name             = "app-asg"
  desired_capacity = 2
  min_size         = var.asg_min_size
  max_size         = var.asg_max_size

  vpc_zone_identifier = [aws_subnet.app_subnet_1.id, aws_subnet.app_subnet_2.id]
  target_group_arns   = [aws_lb_target_group.app_target_group.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.app_launch_template.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }
}

resource "aws_iam_role" "app_instance_role" {
  name = "app-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name = "SRE-DUMMY-APP-INSTANCE-ROLE"
  }
}

resource "aws_iam_role_policy_attachment" "app_instance_role_policy_attachment" {
  role       = aws_iam_role.app_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app_instance_profile" {
  name = "app-instance-profile"
  role = aws_iam_role.app_instance_role.name
}


data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-resolute-26.04-amd64-server-*"]
  }
}