resource "aws_ecs_cluster" "loki-grafana" {
  name = "loki-grafana"
}
# private Route 53 hosted zone needed in microservices mode.
# The per-component aws_service_discovery_service records live in loki-components.tf (for_each).
resource "aws_service_discovery_private_dns_namespace" "loki-grafana" {
  name = "loki.internal" # Domain name
  vpc  = data.aws_vpc.default.id
}