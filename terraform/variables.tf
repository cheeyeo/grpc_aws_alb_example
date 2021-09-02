variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS Profile"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_credentials" {
  description = "Path to aws credentials"
  type        = string
  default     = ""
  sensitive   = true
}

variable "vpc_cidr_block" {
  description = "CIDR Block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidr_blocks" {
  description = "CIDR block for private subnet"
  type        = list(string)
  default = [
    "10.0.101.0/24",
    "10.0.102.0/24",
    "10.0.103.0/24",
    "10.0.104.0/24",
    "10.0.105.0/24",
    "10.0.106.0/24",
    "10.0.107.0/24",
    "10.0.108.0/24"
  ]
}

variable "public_subnet_cidr_blocks" {
  description = "CIDR Block for public subnets"
  type        = list(string)
  default = [
    "10.0.1.0/24",
    "10.0.2.0/24",
    "10.0.3.0/24",
    "10.0.4.0/24",
    "10.0.5.0/24",
    "10.0.6.0/24",
    "10.0.7.0/24",
    "10.0.8.0/24"
  ]
}

variable "public_subnet_count" {
  description = "Number of public subnets"
  type        = number
  default     = 2
}

variable "private_subnet_count" {
  description = "Number of private subnets"
  type        = number
  default     = 2
}

variable "grpc_service_name" {
  description = "Name of grpc service"
  type        = string
  default     = ""
}

variable "grpc_family_name" {
  description = "Family name of grpc service task definition"
  type        = string
  default     = ""
}

variable "container_image" {
  description = "Container image of grpc"
  type        = string
  default     = ""
}

variable "m1l0_keyname" {
  description = "Name of M1L0 SSH key"
  type        = string
  default     = "M1L0Key"
}