data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# KMS key for Ethereum secp256k1 signing
resource "aws_kms_key" "this" {
  description             = "Ethereum signing key (secp256k1) for on-chain tx via AWS KMS"
  key_usage               = "SIGN_VERIFY"
  customer_master_key_spec = "ECC_SECG_P256K1"

  # As of today, KMS does NOT support automatic rotation for asymmetric keys.
  # Enable rotation when AWS supports it in the future.
  # enable_key_rotation = false  # not valid for asymmetric keys

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = compact([
      # Allow full control to account root (enables IAM policies to work)
      {
        Sid      = "EnableRootPermissions"
        Effect   = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      # Optional: additional admins you pass in
      length(var.kms_admin_arns) > 0 ? {
        Sid      = "KeyAdmins"
        Effect   = "Allow"
        Principal = {
          AWS = var.kms_admin_arns
        }
        Action = [
          "kms:Create*","kms:Describe*","kms:Enable*","kms:List*","kms:Put*","kms:Update*",
          "kms:Revoke*","kms:Disable*","kms:Get*","kms:Delete*","kms:TagResource","kms:UntagResource",
          "kms:ScheduleKeyDeletion","kms:CancelKeyDeletion"
        ]
        Resource = "*"
      } : null,
    ])
  })

  tags = var.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.key_alias}"
  target_key_id = aws_kms_key.this.key_id
}
