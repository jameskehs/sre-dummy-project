variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "The EC2 instance type for the application instances"
  type        = string
  default     = "t3.micro"
}

variable "app_port" {
  description = "The port on which the application will listen"
  type        = number
  default     = 3000
}

variable "asg_min_size" {
  description = "The minimum size of the Auto Scaling Group"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "The maximum size of the Auto Scaling Group"
  type        = number
  default     = 2
}

variable "domain_name" {
  description = "The domain name to be used for ACM certificate and Route 53 records"
  type        = string
  default     = "jameskehs.dev"
}