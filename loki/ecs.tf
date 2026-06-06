resource "aws_ecs_cluster" "loki-grafana" {
  name = "loki-grafana"
}
# private Route 53 hosted zone needed in microservices mode
resource "aws_service_discovery_private_dns_namespace" "loki-grafana" {
  name = "loki.internal"
  vpc  = data.aws_vpc.default.id
}
