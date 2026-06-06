variable "loki_s3_bucket_name" {
  description = "Name of the Loki chunk/index bucket"
  type        = string
  default     = "loki-data-366112400496-eu-central-1"
}

variable "loki-iam-policy-name" {
  description = "Name of the Loki IAM policy"
  type        = string
  default     = "loki-iam-policy"
}

variable "loki-iam-role-name" {
  description = "Name of the Loki IAM role"
  type        = string
  default     = "loki-iam-role"
}