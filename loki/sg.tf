#### Grafana #####

resource "aws_security_group" "grafana" {
  name        = "grafana-edge"
  description = "Grafana SG"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_vpc_security_group_ingress_rule" "grafana-http" {
  security_group_id = aws_security_group.grafana.id
  ip_protocol       = "tcp"
  cidr_ipv4         = var.admin_cidr
  # Not source and destination but "range" of ports
  from_port = 80
  to_port   = 80
}

# Probably won't work with fargate tasks anyway but harmless
resource "aws_vpc_security_group_ingress_rule" "grafana-icmp" {
  security_group_id = aws_security_group.grafana.id
  ip_protocol       = "icmp"
  cidr_ipv4         = "0.0.0.0/0"
  # All ICMP types
  from_port = -1
  to_port   = -1
}

resource "aws_vpc_security_group_egress_rule" "grafana-out" {
  security_group_id = aws_security_group.grafana.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

#### Loki #####

resource "aws_security_group" "loki" {
  name        = "loki-edge"
  description = "Loki SG"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_vpc_security_group_ingress_rule" "loki-http" {
  security_group_id = aws_security_group.loki.id
  ip_protocol       = "tcp"

  # Allow grafana dynamically
  referenced_security_group_id = aws_security_group.grafana.id

  # Not source and destination but "range" of ports
  from_port = 3100
  to_port   = 3100
}

resource "aws_vpc_security_group_egress_rule" "loki-out" {
  security_group_id = aws_security_group.loki.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}