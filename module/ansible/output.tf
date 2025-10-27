output "security_group_id" {
	value = aws_security_group.ansible_sg.id
}

output "instance_id" {
	value = aws_instance.ansible.id
	description = "Instance id for the Ansible control node"
}

output "instance_private_ip" {
	value = aws_instance.ansible.private_ip
}

output "instance_profile_name" {
	value = aws_iam_instance_profile.ansible_profile.name
}
