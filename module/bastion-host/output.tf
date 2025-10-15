output "asg_id" {
  value = aws_autoscaling_group.bastion_asg.id
}

output "launch_template_id" {
  value = aws_launch_template.bastion_lt.id
}

output "security_group_id" {
  value = aws_security_group.bastion_sg.id
}

output "instance_profile_name" {
  value = aws_iam_instance_profile.ssm_profile.name
}
