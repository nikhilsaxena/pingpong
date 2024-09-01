variable "cluster_name" {
  type        = string
  description = "Cluster Name"
  default     = "demo-eks"
}

variable "cluster_role_name" {
  type        = string
  description = "Cluster Role Name"
  default     = "eksClusterRole"
}

variable "node_role_name" {
  type        = string
  description = "Node Role Name"
  default     = "eks-demo-node"
}

variable "node_group_desired_capacity" {
  type        = number
  description = "Desired capacity of nodegroup ASG."
  default     = 2
}
variable "node_group_max_size" {
  type        = number
  description = "Maximum size of nodegroup ASG."
  default     = 3
}

variable "node_group_min_size" {
  type        = number
  description = "Minimum size of nodegroup ASG."
  default     = 1
}

