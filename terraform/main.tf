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

  enable_nat_gateway = true

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

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.grpc_service_name}-ecsTaskExecutionRole"

  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "ecs-tasks.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs-task-execution-role-policy-attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# NOTE: Need to create log group manually when using FARGATE?
resource "aws_cloudwatch_log_group" "main" {
  name = "/ecs/${var.grpc_service_name}-task"
}


resource "aws_ecs_task_definition" "grpc_service" {
  family                   = var.grpc_service_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn


  container_definitions = jsonencode([
    {

      "essential" : true,
      "image" : "${var.container_image}",
      "name" : "${var.grpc_service_name}",
      "portMappings" : [
        {
          "containerPort" : 50051,
          "hostPort" : 50051,
          "protocol" : "tcp"
        }
      ],
      "logConfiguration" : {
        "logDriver" : "awslogs",
        "options" : {
          "awslogs-region" : "${var.aws_region}",
          "awslogs-group" : aws_cloudwatch_log_group.main.name,
          "awslogs-stream-prefix" : "ecs"
        }
      }
    }
  ])
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

resource "aws_ecs_service" "grpc_service" {
  name            = var.grpc_service_name
  cluster         = module.ecs.this_ecs_cluster_name
  task_definition = aws_ecs_task_definition.grpc_service.arn

  desired_count = 2

  launch_type = "FARGATE"

  network_configuration {
    security_groups  = [module.vpc.default_security_group_id]
    subnets          = module.vpc.private_subnets
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = module.alb.target_group_arns[0]
    container_name   = var.grpc_service_name
    container_port   = 50051
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}