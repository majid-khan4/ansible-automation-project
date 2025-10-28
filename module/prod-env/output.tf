output "alb_dns_name" {
  value = aws_lb.prod_alb.dns_name
}

output "asg_name" {
  value = aws_autoscaling_group.prod_asg.name
}

output "alb_arn" {
  value = aws_lb.prod_alb.arn
}

output "target_group_arn" {
  value = aws_lb_target_group.prod_tg.arn
}

output "lb_security_group_id" {
  value = aws_security_group.prod_alb_sg.id
}

output "prod_security_group_id" {
  value = aws_security_group.prod_sg.id
}
