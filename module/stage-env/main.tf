
# --- Security Group for Load Balancer ---
resource "aws_security_group" "stage_alb_sg" {
  name        = "${var.name}-stage-alb-sg"
  description = "Security group for Stage ALB"
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

  tags = { Name = "${var.name}-stage-alb-sg" }
}

# --- Security Group for EC2 Instances ---
resource "aws_security_group" "stage_sg" {
  name        = "${var.name}-stage-sg"
  description = "Security group for Stage App EC2s"
  vpc_id      = var.vpc_id

  ingress {
    description     = "App traffic from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.stage_alb_sg.id]
  }

  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.bastion_sg_id, var.ansible_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-app-sg" }
}

# --- Application Load Balancer ---
resource "aws_lb" "stage_alb" {
  name               = "${var.name}-stage-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.stage_alb_sg.id]
  subnets            = var.public_subnet_ids
  idle_timeout       = 60

  tags = { Name = "${var.name}-stage-alb" }
}

# --- Target Group ---
resource "aws_lb_target_group" "stage_tg" {
  name     = "${var.name}-stage-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
    lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.name}-stage-tg" }
}

# --- HTTP Redirect to HTTPS ---
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.stage_alb.arn
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
  load_balancer_arn = aws_lb.stage_alb.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = data.aws_acm_certificate.acm_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.stage_tg.arn
  }
}

// Data: latest RHEL9 AMI
data "aws_ami" "rhel9" {
  most_recent = true
  owners      = ["309956199498"]

  filter {
    name   = "name"
    values = ["RHEL-9.*_HVM-*-x86_64-*-Hourly2-GP2"]
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

# Launch Template Configuration for EC2 Instances in Stage Env 
resource "aws_launch_template" "stage_launch_template" {
  name_prefix   = "${var.name}-stage-tmpl"
  image_id      = data.aws_ami.rhel9.id
  instance_type = "t3.medium"
  key_name      = var.keypair

  # Pass user_data from the local script and substitute variables dynamically
  user_data = templatefile("${path.module}/stage-userdata.sh", {
      NEW_RELIC_API_KEY    = var.new_relic_api_key
      NEW_RELIC_ACCOUNT_ID = var.new_relic_account_id
    })

  vpc_security_group_ids = [aws_security_group.stage_sg.id]

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.name}-stage-ec2"
      Environment = "stage"
    }
  }
}


# --- Auto Scaling Group ---
resource "aws_autoscaling_group" "stage_asg" {
  name                      = "${var.name}-stage-asg"
  vpc_zone_identifier        = var.private_subnet_ids
  desired_capacity           = 1
  min_size                   = 1
  max_size                   = 3
  health_check_type          = "EC2"
  health_check_grace_period  = 120
  target_group_arns          = [aws_lb_target_group.stage_tg.arn]
  launch_template {
        id      = aws_launch_template.stage_launch_template.id
        version = "$Latest"
        }
  tag {
    key                 = "Name"
    value               = "${var.name}-stage-asg"
    propagate_at_launch = true
  }
}

# Auto Scaling Policy for Dynamic Scaling on CPU Utilization   
resource "aws_autoscaling_policy" "stage_asg_policy" {
  name                   = "${var.name}-stage-asg-policy"
  autoscaling_group_name = aws_autoscaling_group.stage_asg.name
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
resource "aws_route53_record" "stage_dns" {
  zone_id = data.aws_route53_zone.my_hosted_zone.zone_id
  name    = "stage.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.stage_alb.dns_name
    zone_id                = aws_lb.stage_alb.zone_id
    evaluate_target_health = true
  }
}