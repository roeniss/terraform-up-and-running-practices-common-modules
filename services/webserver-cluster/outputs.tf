output "subnet_ids" {
  value       = data.aws_subnet_ids.default.ids
  description = "Subnet IDs"
}

output "alb_domain" {
  value       = aws_lb.default.dns_name
  description = "ALB DNS name"
}

output "rds_address" {
  value       = data.terraform_remote_state.db.outputs.address
  description = "address of the RDS instance"
}

output "rds_port" {
  value       = data.terraform_remote_state.db.outputs.port
  description = "port of the RDS instance"
}

output "asg_name" { 
  value = aws_autoscaling_group.default.name
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}