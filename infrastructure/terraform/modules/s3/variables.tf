variable "environment" {
  type        = string
  description = "Environment name for resource naming and tagging (dev/staging/prod)"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket for media storage"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.bucket_name))
    error_message = "Bucket name must be lowercase alphanumeric and can contain hyphens and periods."
  }
}

variable "versioning_enabled" {
  type        = bool
  description = "Enable/disable versioning for the S3 bucket"
  default     = true
}

variable "encryption_configuration" {
  type = object({
    sse_algorithm     = string
    kms_master_key_id = optional(string)
  })
  description = "Server-side encryption configuration for the bucket"
  default = {
    sse_algorithm = "AES256"
  }
  validation {
    condition     = contains(["AES256", "aws:kms"], var.encryption_configuration.sse_algorithm)
    error_message = "SSE algorithm must be either AES256 or aws:kms."
  }
}

variable "lifecycle_rules" {
  type = list(object({
    id                       = string
    enabled                  = bool
    prefix                   = optional(string)
    expiration_days         = optional(number)
    transition_days         = optional(number)
    transition_storage_class = optional(string)
  }))
  description = "Lifecycle management rules for media objects"
  default     = []
  validation {
    condition     = alltrue([for rule in var.lifecycle_rules : contains(["STANDARD_IA", "ONEZONE_IA", "GLACIER", "DEEP_ARCHIVE"], rule.transition_storage_class) if rule.transition_storage_class != null])
    error_message = "Invalid storage class specified in lifecycle rules."
  }
}

variable "cors_rules" {
  type = list(object({
    allowed_headers = list(string)
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = optional(list(string))
    max_age_seconds = optional(number)
  }))
  description = "CORS configuration rules for client-side access"
  default     = []
  validation {
    condition     = alltrue([for rule in var.cors_rules : alltrue([for method in rule.allowed_methods : contains(["GET", "PUT", "POST", "DELETE", "HEAD"], method)])])
    error_message = "Invalid HTTP method in CORS rules."
  }
}

variable "public_access_block" {
  type = object({
    block_public_acls       = bool
    block_public_policy     = bool
    ignore_public_acls      = bool
    restrict_public_buckets = bool
  })
  description = "Configuration for blocking public access to the bucket"
  default = {
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }
}

variable "replication_configuration" {
  type = object({
    role                     = optional(string)
    destination_bucket_arn   = optional(string)
    destination_region       = optional(string)
    replica_storage_class    = optional(string)
    replication_enabled      = optional(bool)
  })
  description = "Cross-region replication configuration for disaster recovery"
  default = {
    replication_enabled = false
  }
  validation {
    condition     = var.replication_configuration.replica_storage_class == null || contains(["STANDARD", "STANDARD_IA", "ONEZONE_IA"], var.replication_configuration.replica_storage_class)
    error_message = "Invalid storage class for replication configuration."
  }
}

variable "tags" {
  type        = map(string)
  description = "Resource tags for the S3 bucket and objects"
  default     = {}
  validation {
    condition     = length(var.tags) <= 50
    error_message = "Maximum of 50 tags allowed per resource."
  }
}