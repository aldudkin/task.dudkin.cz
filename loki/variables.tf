variable "loki-s3-bucket-name" {
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

variable "admin_cidr" {
  description = "Trusted subnet"
  type        = string
  # Intentionally open to the internet for demo access; protected by nginx basic auth
  default = "0.0.0.0/0"
}

variable "aws-default-region" {
  type    = string
  default = "eu-central-1"
}

variable "aws-nginx-image" {
  type    = string
  default = "nginxinc/nginx-unprivileged:1.27-alpine"
}

variable "aws-loki-image" {
  type    = string
  default = "grafana/loki:3.7.2"
}

variable "busybox-image" {
  type    = string
  default = "busybox:1.37"
}