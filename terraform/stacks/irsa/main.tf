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

# Data source to get EKS information from remote state
data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = var.tf_state_bucket
    key    = "terraform/states/${var.environment}/eks.tfstate"
    region = var.aws_region
  }
}

# Data source to get KMS information from remote state
data "terraform_remote_state" "kms" {
  backend = "s3"
  config = {
    bucket = var.tf_state_bucket
    key    = "terraform/states/${var.environment}/kms.tfstate"
    region = var.aws_region
  }
}

############################
# IRSA role for signer SA
############################
module "iam_irsa" {
  source = "../../modules/iam-irsa"

  oidc_provider_arn = data.terraform_remote_state.eks.outputs.oidc_provider_arn
  oidc_issuer_url   = data.terraform_remote_state.eks.outputs.cluster_oidc_issuer_url

  namespace             = var.k8s_namespace
  service_account_name  = var.k8s_service_account
  role_name             = "${var.name_prefix}-irsa"

  kms_key_arn = data.terraform_remote_state.kms.outputs.key_arn

  tags = {
    Project     = var.name_prefix
    Environment = var.environment
    Component   = "irsa"
  }
} 