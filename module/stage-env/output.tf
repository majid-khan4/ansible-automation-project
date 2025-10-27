output "alb_dns_name" {
  value = aws_lb.stage_alb.dns_name
}

output "asg_name" {
  value = aws_autoscaling_group.stage_asg.name
}

output "alb_arn" {
  value = aws_lb.stage_alb.arn
}

output "target_group_arn" {
  value = aws_lb_target_group.stage_tg.arn
}

output "lb_security_group_id" {
  value = aws_security_group.stage_alb_sg.id
}

output "stage_security_group_id" {
  value = aws_security_group.stage_sg.id
}
