resource "aws_ecs_cluster" "loki-grafana" {
  name = "loki-grafana"
}
# private Route 53 hosted zone needed in microservices mode
resource "aws_service_discovery_private_dns_namespace" "loki-grafana" {
  name = "loki.internal" # Domain name
  vpc  = data.aws_vpc.default.id
}

# Self updating record set under loki.internal, will resolve to N ip addresses
resource "aws_service_discovery_service" "distributor" {
  name = "loki-distributor" # -> becomes loki-distributor.loki.internal

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.loki-grafana.id
    routing_policy = "MULTIVALUE" # return ALL task IPs, not just one
    dns_records {
      type = "A"
      ttl  = 10
    }
  }
}

resource "aws_service_discovery_service" "ingester" {
  name = "loki-ingester"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.loki-grafana.id
    routing_policy = "MULTIVALUE"
    dns_records {
      type = "A"
      ttl  = 10
    }
  }
}

resource "aws_service_discovery_service" "index-gateway" {
  name = "loki-index-gateway"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.loki-grafana.id
    routing_policy = "MULTIVALUE"
    dns_records {
      type = "A"
      ttl  = 10
    }
  }
}

resource "aws_service_discovery_service" "compactor" {
  name = "loki-compactor"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.loki-grafana.id
    routing_policy = "MULTIVALUE"
    dns_records {
      type = "A"
      ttl  = 10
    }
  }
}

resource "aws_service_discovery_service" "loki-query-scheduler" {
  name = "loki-loki-query-scheduler"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.loki-grafana.id
    routing_policy = "MULTIVALUE"
    dns_records {
      type = "A"
      ttl  = 10
    }
  }
}

resource "aws_service_discovery_service" "loki-query-frontend" {
  name = "loki-loki-query-frontend"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.loki-grafana.id
    routing_policy = "MULTIVALUE"
    dns_records {
      type = "A"
      ttl  = 10
    }
  }
}

# TODO: rewrite to for_each