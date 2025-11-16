
# --- Security Group for Load Balancer ---
resource "aws_security_group" "prod_alb_sg" {
  name        = "${var.name}-prod-alb-sg"
  description = "Security group for prod ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-prod-alb-sg" }
}

# --- Security Group for EC2 Instances ---
resource "aws_security_group" "prod_sg" {
  name        = "${var.name}-prod-sg"
  description = "Security group for prod App EC2s"
  vpc_id      = var.vpc_id

  ingress {
    description     = "App traffic from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.prod_alb_sg.id]
  }

  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.bastion_sg, var.ansible_sg]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-prod-sg" }
}

# --- Application Load Balancer ---
resource "aws_lb" "prod_alb" {
  name               = "${var.name}-prod-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.prod_alb_sg.id]
  subnets            = var.public_subnet_ids
  idle_timeout       = 60

  tags = { Name = "${var.name}-prod-alb" }
}

# --- Target Group ---
resource "aws_lb_target_group" "prod_tg" {
  name     = "${var.name}-prod-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Name = "${var.name}-prod-tg" }
}

# --- HTTP Redirect to HTTPS ---
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.prod_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# --- HTTPS Listener ---
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.prod_alb.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = data.aws_acm_certificate.acm_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_tg.arn
  }
}

// Data: latest RHEL9 AMI
data "aws_ami" "latest_rhel" {
  most_recent = true
  owners      = ["309956199498"] # Red Hat official AWS account ID

  filter {
    name = "name"
    # Simplified pattern: looks for any RHEL 9 AMI with the HVM suffix
    values = ["RHEL-9.*_HVM-*x86_64*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Launch Template Configuration for EC2 Instances in prod Env 
resource "aws_launch_template" "prod_launch_template" {
  name_prefix   = "${var.name}-prod-tmpl"
  image_id      = data.aws_ami.latest_rhel.id
  instance_type = "t2.medium"
  key_name      = var.keypair

  # Pass user_data as base64 encoded from the local script and substitute variables dynamically
  user_data = base64encode(templatefile("${path.module}/prod-userdata.sh", {
    newrelic_api_key    = var.newrelic_api_key
    newrelic_account_id = var.newrelic_account_id
  }))

  vpc_security_group_ids = [aws_security_group.prod_sg.id]

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.name}-prod-ec2"
      Environment = "prod"
    }
  }
}

# --- Auto Scaling Group ---
resource "aws_autoscaling_group" "prod_asg" {
  name                      = "${var.name}-prod-asg"
  vpc_zone_identifier        = var.private_subnet_ids
  desired_capacity           = 1
  min_size                   = 1
  max_size                   = 3
  health_check_type          = "EC2"
  health_check_grace_period  = 120
  target_group_arns          = [aws_lb_target_group.prod_tg.arn]
  launch_template {
        id      = aws_launch_template.prod_launch_template.id
        version = "$Latest"
        }
  tag {
    key                 = "Name"
    value               = "${var.name}-prod-asg"
    propagate_at_launch = true
  }
}

# Auto Scaling Policy for Dynamic Scaling on CPU Utilization   
resource "aws_autoscaling_policy" "prod_asg_policy" {
  name                   = "${var.name}-prod-asg-policy"
  autoscaling_group_name = aws_autoscaling_group.prod_asg.name
  adjustment_type        = "ChangeInCapacity"
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}
# Route53 Hosted Zone and ACM Certificate
data "aws_route53_zone" "my_hosted_zone" {
  name         = var.domain_name
  private_zone = false
}

# data block to fetch ACM certificate for sonarqube
data "aws_acm_certificate" "acm_cert" {
  domain   = "majiktech.uk"
  statuses = ["ISSUED"]
  most_recent = true
}   

# Route 53 Record
resource "aws_route53_record" "prod_dns" {
  zone_id = data.aws_route53_zone.my_hosted_zone.zone_id
  name    = "prod.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.prod_alb.dns_name
    zone_id                = aws_lb.prod_alb.zone_id
    evaluate_target_health = true
  }
}