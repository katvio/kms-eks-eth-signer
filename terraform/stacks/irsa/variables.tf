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

variable "tf_state_bucket" {
  description = "S3 bucket for Terraform state"
  type        = string
}

variable "k8s_namespace" {
  description = "Kubernetes namespace for the service account"
  type        = string
  default     = "eth-signer"
}

variable "k8s_service_account" {
  description = "Kubernetes service account name"
  type        = string
  default     = "eth-signer-sa"
} 