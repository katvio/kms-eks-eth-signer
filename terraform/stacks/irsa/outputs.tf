output "role_arn" {
  description = "ARN of the IAM role for service account"
  value       = module.iam_irsa.role_arn
}

output "role_name" {
  description = "Name of the IAM role for service account"
  value       = module.iam_irsa.role_name
} 