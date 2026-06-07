# Security groups for the Loki + Grafana stack.
#
# Traffic flows edge -> core:
#   log agents -> loki-alb  -> loki-gateway -> loki-internal (distributor / query-frontend)
#   browser    -> grafana   -> loki-gateway -> loki-internal

##################################################
# loki-alb  --  public edge, fronts the write/read path
##################################################

resource "aws_security_group" "loki-alb" {
  name        = "loki-alb"
  description = "Loki ALB SG"
  vpc_id      = data.aws_vpc.default.id
}

# Public entrance: HTTP :80 from the demo CIDR (log agents + admins).
resource "aws_vpc_security_group_ingress_rule" "loki-alb-http-ingress" {
  security_group_id = aws_security_group.loki-alb.id
  ip_protocol       = "tcp"
  cidr_ipv4         = var.admin_cidr
  from_port         = 80
  to_port           = 80
  description       = "Allow all HTTP"
}

# Grafana HTTPS entrance: :443 from the demo CIDR (browser -> ALB -> Grafana).
resource "aws_vpc_security_group_ingress_rule" "loki-alb-https-ingress" {
  security_group_id = aws_security_group.loki-alb.id
  ip_protocol       = "tcp"
  cidr_ipv4         = var.admin_cidr
  from_port         = 443
  to_port           = 443
  description       = "Grafana HTTPS via ALB"
}

# An ALB only ever forwards to its targets; allow-all egress is harmless here.
# TODO: tighten to loki-gateway:8080.
resource "aws_vpc_security_group_egress_rule" "loki-alb-egress" {
  security_group_id = aws_security_group.loki-alb.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Allow all egress"
}

##################################################
# grafana  --  public edge, the Grafana web UI
##################################################

resource "aws_security_group" "grafana" {
  name        = "grafana-edge"
  description = "Grafana SG"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_vpc_security_group_ingress_rule" "grafana-http" {
  security_group_id = aws_security_group.grafana.id
  ip_protocol       = "tcp"
  # Only the ALB reaches Grafana now (browser -> ALB:3000 -> here). Grafana
  # listens on 3000 (non-root container can't bind <1024).
  referenced_security_group_id = aws_security_group.loki-alb.id
  from_port                    = 3000
  to_port                      = 3000
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

##################################################
# loki-gateway  --  nginx reverse proxy (read/write routing)
##################################################

resource "aws_security_group" "loki-nginx-gateway" {
  name        = "loki-nginx-gateway"
  description = "Loki gateway SG"
  vpc_id      = data.aws_vpc.default.id
}

# Accept the ALB (the log agents' write/read path).
resource "aws_vpc_security_group_ingress_rule" "loki-gateway-from-alb" {
  security_group_id            = aws_security_group.loki-nginx-gateway.id
  referenced_security_group_id = aws_security_group.loki-alb.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

# Accept Grafana directly (its LogQL queries go straight to the gateway).
resource "aws_vpc_security_group_ingress_rule" "loki-http" {
  security_group_id = aws_security_group.loki-nginx-gateway.id
  ip_protocol       = "tcp"

  # Allow grafana dynamically
  referenced_security_group_id = aws_security_group.grafana.id

  # Not source and destination but "range" of ports
  from_port = 8080
  to_port   = 8080
}

# Harmless allow all egress
resource "aws_vpc_security_group_egress_rule" "loki-gateway-egress" {
  security_group_id = aws_security_group.loki-nginx-gateway.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Allow all egress"
}

##################################################
# loki-internal  --  the Loki component mesh
##################################################

resource "aws_security_group" "loki-internal" {
  name        = "loki-internal"
  description = "SG for Loki microservices to speak with each other"
  vpc_id      = data.aws_vpc.default.id
}

# Components reach each other via this self-rule.
resource "aws_vpc_security_group_ingress_rule" "loki-internal-self" {
  security_group_id            = aws_security_group.loki-internal.id
  referenced_security_group_id = aws_security_group.loki-internal.id
  ip_protocol                  = "-1"
  description                  = "Allow anyone wearing loki-internal-self to connect to any port of loki-internal-self"
}

# Let the gateway reach distributor/query-frontend.
# TODO: tighten to least privilege (tcp/3100 only?).
resource "aws_vpc_security_group_ingress_rule" "loki-internal-from-gateway" {
  security_group_id            = aws_security_group.loki-internal.id
  referenced_security_group_id = aws_security_group.loki-nginx-gateway.id
  ip_protocol                  = "-1"
}

# Let Grafana query the read path directly (Grafana -> query-frontend :3100).
resource "aws_vpc_security_group_ingress_rule" "loki-internal-from-grafana" {
  security_group_id            = aws_security_group.loki-internal.id
  referenced_security_group_id = aws_security_group.grafana.id
  ip_protocol                  = "tcp"
  from_port                    = 3100
  to_port                      = 3100
}

resource "aws_vpc_security_group_egress_rule" "loki-egress" {
  security_group_id = aws_security_group.loki-internal.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Allow all egress"
}
