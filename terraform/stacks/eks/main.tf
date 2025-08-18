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

# Data source to get VPC information from remote state
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = var.tf_state_bucket
    key    = "terraform/states/${var.environment}/vpc.tfstate"
    region = var.aws_region
  }
}



# Get the latest EKS optimized AMI
data "aws_ami" "eks_default" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amazon-eks-node-${var.cluster_version}-v*"]
  }
}



############################
# EKS Cluster
############################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = data.terraform_remote_state.vpc.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnets

  enable_irsa = true

  # API endpoint access configuration
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Enable cluster creator admin permissions (this grants access to the user who created the cluster)
  enable_cluster_creator_admin_permissions = true

  # EKS Managed Node Groups
  eks_managed_node_groups = {
    # Default node group for regular workloads
    default = {
      min_size     = var.node_group_min_size
      max_size     = var.node_group_max_size
      desired_size = var.node_group_desired_size

      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type

      # Allow nodes to join cluster
      iam_role_additional_policies = {
        AmazonEKSWorkerNodePolicy          = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
        AmazonEKS_CNI_Policy               = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      }
    }


  }

  tags = {
    Project     = var.name_prefix
    Environment = var.environment
    Component   = "eks"
  }
} 