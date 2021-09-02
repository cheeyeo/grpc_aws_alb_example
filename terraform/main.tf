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

# Creating a keypair
resource "aws_key_pair" "deployer" {
  key_name   = var.m1l0_keyname
  public_key = file("~/.ssh/${var.m1l0_keyname}.pub")
}


module "ssh_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "3.18.0"

  name        = "SSHDMZ"
  description = "Security group that allows SSH access into VPC"

  vpc_id = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}


# Create security group 
module "ssh_private_vpc" {
  source      = "terraform-aws-modules/security-group/aws"
  name        = "PRIVATEVPCSSH"
  description = "Allow SSH access into private VPC"
  vpc_id      = module.vpc.vpc_id

  computed_ingress_with_source_security_group_id = [
    {
      from_port                = 22
      to_port                  = 22
      protocol                 = "tcp"
      source_security_group_id = module.ssh_security_group.this_security_group_id
    }
  ]

  number_of_computed_ingress_with_source_security_group_id = 1

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}



# Creates bastion host
module "bastion_host" {
  source = "./bastion"

  instance_count = 1

  instance_type = "t2.micro"

  subnet_ids = module.vpc.public_subnets

  security_group_ids = [module.ssh_security_group.this_security_group_id]

  key_name = aws_key_pair.deployer.key_name

  tags = {
    Name = "bastion_host"
  }
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

resource "aws_cloudwatch_log_group" "main" {
  name = "/ecs/${var.grpc_service_name}-task"
}


resource "aws_iam_policy" "rexraypolicy" {
  name        = "${var.grpc_service_name}-rexrayPolicy"
  description = "Policy for RexRay plugin for EBS volumes"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:AttachVolume",
          "ec2:CreateVolume",
          "ec2:CreateSnapshot",
          "ec2:CreateTags",
          "ec2:DeleteVolume",
          "ec2:DeleteSnapshot",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumeAttribute",
          "ec2:DescribeVolumeStatus",
          "ec2:DescribeSnapshots",
          "ec2:CopySnapshot",
          "ec2:DescribeSnapshotAttribute",
          "ec2:DetachVolume",
          "ec2:ModifySnapshotAttribute",
          "ec2:ModifyVolumeAttribute",
          "ec2:DescribeTags"
        ],
        Resource = "*"
    }]
  })
}

resource "aws_iam_role" "ecs_instance_role" {
  name = "${var.grpc_service_name}-ecsInstanceRole"

  description = "IAM Role for ECS Container Instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# attaches rexray policy to role
resource "aws_iam_role_policy_attachment" "ecs_instance_rexray" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = aws_iam_policy.rexraypolicy.arn
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ec2_instance_role" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# create ec2 instance profile
resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "${var.grpc_service_name}-ecsInstanceProfile"

  role = aws_iam_role.ecs_instance_role.name
}

# create task execution role
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.grpc_service_name}-ecsTaskRole"

  description = "IAM Role for running ECS Tasks"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          AWS     = data.aws_caller_identity.current.arn,
          Service = "ecs-tasks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "task_role_attach_ecs_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


resource "aws_iam_role_policy_attachment" "task_role_attach_cloudwatch_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSOpsWorksCloudWatchLogs"
}

# Allows ECS containers to read secrets from KMS..
resource "aws_iam_policy" "kms_policy" {
  name        = "${var.grpc_service_name}-ecsKMSPolicy"
  description = "Policy for handling KMS secrets in ECS"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssm:GetParameters",
          "secretsmanager:GetSecretValue",
          "kms:Decrypt"
        ],
        Resource = "*"
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "task_role_attach_kms" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.kms_policy.arn
}


## Provision EC2 Instance first
resource "aws_instance" "ecs_instance" {
  ami = data.aws_ami.amazon_ecs_linux.id

  iam_instance_profile = "${var.grpc_service_name}-ecsInstanceProfile"

  instance_type = "t3.medium"

  instance_initiated_shutdown_behavior = "terminate"

  monitoring = false

  security_groups = [module.vpc.default_security_group_id, module.ssh_private_vpc.this_security_group_id, module.grpc_sg.security_group_id]

  subnet_id = module.vpc.private_subnets[0]

  user_data = data.template_cloudinit_config.config.rendered

  key_name = aws_key_pair.deployer.key_name

  tags = {
    Name = "builder"
  }
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
      protocol_version = "gRPC"
      backend_port     = 50051
      target_type      = "instance"
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


resource "aws_ecs_task_definition" "grpc_service" {
  family                   = var.grpc_service_name
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {

      "essential" : true,
      "image" : "${var.container_image}",
      "name" : "${var.grpc_service_name}",
      "command" : ["--secure"],
      "portMappings" : [
        {
          "containerPort" : 50051,
          "hostPort" : 0,
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

resource "aws_ecs_service" "grpc_service" {
  name            = var.grpc_service_name
  cluster         = module.ecs.this_ecs_cluster_name
  task_definition = aws_ecs_task_definition.grpc_service.arn
  desired_count   = 2
  depends_on      = [aws_instance.ecs_instance]

  launch_type = "EC2"

  load_balancer {
    target_group_arn = module.alb.target_group_arns[0]
    container_name   = var.grpc_service_name
    container_port   = 50051
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  placement_constraints {
    type       = "memberOf"
    expression = "ec2InstanceId==${aws_instance.ecs_instance.id}"
  }
}