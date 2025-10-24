// Fetch latest RHEL 9 AMI for Ansible

data "aws_ami" "rhel9" {
  most_recent = true
  owners      = ["309956199498"] # Red Hat official AWS account ID
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

// IAM Role for Ansible EC2
resource "aws_iam_role" "ansible_role" {
  name = "${var.name}-ansible-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
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

// Ansible EC2 instance in private subnet
resource "aws_instance" "ansible" {
  ami                         = data.aws_ami.rhel9.id
  instance_type               = "t2.medium"
  subnet_id                   = var.private_subnet_id
  vpc_security_group_ids      = [aws_security_group.ansible_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ansible_profile.name
  key_name                    = var.key_pair_name
  associate_public_ip_address = false

  tags = {
    Name = "${var.name}-ansible"
  }
}

// Null resource to copy playbooks to S3
resource "null_resource" "copy_playbooks" {
  provisioner "local-exec" {
    command = "aws s3 cp ../playbooks/ s3://${var.s3_bucket}/playbooks/ --recursive"
  }
}
