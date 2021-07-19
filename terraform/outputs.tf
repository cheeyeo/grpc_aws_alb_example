output "aws_region" {
  description = "AWS Region"
  value       = data.aws_region.current.name
}

output "public_subnet_ids" {
  description = "Public subnet ids"
  value       = module.vpc.public_subnets
}

output "cluster_id" {
  description = "ECS cluster id"
  value       = module.ecs.this_ecs_cluster_id
}

output "cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.this_ecs_cluster_name
}

output "load_balancer" {
  description = "DNS A record of load balancer"
  value       = module.alb.lb_dns_name
}