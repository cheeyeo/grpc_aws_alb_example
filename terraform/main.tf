terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  shared_credentials_file = var.aws_credentials
  region                  = var.aws_region
  profile                 = var.aws_profile
}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.64.0"

  cidr = var.vpc_cidr_block

  azs = data.aws_availability_zones.available.names

  private_subnets = slice(var.private_subnet_cidr_blocks, 0, var.private_subnet_count)

  public_subnets = slice(var.public_subnet_cidr_blocks, 0, var.public_subnet_count)

  enable_nat_gateway = false

  enable_vpn_gateway = false
}


# Create security group 
module "grpc_sg" {
  source      = "terraform-aws-modules/security-group/aws"
  name        = "grpc"
  description = "allow grpc traffic"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 50051
      to_port     = 50051
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}


# creates ECS cluster
module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "2.8.0"

  name = "demo"

  tags = {
    Name = "dev"
  }
}

# create and upload self-sign certs
resource "aws_acm_certificate" "self_signed" {
  private_key      = file("../server.key")
  certificate_body = file("../server.crt")
}

# create Application Load Balancer
module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 6.0"

  name = "route-guide"

  load_balancer_type = "application"

  vpc_id          = module.vpc.vpc_id
  subnets         = module.vpc.public_subnets
  security_groups = [module.vpc.default_security_group_id, module.grpc_sg.security_group_id]

  target_groups = [
    {
      backend_protocol = "HTTPS"
      backend_port     = 50051
      target_type      = "ip"
      health_check = {
        enable              = true
        interval            = 30
        path                = "/"
        port                = "traffic-port"
        healthy_threshold   = 3
        unhealthy_threshold = 3
        timeout             = 5
        protocol            = "HTTPS"
        matcher             = "12"
      }
      protocol_version = "gRPC"
    }
  ]

  https_listeners = [
    {
      port               = 50051
      protocol           = "HTTPS"
      certificate_arn    = aws_acm_certificate.self_signed.arn
      target_group_index = 0
    }
  ]
}

# NOTE: Cant get task definition to register as FARGATE
/*
resource "aws_ecs_task_definition" "grpc" {
  family = var.grpc_family_name

  container_definitions = <<TASK_DEFINITION
[
    {
        "cpu": 256,
        "networkMode": "awsvpc",
        "essential": true,
        "image": "${var.container_image}",
        "memory": 500,
        "name": "${var.grpc_service_name}",
        "portMappings": [
            {
                "containerPort": 50051,
                "hostPort": 50051,
                "protocol": "tcp"
            }
        ],
        "compatibilities": ["EC2", "FARGATE"],
        "requiresCompatibilities": ["FARGATE"],
        "logConfiguration": {
          "logDriver": "awslogs",
          "options": {
            "awslogs-region": "${var.aws_region}",
            "awslogs-group": "${var.grpc_service_name}",
            "awslogs-stream-prefix": "${var.grpc_service_name}"
          }
        }
    }
]
TASK_DEFINITION
}
*/

resource "aws_ecs_service" "grpc_service" {
  name            = "route-guide"
  cluster         = module.ecs.this_ecs_cluster_name
  task_definition = "grpc-test"

  desired_count = 2

  launch_type = "FARGATE"

  network_configuration {
    subnets = module.vpc.public_subnets
    security_groups = [module.vpc.default_security_group_id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = module.alb.target_group_arns[0]
    container_name   = var.grpc_service_name
    container_port   = 50051
  }
}