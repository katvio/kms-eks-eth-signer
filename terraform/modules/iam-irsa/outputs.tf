output "role_arn" {
  value       = aws_iam_role.this.arn
  description = "IAM Role ARN for IRSA"
}
