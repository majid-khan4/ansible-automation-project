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

// IAM role for SSM access
resource "aws_iam_role" "nexus_ssm_role" {
  name = "${var.name}-nexus-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = { Service = "ec2.amazonaws.com" },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

// IAM policy for SSM (uses AWS managed policy but create inline minimal policy here)
resource "aws_iam_policy" "nexus_ssm_policy" {
  name        = "${var.name}-nexus-ssm-policy"
  description = "Minimal policy for SSM access and S3 if needed"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssm:DescribeInstanceInformation",
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:ListCommands",
          "ssm:ListCommandInvocations"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "nexus_ssm_attach" {
  role       = aws_iam_role.nexus_ssm_role.name
  policy_arn = aws_iam_policy.nexus_ssm_policy.arn
}

resource "aws_iam_role_policy_attachment" "nexus_ssm_managed" {
  role       = aws_iam_role.nexus_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "nexus_instance_profile" {
  name = "${var.name}-nexus-instance-profile"
  role = aws_iam_role.nexus_ssm_role.name
}

// Nexus security group: only allow traffic from ELB on app port (8081)
resource "aws_security_group" "nexus_sg" {
  name        = "${var.name}-nexus-sg"
  description = "Allow traffic from Nexus ELB only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Nexus app from ELB"
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.nexus_elb_sg.id]
  }

  # Allow Docker registry traffic from ELB (port 5000)
  # (removed optional docker registry rule — Nexus userdata currently doesn't map port 5000)

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-nexus-sg" }
}

// Nexus ELB security group: allow HTTPS from anywhere
resource "aws_security_group" "nexus_elb_sg" {
  name        = "${var.name}-nexus-elb-sg"
  description = "ELB for Nexus - allow HTTPS from anywhere"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow Docker registry HTTPS/HTTP from internet if needed (5000)
  # (removed optional docker registry rule — Nexus userdata currently doesn't map port 5000)

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-nexus-elb-sg" }
}

// Nexus EC2 instance (SSM-only access)
resource "aws_instance" "nexus" {
  ami                         = data.aws_ami.rhel9.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_ids[0]       
  vpc_security_group_ids      = [aws_security_group.nexus_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.nexus_instance_profile.name
  associate_public_ip_address = true
  key_name                    = var.key_name

  user_data = templatefile("${path.module}/userdata.sh", {
    newrelic_api_key    = var.newrelic_api_key
    newrelic_account_id = var.newrelic_account_id
  })

  tags = { Name = "${var.name}-nexus" }
}

// Classic ELB for Nexus
resource "aws_elb" "nexus_elb" {
  name            = "${var.name}-nexus-elb"
  subnets         = var.subnet_ids
  security_groups = [aws_security_group.nexus_elb_sg.id]
  cross_zone_load_balancing = true

  listener {
    instance_port     = 8081
    instance_protocol = "http"
    lb_port           = 443
    lb_protocol       = "https"
    # Attach certificate: prefer caller-provided ARN, otherwise use certificate created by this module
    ssl_certificate_id = var.ssl_certificate_arn != "" ? var.ssl_certificate_arn : aws_acm_certificate.nexus_cert[0].arn
  }

  health_check {
    target              = "HTTP:8081/"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }

  instances = [aws_instance.nexus.id]
  tags = { Name = "${var.name}-nexus-elb" }

}

# ACM certificate for the nexus subdomain (created only if caller did not provide ssl_certificate_arn)
resource "aws_acm_certificate" "nexus_cert" {
  count                      = var.ssl_certificate_arn == "" ? 1 : 0
  domain_name                = var.subdomain
  validation_method          = "DNS"
  subject_alternative_names  = []
  lifecycle {
    create_before_destroy = true
  }
}

# DNS validation record for the ACM certificate
resource "aws_route53_record" "nexus_cert_validation" {
  count       = var.ssl_certificate_arn == "" ? length(aws_acm_certificate.nexus_cert[0].domain_validation_options) : 0
  zone_id     = data.aws_route53_zone.zone.zone_id
  name        = element(aws_acm_certificate.nexus_cert[0].domain_validation_options.*.resource_record_name, count.index)
  type        = element(aws_acm_certificate.nexus_cert[0].domain_validation_options.*.resource_record_type, count.index)
  records     = [element(aws_acm_certificate.nexus_cert[0].domain_validation_options.*.resource_record_value, count.index)]
  ttl         = 60
  allow_overwrite = true
}

# ACM certificate validation resource
resource "aws_acm_certificate_validation" "nexus_cert_validation" {
  count               = var.ssl_certificate_arn == "" ? 1 : 0
  certificate_arn     = aws_acm_certificate.nexus_cert[0].arn
  validation_record_fqdns = [for r in aws_route53_record.nexus_cert_validation : r.fqdn]
}

# Note: ELB creation may proceed before ACM validation completes. If you need strict ordering,
# consider provisioning the certificate outside the module and passing ssl_certificate_arn in.

// Route53 record for Nexus subdomain -> ELB
data "aws_route53_zone" "zone" {
  name         = var.domain
  private_zone = false
}

resource "aws_route53_record" "nexus_alias" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = var.subdomain
  type    = "A"

  alias {
    name                   = aws_elb.nexus_elb.dns_name
    zone_id                = aws_elb.nexus_elb.zone_id
    evaluate_target_health = true
  }
}

