variable "key_alias" {
  description = "Alias name without 'alias/' prefix, e.g. eth-signer-sepolia"
  type        = string
  default     = "eth-signer-sepolia"
}

variable "kms_admin_arns" {
  description = "List of IAM principal ARNs (users/roles) that can administer the key (in addition to account root)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to KMS key and alias"
  type        = map(string)
  default     = {}
}
