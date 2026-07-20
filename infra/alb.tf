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

resource "aws_lb_listener" "app_listener_https" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 443
  protocol          = "HTTPS"

  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.app_cert.arn

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

resource "aws_vpc_security_group_ingress_rule" "allow_https__ingress_rule" {
  security_group_id = aws_security_group.allow_http.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443

  tags = {
    Name = "SRE-DUMMY-APP-allow_https"
  }
}

resource "aws_acm_certificate" "app_cert" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  tags = {
    Name = "SRE-DUMMY-APP-CERT" 
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "app_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.app_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.app_zone.id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
}

resource "aws_route53_record" "app_alb_record" {
  zone_id         = data.aws_route53_zone.app_zone.id
  name            = "*.${var.domain_name}"
  type            = "CNAME"
  ttl             = 60
  records         = [aws_lb.app_lb.dns_name]
}
