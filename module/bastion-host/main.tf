

// Fetch latest RHEL 9 AMI for bastion
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


# IAM role for SSM
resource "aws_iam_role" "ssm_role" {
  name = "${var.name}-ssm-role"
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

# Attach SSM managed policy to role
resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile for the role
resource "aws_iam_instance_profile" "ssm_profile" {
  name = "${var.name}-instance-profile"
  role = aws_iam_role.ssm_role.name
}

# Security group: no ingress, egress to everywhere
resource "aws_security_group" "bastion_sg" {
  name   = "${var.name}-bastion_sg"
  vpc_id = var.vpc_id
  description = "Bastion security group: no ingress, allow all egress"

  # Egress: allow all
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Launch template for ASG
resource "aws_launch_template" "bastion_lt" {
  name_prefix   = "${var.name}-bastion_lt"
  image_id      = data.aws_ami.rhel9.id
  instance_type = "t2.micro"
  key_name      = var.key_pair_name

  user_data = base64encode(templatefile("${path.module}/userdata.sh", {
    private_key_pem     = var.private_key_pem
    region              = var.region
    newrelic_api_key    = var.newrelic_api_key
    newrelic_account_id = var.newrelic_account_id
  }))

  iam_instance_profile {
    name = aws_iam_instance_profile.ssm_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.bastion_sg.id]
  }
}

// Auto Scaling Group
resource "aws_autoscaling_group" "bastion_asg" {
  name                      = "${var.name}-bastion_asg"
  max_size                  = 3
  min_size                  = 1
  launch_template {
    id      = aws_launch_template.bastion_lt.id
    version = "$Latest"
  }

  vpc_zone_identifier = var.public_subnet_ids

  tag {
    key                 = "Name"
    value               = "${var.name}"
    propagate_at_launch = true
  }
  health_check_type         = "EC2"
  health_check_grace_period = 30
}
