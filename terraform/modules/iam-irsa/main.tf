locals {
  # issuer host without https://
  oidc_host = replace(var.oidc_issuer_url, "https://", "")
  sa_sub    = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
}

resource "aws_iam_role" "this" {
  name = var.role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Federated = var.oidc_provider_arn
      },
      Action = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringEquals = {
          "${local.oidc_host}:sub" = local.sa_sub
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "kms_sign" {
  name = "${var.role_name}-kms-sign"
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "KmsSignAndGetPublicKey",
        Effect = "Allow",
        Action = [
          "kms:Sign",
          "kms:GetPublicKey",
          "kms:DescribeKey"
        ],
        Resource = var.kms_key_arn
      }
    ]
  })
}
