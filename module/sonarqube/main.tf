# IAM Role for SSM on sonaqube server
resource "aws_iam_role" "sonarqube_ssm_role" {
  name = "${var.name}-sonarqube-ssm-role"

  # Allows EC2 service to assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

# Attach SSM permissions so EC2 can be managed via Systems Manager
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.sonarqube_ssm_role.id
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile to associate the IAM role with the EC2 instance
resource "aws_iam_instance_profile" "sonar_ssm_profile" {
  name = "${var.name}-sonarqube-instance-profile"
  role = aws_iam_role.sonarqube_ssm_role.id
}

# sonaqube Security Group
resource "aws_security_group" "sonarqube_sg" {
  name   = "${var.name}-sonarqube-sg"
  vpc_id = var.vpc_id


  # custom port (admin UI port)
  ingress {
    description     = "allows ingress from sonar elb"
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.sonarqube_elb_sg.id]
  }

  # Allow all outbound traffic
  egress {
    description = "allows egress from sonar elb"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Data source to get the latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# EC2 Instance to create a sonaqube server
resource "aws_instance" "sonarqube" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.medium"
  subnet_id                   = var.subnet_id
  key_name                    = var.key_pair_name # SSH key
  vpc_security_group_ids      = [aws_security_group.sonarqube_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.sonar_ssm_profile.name
  associate_public_ip_address = true
  user_data = templatefile("${path.module}/userdata.sh", {
    newrelic_api_key    = var.newrelic_api_key
    newrelic_account_id = var.newrelic_account_id
  })
  
  metadata_options { http_tokens = "required" }
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
    tags = {
      Name = "${var.name}-sonarqube-root-volume"
    }
  }
  tags = {
    Name = "${var.name}-sonarqube"
    Service = "sonarqube"
    Environment = "production"
    Monitoring = "newrelic"
  }
}

# Create a new load balancer
resource "aws_elb" "sonarqube_elb" {
  name            = "${var.name}-sonarqube-elb"
  subnets         = var.subnet_ids
  security_groups = [aws_security_group.sonarqube_elb_sg.id]

  listener {
    instance_port      = 9000
    instance_protocol  = "http"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = data.aws_acm_certificate.name.arn
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    target              = "TCP:9000"
    interval            = 30
  }

  instances                   = [aws_instance.sonarqube.id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "${var.name}-sonarqube-elb"
  }
}

# sonaqube Security Group
resource "aws_security_group" "sonarqube_elb_sg" {
  name   = "${var.name}-sonarqube-elb-sg"
  vpc_id = var.vpc_id

  # Allow HTTPS access (for future SSL setup)
  ingress {
    description = "Allow all inbound traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Allow all outbound traffic
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.name}-sonarqube-elb-sg"
  }
}

# Route53 Hosted Zone and ACM Certificate
data "aws_route53_zone" "my_hosted_zone" {
  name         = var.domain_name
  private_zone = false
}

# data block to fetch ACM certificate for sonarqube
data "aws_acm_certificate" "name" {
  domain   = var.domain_name
  statuses = ["ISSUED"]
  most_recent = true
}   

# Route 53 Record
resource "aws_route53_record" "sonraqube_dns" {
  zone_id = data.aws_route53_zone.my_hosted_zone.zone_id
  name    = "sonarqube.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_elb.sonarqube_elb.dns_name
    zone_id                = aws_elb.sonarqube_elb.zone_id
    evaluate_target_health = true
  }
}

