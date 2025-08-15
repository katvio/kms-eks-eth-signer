variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "eth-signer"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "kms_key_alias" {
  description = "Alias name for KMS key without 'alias/' prefix"
  type        = string
  default     = "eth-signer-sepolia"
}

variable "kms_admin_arns" {
  description = "List of IAM principal ARNs that can administer the KMS key"
  type        = list(string)
  default     = []
} 