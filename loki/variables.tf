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

variable "aws-grafana-image" {
  type    = string
  default = "grafana/grafana:11.4.0"
}

# aws ssm put-parameter --name /loki/grafana-admin-password --type SecureString --value 'VALUE' --region eu-central-1
# aws ssm describe-parameters --region eu-central-1
variable "grafana_admin_password_ssm_name" {
  type    = string
  default = "/loki/grafana-admin-password"
}

# ACM certificate for the Grafana HTTPS listener. Created out of band (console)
# TODO: move to Terraform
variable "grafana_acm_certificate_arn" {
  type    = string
  default = "arn:aws:acm:eu-central-1:366112400496:certificate/4e2d5142-c48d-4d91-aa45-dd61c7f6f9e8"
}

# FireLens demo (ECS log collection via Fluent Bit sidecar).
variable "aws-fluentbit-image" {
  type    = string
  default = "amazon/aws-for-fluent-bit:stable" # bundles the Loki output plugin
}

variable "aws-flog-image" {
  type    = string
  default = "mingrammer/flog:0.4.3"
}