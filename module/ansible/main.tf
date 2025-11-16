// Fetch latest RHEL 9 AMI for Ansible

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

# ansible IAM Role and Instance Profile
resource "aws_iam_role" "ansible_role" {
  name = "${var.name}-ansible-role"
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
}

resource "aws_iam_role_policy_attachment" "ansible_ec2_full" {
  role       = aws_iam_role.ansible_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_role_policy_attachment" "ansible_s3_full" {
  role       = aws_iam_role.ansible_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_instance_profile" "ansible_profile" {
  name = "${var.name}-ansible-instance-profile"
  role = aws_iam_role.ansible_role.name
}

// Security group for Ansible: allow SSH from Bastion SG, egress everywhere
resource "aws_security_group" "ansible_sg" {
  name        = "${var.name}-ansible-sg"
  description = "Allow SSH from Bastion, egress everywhere"
  vpc_id      = var.vpc_id

  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.bastion_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-ansible-sg"
  }
}


// Ansible EC2 instance in private subnet
resource "aws_instance" "ansible" {
  ami                         = data.aws_ami.latest_rhel.id
  instance_type               = "t2.medium"
  subnet_id                   = var.private_subnet_id
  vpc_security_group_ids      = [aws_security_group.ansible_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ansible_profile.name
  key_name                    = var.key_pair_name
  associate_public_ip_address = false
  user_data = templatefile("${path.module}/ansible-userdata.sh", {
    private_key_pem        = var.private_key_pem
    s3_bucket             = var.s3_bucket
    nexus_ip              = var.nexus_ip
    newrelic_api_key      = var.newrelic_api_key
    newrelic_account_id   = var.newrelic_account_id
  })

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.name}-ansible"
  }

  lifecycle {
    ignore_changes = [user_data]
  }
}

# Upload Ansible scripts to S3 bucket
resource "aws_s3_object" "stage_bash_script" {
  bucket = var.s3_bucket
  key = "scripts/stage_bash.sh"
  source = "${path.module}/scripts/stage_bash.sh"
}
resource "aws_s3_object" "prod_bash_script" {
  bucket = var.s3_bucket
  key = "scripts/prod_bash.sh"
  source = "${path.module}/scripts/prod_bash.sh"
}
resource "aws_s3_object" "deployment__yml" {
  bucket = var.s3_bucket
  key = "scripts/deployment.yml"
  source = "${path.module}/scripts/deployment.yml"
}