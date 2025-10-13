#Team name and project title
locals {
  name = "m3ap"
}



# Create a default VPC for Jenkins server
resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16" # CIDR block for the VPC
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${local.name}-vpc"
  }
}

#----------------------------------------------------------------
# Generate a new RSA private key using the TLS provider
# this key will be used to create a public key pair for accessing the EC2 instance
#----------------------------------------------------------------
resource "tls_private_key" "keypair" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
#----------------------------------------------------------------
# Create a new key pair using the AWS provider
# the public key is derived from the private key generated above
#----------------------------------------------------------------
resource "aws_key_pair" "public_key" {
  key_name   = "${local.name}-keypair"
  public_key = tls_private_key.keypair.public_key_openssh
}
#----------------------------------------------------------------
# Save the generated private key to a local PEM file
# This file can be used for SSH access to the EC2 instance
#----------------------------------------------------------------
resource "local_file" "private_key" {
  content  = tls_private_key.keypair.private_key_pem
  filename = "${local.name}-keypair.pem"
}

# data source to fetch avaiable availability zones in the region
data "aws_availability_zones" "available" {
  state = "available"
}

# Create a public subnet in the VPC
resource "aws_subnet" "public_subnet" {
  count                   = 2 # Create two public subnets
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.${count.index}.0/24"                                        # CIDR block for each subnet
  availability_zone       = element(data.aws_availability_zones.available.names, count.index) # Use different AZs
  map_public_ip_on_launch = true                                                              # Enable public IP assignment
  tags = {
    Name = "${local.name}-public-subnet-${count.index + 1}"
  }
}
# Create an Internet Gateway for the VPC
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${local.name}-internet-gateway"
  }
}

# Create a route table for the public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${local.name}-public-rt"
  }
}
# Associate the public subnets with the route table
resource "aws_route_table_association" "public_assoc" {
  count          = 2
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public.id
}

# Fetch the latest RHEL 9 AMI in the selected region
data "aws_ami" "latest_rhel" {
  most_recent = true
  owners      = ["309956199498"] # Red Hat official AWS account ID

  filter {
    name   = "name"
    values = ["RHEL-9.*_HVM-*-x86_64-*-Hourly2-GP2"] # Pattern for RHEL 9 AMIs
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

##############################################
# IAM Role, Policies & Instance Profile for Jenkins EC2
# Purpose: Allow the Jenkins EC2 instance to use AWS Systems Manager (SSM)
# and gain administrative permissions for deployment and automation tasks.
##############################################

# -------------------------------------------------------
# 1️⃣ Create IAM Role for Jenkins EC2 Instance
# -------------------------------------------------------
# This role allows the EC2 instance (Jenkins server) to assume the role
# and interact securely with AWS services such as SSM, CloudWatch, S3, etc.
resource "aws_iam_role" "jenkins_ssm_role" {
  name = "${local.name}-ssm-role"

  # Define who can assume this role — here, EC2 service
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com" # EC2 instances are trusted to use this role
        }
      }
    ]
  })
}

# -------------------------------------------------------
# 2️⃣ Attach SSM Managed Policy
# -------------------------------------------------------
# Grants permissions for the EC2 instance to communicate with AWS Systems Manager (SSM).
# This allows you to connect to the instance using Session Manager instead of SSH keys.
resource "aws_iam_role_policy_attachment" "jenkins_ssm_attachment" {
  role       = aws_iam_role.jenkins_ssm_role.id
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# -------------------------------------------------------
# 3️⃣ Attach AdministratorAccess Policy
# -------------------------------------------------------
# Provides full administrative privileges to the Jenkins instance.
# This is useful when Jenkins needs to manage other AWS services
# like EC2, S3, ECR, or deploy infrastructure as part of CI/CD.
resource "aws_iam_role_policy_attachment" "jenkins_admin_attachment" {
  role       = aws_iam_role.jenkins_ssm_role.id
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# -------------------------------------------------------
# 4️⃣ Create IAM Instance Profile
# -------------------------------------------------------
# An instance profile is required to attach an IAM role to an EC2 instance.
# This profile wraps the IAM role and links it to the EC2 machine at launch.
resource "aws_iam_instance_profile" "jenkins_instance_profile" {
  name = "${local.name}-jenkins-instance-profile"
  role = aws_iam_role.jenkins_ssm_role.name
}

# ==============================================================
# Security Group for Jenkins Server
# --------------------------------------------------------------
# - Allows Jenkins web interface (port 8080) from ELB security group
# - No direct SSH (port 22) access; use SSM instead
# - Allows all outbound traffic
# ==============================================================

resource "aws_security_group" "jenkins_sg" {
  name        = "${local.name}-jenkins-sg"
  description = "Security group for Jenkins server"
  vpc_id      = aws_vpc.vpc.id

  # Inbound: Allow Jenkins web interface only from ELB
  ingress {
    description      = "Jenkins web interface from ELB"
    from_port        = 8080
    to_port          = 8080
    protocol         = "tcp"
    security_groups  = [aws_security_group.elb_sg.id]
  }

#   # Inbound: Optional SSH (port 22) if needed (currently open to all)
#   ingress {
#     description = "SSH access (optional, can be removed if using SSM only)"
#     from_port   = 22
#     to_port     = 22
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

  # Outbound: Allow all traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Tags for identification
  tags = {
    Name = "${local.name}-jenkins-sg"
  }
}

# ==============================================================
# EC2 Instance for Jenkins Server
# --------------------------------------------------------------
# - Uses latest RHEL AMI from data source
# - Placed in public subnet with security group
# - IAM instance profile attaches SSM and admin role
# - Uses user_data script to install Jenkins & dependencies
# ==============================================================

resource "aws_instance" "jenkins_instance" {
  ami                         = data.aws_ami.latest_rhel.id
  instance_type               = var.jenkins_instance_type # Suitable for Jenkins workloads    
  subnet_id                   = aws_subnet.public_subnet[0].id
  vpc_security_group_ids      = [aws_security_group.jenkins_sg.id]
  key_name                    = aws_key_pair.public_key.key_name
  iam_instance_profile        = aws_iam_instance_profile.jenkins_instance_profile.name
  associate_public_ip_address = true

  # User data script for automatic Jenkins installation & configuration
  user_data = templatefile("${path.module}/jenkins-userdata.sh", {
    region            = var.aws_region
    nexus_registry    = var.nexus_registry
    nexus_username    = var.nexus_username
    nexus_password    = var.nexus_password
    newrelic_license  = var.newrelic_license
  })

  # Root block device configuration
  root_block_device {
    volume_size = 20  # 20 GB root volume
    volume_type = "gp3"
    encrypted   = true
  }

  # Enforce IMDSv2 for enhanced instance metadata security
  metadata_options {
    http_tokens = "required"
  }

  # Tags for identification
  tags = {
    Name = "${local.name}-jenkins-server"
  }
}

# Security group ELB to allow HTTP traffic on port 443
resource "aws_security_group" "elb_sg" {
  name        = "${local.name}-elb-sg"
  description = "Security group for ELB"
  vpc_id      = aws_vpc.vpc.id
  # Allow inbound traffic on port 80 for HTTP (ELB frontend)
  ingress {
    description      = "Allow HTTP traffic"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] # Allow from anywhere
  }

  # Optional: keep HTTPS (443) open if you plan to terminate SSL on the ELB with a server cert
  # ingress {
  #   description      = "Allow HTTPS traffic"
  #   from_port        = 443
  #   to_port          = 443
  #   protocol         = "tcp"
  #   cidr_blocks      = ["0.0.0.0/0"]
  # }
    
    # Allow all outbound traffic
    egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1" # All protocols
    cidr_blocks      = ["0.0.0.0/0"]
  }
    tags = {
        Name = "${local.name}-elb-sg"
    }   
}

# Classic Elastic Load Balancer (ELB) to distribute traffic to Jenkins instances
resource "aws_elb" "jenkins_elb" {
  name               = "${local.name}-elb"
  subnets            = aws_subnet.public_subnet[*].id
  security_groups    = [aws_security_group.elb_sg.id]
  cross_zone_load_balancing = true

  listener {
    instance_port     = 8080
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    target              = "HTTP:8080/login" # Health check endpoint for Jenkins
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }

  instances = [aws_instance.jenkins_instance.id]

  tags = {
    Name = "${local.name}-elb"
  }
}
# ============================================================
# Lookup the existing Route 53 hosted zone for majiktech.uk
# ============================================================
data "aws_route53_zone" "majiktech_zone" {
  name         = "majiktech.uk"
  private_zone = false
}

# ============================================================
# Request an ACM certificate for Jenkins subdomain
# ============================================================
resource "aws_acm_certificate" "jenkins_cert" {
  domain_name       = "jenkins.majiktech.uk"      # Main domain for Jenkins
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "jenkins-cert-majiktech" 
  }
}

# ============================================================
# Create DNS validation records in Route 53
# ============================================================
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.jenkins_cert.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.majiktech_zone.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.value]
}

# ============================================================
# Validate the ACM certificate after DNS records are created
# ============================================================
resource "aws_acm_certificate_validation" "jenkins_cert_validation" {
  certificate_arn         = aws_acm_certificate.jenkins_cert.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# ============================================================
# Create a Route 53 Alias record for the Jenkins domain
# ============================================================
resource "aws_route53_record" "jenkins_alias" {
  zone_id = data.aws_route53_zone.majiktech_zone.zone_id
  name    = "jenkins.majiktech.uk"
  type    = "A"

  alias {
    name                   = aws_elb.jenkins_elb.dns_name
    zone_id                = aws_elb.jenkins_elb.zone_id
    evaluate_target_health = true
  }

  depends_on = [aws_acm_certificate_validation.jenkins_cert_validation]
}

/* -------------------------------------------------------
   Vault server + ELB
   - Ubuntu AMI data source
   - IAM role/profile for EC2 (SSM + KMS policy)
   - Security groups for Vault and Vault ELB
   - EC2 instance (vault-server)
   - Classic ELB in front of Vault
   - Route53 record for Vault
   ------------------------------------------------------- */

# Fetch latest Ubuntu 22.04 LTS AMI
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

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# IAM role for Vault EC2 instance
resource "aws_iam_role" "vault_ec2_role" {
  name = "${local.name}-vault-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attach SSM managed policy so instance can be managed via Session Manager
resource "aws_iam_role_policy_attachment" "vault_ssm_attachment" {
  role       = aws_iam_role.vault_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# KMS policy for Vault (basic set of operations) - scope as needed
resource "aws_iam_policy" "vault_kms_policy" {
  name        = "${local.name}-vault-kms-policy"
  description = "Allow KMS operations needed by Vault"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid = "AllowKMSUse"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach the KMS policy to the EC2 role
resource "aws_iam_role_policy_attachment" "vault_kms_attach" {
  role       = aws_iam_role.vault_ec2_role.name
  policy_arn = aws_iam_policy.vault_kms_policy.arn
}

# Instance profile for Vault EC2
resource "aws_iam_instance_profile" "vault_instance_profile" {
  name = "${local.name}-vault-instance-profile"
  role = aws_iam_role.vault_ec2_role.name
}

# Security group for Vault EC2 instance (allow 8200 from ELB only)
resource "aws_security_group" "vault_sg" {
  name        = "${local.name}-vault-sg"
  description = "Security group for Vault server"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description     = "Vault API from ELB"
    from_port       = 8200
    to_port         = 8200
    protocol        = "tcp"
    security_groups = [aws_security_group.vault_elb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-vault-sg"
  }
}

# Security group for Vault ELB (allow incoming 8200)
resource "aws_security_group" "vault_elb_sg" {
  name        = "${local.name}-vault-elb-sg"
  description = "Security group for Vault ELB"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "Allow Vault traffic"
    from_port   = 8200
    to_port     = 8200
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
    Name = "${local.name}-vault-elb-sg"
  }
}

# Vault EC2 instance
resource "aws_instance" "vault_server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.medium"
  subnet_id                   = aws_subnet.public_subnet[0].id
  vpc_security_group_ids      = [aws_security_group.vault_sg.id]
  key_name                    = aws_key_pair.public_key.key_name
  iam_instance_profile        = aws_iam_instance_profile.vault_instance_profile.name
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${local.name}-vault-server"
  }
}

# Classic ELB for Vault
resource "aws_elb" "vault_elb" {
  name    = "${local.name}-vault-elb"
  subnets = aws_subnet.public_subnet[*].id
  security_groups = [aws_security_group.vault_elb_sg.id]

  listener {
    instance_port     = 8200
    instance_protocol = "tcp"
    lb_port           = 8200
    lb_protocol       = "tcp"
  }

  health_check {
    target              = "TCP:8200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }

  instances = [aws_instance.vault_server.id]

  tags = {
    Name = "${local.name}-vault-elb"
  }
}

# Route53 record for Vault
resource "aws_route53_record" "vault_alias" {
  zone_id = data.aws_route53_zone.majiktech_zone.zone_id
  name    = var.vault_domain
  type    = "A"

  alias {
    name                   = aws_elb.vault_elb.dns_name
    zone_id                = aws_elb.vault_elb.zone_id
    evaluate_target_health = true
  }
}