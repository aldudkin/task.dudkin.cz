# Demonstrates the README's MAIN requirement: log collection from ECS via AWS
# FireLens (Fluent Bit sidecar). An app container (flog) writes Apache logs to
# stdout; ECS routes that stdout THROUGH the Fluent Bit sidecar, which ships it
# to Loki's distributor with the "loki" output plugin. No app code involved.
#
#   app (stdout) --awsfirelens--> log_router (Fluent Bit) --loki--> loki-distributor:3100

# This file was mostly written by Claude

# --- Networking: a dedicated SG; only needs to reach the distributor ----------
resource "aws_security_group" "firelens-demo" {
  name        = "firelens-demo"
  description = "Demo ECS app shipping logs to Loki via FireLens"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_vpc_security_group_egress_rule" "firelens-demo-egress" {
  security_group_id = aws_security_group.firelens-demo.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Allow all egress (image pull + push to distributor)"
}

# Let the demo's Fluent Bit reach the distributor's push API.
resource "aws_vpc_security_group_ingress_rule" "loki-internal-from-firelens" {
  security_group_id            = aws_security_group.loki-internal.id
  referenced_security_group_id = aws_security_group.firelens-demo.id
  ip_protocol                  = "tcp"
  from_port                    = 3100
  to_port                      = 3100
}

# --- The task ------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "firelens-demo" {
  name              = "/ecs/firelens-demo"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "firelens-demo" {
  family                   = "firelens-demo"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs.arn # pull images + write router logs

  container_definitions = jsonencode([
    {
      # The Fluent Bit sidecar. firelensConfiguration makes ECS treat it as the
      # log router for any container using logDriver=awsfirelens.
      name                  = "log_router"
      image                 = var.aws-fluentbit-image
      essential             = true
      firelensConfiguration = { type = "fluentbit" }
      logConfiguration = { # the router's OWN logs -> CloudWatch (diagnostics)
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.firelens-demo.name
          "awslogs-region"        = var.aws-default-region
          "awslogs-stream-prefix" = "log_router"
        }
      }
    },
    {
      # The "application": flog writes Apache logs to stdout. Its logConfiguration
      # options below become the Fluent Bit [OUTPUT] -> the Loki plugin.
      name      = "app"
      image     = var.aws-flog-image
      essential = true
      command   = ["-l", "-d", "1s", "-f", "apache_combined"] # infinite, 1/sec, to stdout
      dependsOn = [{ containerName = "log_router", condition = "START" }]
      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          Name = "loki"
          host = "loki-distributor.loki.internal"
          port = "3100"
          # No "uri" option: the loki plugin always pushes to /loki/api/v1/push.
          labels      = "job=ecs-firelens, source=ecs" # Used as a selector in LogQL; Are indexed (log text itself wont be)
          label_keys  = "$container_name"
          line_format = "key_value"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "firelens-demo" {
  name            = "firelens-demo"
  cluster         = aws_ecs_cluster.loki-grafana.id
  task_definition = aws_ecs_task_definition.firelens-demo.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = data.aws_subnets.default.ids
    security_groups = [aws_security_group.firelens-demo.id]
    # Public IP only to pull images from Docker Hub; the push to Loki is internal.
    assign_public_ip = true
  }
}
