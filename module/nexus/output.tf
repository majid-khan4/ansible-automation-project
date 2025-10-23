output "instance_id" {
  value = aws_instance.nexus.id
}

output "public_ip" {
  value = aws_instance.nexus.public_ip
}

output "elb_dns_name" {
  value = aws_elb.nexus_elb.dns_name
}

output "nexus_url" {
  value = "https://${var.domain_name}"
} 