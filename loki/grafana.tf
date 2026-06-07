# Grafana web UI (LogQL). Reaches Loki's read path directly at the query-frontend
# (http://loki-query-frontend.loki.internal:3100). The Loki datasource is
# auto-provisioned by a busybox init container (same pattern as the components),
# so it works on first login. Admin password comes from an SSM SecureString that
# is created OUT OF BAND -- Terraform only references its ARN, never its value.

# This file was mainly written by Claude

data "aws_caller_identity" "current" {}

# The AWS-managed key that encrypts SSM SecureStrings (exists once any
# SecureString has been created in this account/region -- i.e. after you run the
# put-parameter command).
data "aws_kms_key" "ssm" {
  key_id = "alias/aws/ssm"
}

locals {
  grafana_pw_param_arn = "arn:aws:ssm:${var.aws-default-region}:${data.aws_caller_identity.current.account_id}:parameter${var.grafana_admin_password_ssm_name}"

  grafana_datasource_yaml = <<-EOT
    apiVersion: 1
    datasources:
      - name: Loki
        type: loki
        access: proxy
        url: http://loki-query-frontend.loki.internal:3100
        isDefault: true
  EOT
}

# Allow the ECS execution role to fetch + decrypt the Grafana password secret.
# (ECS injects `secrets` using the EXECUTION role, at task launch.)
resource "aws_iam_role_policy" "ecs-grafana-secret" {
  name = "grafana-admin-password-read"
  role = aws_iam_role.ecs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ssm:GetParameters"
        Resource = local.grafana_pw_param_arn
      },
      {
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = data.aws_kms_key.ssm.arn
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "grafana" {
  name              = "/ecs/grafana"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "grafana" {
  family                   = "grafana"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs.arn # pull image, write logs, fetch the secret

  # Shared scratch volume: init writes the datasource file, grafana reads it.
  volume {
    name = "provisioning"
  }

  container_definitions = jsonencode([
    {
      # busybox writes the datasource provisioning file to the shared volume.
      name        = "provision-init"
      image       = var.busybox-image
      essential   = false
      command     = ["sh", "-c", "mkdir -p /shared/datasources && printf '%s' \"$DATASOURCE_YAML\" > /shared/datasources/loki.yaml"]
      environment = [{ name = "DATASOURCE_YAML", value = local.grafana_datasource_yaml }]
      mountPoints = [{ sourceVolume = "provisioning", containerPath = "/shared", readOnly = false }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.grafana.name
          "awslogs-region"        = var.aws-default-region
          "awslogs-stream-prefix" = "provision-init"
        }
      }
    },
    {
      name      = "grafana"
      image     = var.aws-grafana-image
      essential = true
      environment = [
        { name = "GF_PATHS_PROVISIONING", value = "/shared" }, # read provisioning from the shared volume
        { name = "GF_USERS_ALLOW_SIGN_UP", value = "false" },
        { name = "GF_AUTH_ANONYMOUS_ENABLED", value = "false" },
      ]
      # Password injected from SSM at launch -- ARN only, value never in the task def.
      secrets = [
        { name = "GF_SECURITY_ADMIN_PASSWORD", valueFrom = local.grafana_pw_param_arn },
      ]
      mountPoints = [{ sourceVolume = "provisioning", containerPath = "/shared", readOnly = true }]
      dependsOn   = [{ containerName = "provision-init", condition = "SUCCESS" }]
      portMappings = [
        { containerPort = 3000, protocol = "tcp" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.grafana.name
          "awslogs-region"        = var.aws-default-region
          "awslogs-stream-prefix" = "grafana"
        }
      }
    }
  ])
}

# --- Stable URL: a second ALB listener on :3000 -> Grafana ---------------------
# Browser -> ALB :3000 (stable DNS) -> this target group -> Grafana task :3000.

resource "aws_lb_target_group" "grafana" {
  name        = "grafana"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip" # Fargate tasks register by ENI IP

  vpc_id = data.aws_vpc.default.id

  health_check {
    protocol = "HTTP"
    path     = "/api/health" # Grafana returns 200 here once it's up
    matcher  = "200"
  }
}

resource "aws_ecs_service" "grafana" {
  name            = "grafana"
  cluster         = aws_ecs_cluster.loki-grafana.id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  # Give Grafana time to boot before the ALB health check can fail the task.
  health_check_grace_period_seconds = 60

  network_configuration {
    subnets         = data.aws_subnets.default.ids
    security_groups = [aws_security_group.grafana.id]
    # Public IP still needed for the Docker Hub image pull (no NAT yet).
    assign_public_ip = true
  }

  # Register tasks into the ALB target group.
  load_balancer {
    target_group_arn = aws_lb_target_group.grafana.arn
    container_name   = "grafana"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.loki-alb-listener]
}
