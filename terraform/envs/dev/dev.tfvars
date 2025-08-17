# Core infrastructure settings
aws_region       = "eu-west-1"
environment      = "dev"
name_prefix      = "kms-eks-eth"
cluster_name     = "kms-eks-eth"
cluster_version  = "1.29"

# VPC configuration (3 AZs for high availability)
vpc_cidr         = "10.20.0.0/16"
azs              = ["eu-west-1a","eu-west-1b","eu-west-1c"]
private_subnets  = ["10.20.1.0/24","10.20.2.0/24","10.20.3.0/24"]
public_subnets   = ["10.20.101.0/24","10.20.102.0/24","10.20.103.0/24"]

# Cost optimization for dev
single_nat_gateway = true
enable_flow_logs   = false

# EKS node group settings
node_group_min_size     = 1
node_group_max_size     = 3
node_group_desired_size = 1
node_instance_types     = ["t3.medium"]
node_capacity_type      = "ON_DEMAND"

# KMS settings
kms_key_alias = "eth-signer-sepolia"

# Optional: declare extra admins for the key (your IAM user/role ARNs)
kms_admin_arns = [
  # "arn:aws:iam::<ACCOUNT_ID>:user/you",
  # "arn:aws:iam::<ACCOUNT_ID>:role/admin"
]

# IRSA settings
k8s_namespace       = "signer"
k8s_service_account = "eth-signer"
