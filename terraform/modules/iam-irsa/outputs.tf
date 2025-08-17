output "role_arn" {
  value       = aws_iam_role.this.arn
  description = "IAM Role ARN for IRSA"
}

output "role_name" {
  value       = aws_iam_role.this.name
  description = "IAM Role name for IRSA"
}
