# =============================================================================
# Variables
# =============================================================================

variable "region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-west-2"
}

variable "owner" {
  description = "Owner tag for resources"
  type        = string
}
