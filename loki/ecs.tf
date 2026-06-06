resource "aws_ecs_cluster" "loki-grafana" {
  name = "loki-grafana"
  service_connect_defaults {
    # Shared directory of http hostnames
    namespace = aws_service_discovery_http_namespace.loki-grafana.arn
  }
}

# Allows using dynamic http hostnames instead of IPs
resource "aws_service_discovery_http_namespace" "loki-grafana" {
  name = var.loki-grafana-http-namespace-name
}
