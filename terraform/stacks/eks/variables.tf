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

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "eth-signer-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version to use for EKS cluster"
  type        = string
  default     = "1.28"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks that can access the EKS cluster endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_group_min_size" {
  description = "Minimum number of nodes in the managed node group"
  type        = number
  default     = 1
}

variable "node_group_max_size" {
  description = "Maximum number of nodes in the managed node group"
  type        = number
  default     = 3
}

variable "node_group_desired_size" {
  description = "Desired number of nodes in the managed node group"
  type        = number
  default     = 1
}

variable "node_instance_types" {
  description = "List of instance types for the managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "Capacity type for nodes (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"
  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "Capacity type must be either ON_DEMAND or SPOT."
  }
}

############################
# Nitro Enclaves Variables
############################

variable "nitro_node_group_min_size" {
  description = "Minimum number of nodes in the Nitro Enclaves node group"
  type        = number
  default     = 0
}

variable "nitro_node_group_max_size" {
  description = "Maximum number of nodes in the Nitro Enclaves node group"
  type        = number
  default     = 2
}

variable "nitro_node_group_desired_size" {
  description = "Desired number of nodes in the Nitro Enclaves node group"
  type        = number
  default     = 1
}

variable "nitro_instance_types" {
  description = "List of Nitro Enclaves compatible instance types"
  type        = list(string)
  default     = ["c6a.xlarge", "c6a.2xlarge", "m6a.xlarge"]
  
  validation {
    condition = alltrue([
      for instance_type in var.nitro_instance_types :
      can(regex("^(c6a|c6i|c7a|c7i|m6a|m6i|m7a|m7i|r6a|r6i|r7a|r7i)", instance_type))
    ])
    error_message = "Instance types must be Nitro Enclaves compatible (c6a, c6i, c7a, c7i, m6a, m6i, m7a, m7i, r6a, r6i, r7a, r7i series)."
  }
}

variable "enable_nitro_enclaves" {
  description = "Enable Nitro Enclaves node group"
  type        = bool
  default     = true
} 