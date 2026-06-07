# nginx "gateway" that fronts the Loki components:
#   - /loki/api/v1/push  -> distributor   (write path)
#   - everything else /loki/ -> query-frontend (read path)
# It listens on :8080 (the ALB target group + loki-gateway SG port).
#
# Delivered inline: the stock nginxinc/nginx-unprivileged image already runs as
# non-root, listens on 8080, and includes /etc/nginx/conf.d/*.conf inside its
# http{} block -- so we only supply the server block below, written to
# conf.d/default.conf by the container command (see the task definition).

# This file was mainly written by Claude

locals {
  gateway_nginx_conf = <<-EOT
    # Re-resolve upstream names at REQUEST time, not startup. Two reasons:
    #   1) the Loki services may not exist yet when nginx boots (gateway-first),
    #   2) Cloud Map (loki.internal) IPs change as Fargate tasks come and go.
    # 169.254.169.253 is the VPC's built-in DNS resolver (always reachable).
    # Using a $variable in proxy_pass is what triggers this runtime resolution.
    resolver 169.254.169.253 valid=10s ipv6=off;

    server {
      listen 8080;

      # ALB health check hits "/": answered locally, needs no upstream,
      # so the target goes healthy even before the Loki components exist.
      location = / {
        return 200 "gateway ok\n";
      }

      # WRITE path -> distributor
      location = /loki/api/v1/push {
        set $distributor "loki-distributor.loki.internal";
        proxy_pass http://$distributor:3100$request_uri;
      }

      # READ paths (query, query_range, labels, series, ...) -> query-frontend
      location /loki/ {
        set $query_frontend "loki-query-frontend.loki.internal";
        proxy_pass http://$query_frontend:3100$request_uri;
      }
    }
  EOT
}

resource "aws_cloudwatch_log_group" "nginx-gateway-logs" {
  name              = "/ecs/loki-nginx-gateway"
  retention_in_days = 7
}

# Blueprint for services (images, ports, cpu, memory ...)
resource "aws_ecs_task_definition" "loki-nginx-gateway" {
  family                   = "loki-nginx-gateway"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # mandatory for Fargate (own ENI/IP/SG)
  cpu                      = "256"    # strings; smallest size
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs.arn # pulls image, writes logs

  container_definitions = jsonencode([{
    name         = "loki-nginx-gateway" # service's load_balancer block references this
    image        = var.aws-nginx-image
    essential    = true
    command      = ["/bin/sh", "-c", "printf '%s' \"$NGINX_CONF\" > /etc/nginx/conf.d/default.conf && exec nginx -g 'daemon off;'"]
    environment  = [{ name = "NGINX_CONF", value = local.gateway_nginx_conf }]
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.nginx-gateway-logs.name
        "awslogs-region"        = var.aws-default-region
        "awslogs-stream-prefix" = "loki-nginx-gateway"
      }
    }
  }])
}

# Actuall task (count, which network to deploy to, attaching to LB ...)
resource "aws_ecs_service" "loki-nginx-gateway" {
  name            = "loki-nginx-gateway"
  cluster         = aws_ecs_cluster.loki-grafana.id
  task_definition = aws_ecs_task_definition.loki-nginx-gateway.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = data.aws_subnets.default.ids
    security_groups = [aws_security_group.loki-nginx-gateway.id]
    # TODO: migrate to NAT Gateway in VPC and use only private adress, public IP here is only connecting to docker hub
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.loki-nginx-gateway-target-group.arn
    container_name   = "loki-nginx-gateway" # must match the name in container_definitions
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.loki-alb-listener]
}

