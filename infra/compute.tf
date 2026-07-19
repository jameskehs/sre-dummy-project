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