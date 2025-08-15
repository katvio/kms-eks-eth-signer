variable "oidc_provider_arn" {
  description = "EKS cluster OIDC provider ARN"
  type        = string
}

variable "oidc_issuer_url" {
  description = "EKS cluster OIDC issuer URL (e.g., https://oidc.eks.<region>.amazonaws.com/id/XYZ)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the ServiceAccount"
  type        = string
  default     = "signer"
}

variable "service_account_name" {
  description = "Kubernetes ServiceAccount name"
  type        = string
  default     = "eth-signer"
}

variable "kms_key_arn" {
  description = "KMS key ARN to allow kms:Sign/GetPublicKey access"
  type        = string
}

variable "role_name" {
  description = "Name of the IAM role for IRSA"
  type        = string
  default     = "eth-signer-irsa"
}

variable "tags" {
  description = "Tags to apply to the IAM role"
  type        = map(string)
  default     = {}
}
