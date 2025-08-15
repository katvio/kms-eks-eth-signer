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
# KMS secp256k1 key for Ethereum
############################
module "kms_eth_key" {
  source = "../../modules/kms-eth-key"

  key_alias      = var.kms_key_alias
  kms_admin_arns = var.kms_admin_arns
  
  tags = {
    Project     = var.name_prefix
    Environment = var.environment
    Component   = "kms"
  }
} 