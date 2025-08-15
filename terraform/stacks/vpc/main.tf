terraform {
  required_version = ">= 1.7"
  backend "s3" {}
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

############################
# VPC (community module)
############################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.name_prefix
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway = true
  single_nat_gateway = var.single_nat_gateway

  # Enable DNS hostnames and resolution for EKS
  enable_dns_hostnames = true
  enable_dns_support   = true

  # VPC Flow Logs (optional but recommended)
  enable_flow_log                      = var.enable_flow_logs
  create_flow_log_cloudwatch_log_group = var.enable_flow_logs
  create_flow_log_cloudwatch_iam_role  = var.enable_flow_logs

  tags = {
    Project                                           = var.name_prefix
    Environment                                       = var.environment
    "kubernetes.io/cluster/${var.cluster_name}"      = "shared"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
} 