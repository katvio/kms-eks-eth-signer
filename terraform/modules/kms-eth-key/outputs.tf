output "key_id" {
  value       = aws_kms_key.this.key_id
  description = "KMS Key ID"
}

output "key_arn" {
  value       = aws_kms_key.this.arn
  description = "KMS Key ARN"
}

output "alias_name" {
  value       = aws_kms_alias.this.name
  description = "KMS Alias name (with alias/ prefix)"
}

output "alias_arn" {
  value       = aws_kms_alias.this.arn
  description = "KMS Alias ARN"
}
