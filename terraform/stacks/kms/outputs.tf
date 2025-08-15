output "key_id" {
  description = "The globally unique identifier for the key"
  value       = module.kms_eth_key.key_id
}

output "key_arn" {
  description = "The Amazon Resource Name (ARN) of the key"
  value       = module.kms_eth_key.key_arn
}

output "alias_name" {
  description = "The display name of the alias"
  value       = module.kms_eth_key.alias_name
}

output "alias_arn" {
  description = "The Amazon Resource Name (ARN) of the key alias"
  value       = module.kms_eth_key.alias_arn
} 