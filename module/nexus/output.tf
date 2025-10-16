output "instance_id" {
  value = aws_instance.nexus.id
}

output "public_ip" {
  value = aws_instance.nexus.public_ip
}
