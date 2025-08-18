# Core infrastructure settings
aws_region       = "eu-west-1"
environment      = "prod"
name_prefix      = "kms-eks-eth-prod"

# EKS Configuration
cluster_name     = "kms-eks-eth-prod"
cluster_version  = "1.29"

# EKS API endpoint access (restrict to your IP for better security)
cluster_endpoint_public_access_cidrs = ["88.181.233.30/32"]

# VPC configuration (3 AZs for high availability)
vpc_cidr         = "10.0.0.0/16"
azs              = ["eu-west-1a","eu-west-1b","eu-west-1c"]
private_subnets  = ["10.0.1.0/24","10.0.2.0/24","10.0.3.0/24"]
public_subnets   = ["10.0.101.0/24","10.0.102.0/24","10.0.103.0/24"]

# Cost optimization for dev
single_nat_gateway = true
enable_flow_logs   = true

# EKS node group settings - Optimized for single node (cost savings)
node_group_min_size     = 2
node_group_max_size     = 6
node_group_desired_size = 3
node_instance_types     = ["t3.medium"]
node_capacity_type      = "ON_DEMAND"

# KMS settings
kms_key_alias = "eth-signer-mainnet-prod"

# Optional: declare extra admins for the key (your IAM user/role ARNs)
kms_admin_arns = [
  # "arn:aws:iam::<ACCOUNT_ID>:user/you",
  # "arn:aws:iam::<ACCOUNT_ID>:role/admin"
]

# IRSA settings
k8s_namespace       = "signer"
k8s_service_account = "eth-signer"

# Terraform State (will be set by setup.sh)
# tf_state_bucket = "will-be-set-dynamically" 