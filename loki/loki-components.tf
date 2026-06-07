# All Loki microservice components share ONE image + ONE config and differ only
# by their -target flag (and whether anything resolves them by DNS)

locals {
  loki_components = toset([
    "distributor",
    "ingester",
    "query-frontend",
    "query-scheduler",
    "querier",
    "index-gateway",
    "compactor"
  ])
}

resource "aws_service_discovery_service" "loki" {
  for_each = local.loki_components # Hard requirement to use a set

  name = "loki-${each.key}" # -> loki-<key>.loki.internal

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.loki-grafana.id
    routing_policy = "MULTIVALUE" # return ALL task IPs (memberlist needs them all)
    dns_records {
      type = "A"
      ttl  = 10
    }
  }
}

# One log group per component.
resource "aws_cloudwatch_log_group" "loki" {
  for_each          = local.loki_components
  name              = "/ecs/loki-${each.key}"
  retention_in_days = 7
}

# One task-definition blueprint per component (same image/config, different -target).
resource "aws_ecs_task_definition" "loki" {
  for_each = local.loki_components

  family                   = "loki-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs.arn           # pull image + write logs
  task_role_arn            = aws_iam_role.loki-iam-role.arn # runtime S3 access

  # Scratch volume shared between the two containers in this task.
  # No host/EFS config = an ephemeral Fargate volume, gone when the task stops.
  volume {
    name = "config"
  }

  container_definitions = jsonencode([
    {
      # One-time sidecar container to inject config file during terraform apply
      name      = "config-init"
      image     = var.busybox-image
      essential = false
      # Config must be written inside /shared as two containers do not share the same root FS
      command     = ["sh", "-c", "printf '%s' \"$LOKI_CONFIG\" > /shared/loki.yaml"]
      environment = [{ name = "LOKI_CONFIG", value = file("${path.module}/../config/loki-config.yml") }]
      mountPoints = [{ sourceVolume = "config", containerPath = "/shared", readOnly = false }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.loki[each.key].name
          "awslogs-region"        = var.aws-default-region
          "awslogs-stream-prefix" = "config-init"
        }
      }
    },
    {
      # Set entryPoint + command explicitly so the flags definitely reach loki
      # (relying on the image ENTRYPOINT to absorb `command` proved unreliable).
      name        = "loki-${each.key}"
      image       = var.aws-loki-image
      essential   = true
      entryPoint  = ["/usr/bin/loki"]
      command     = ["-config.file=/shared/loki.yaml", "-target=${each.key}"]
      mountPoints = [{ sourceVolume = "config", containerPath = "/shared", readOnly = true }]
      # Wait until config-init has written the file and exited 0.
      dependsOn = [{ containerName = "config-init", condition = "SUCCESS" }]
      portMappings = [
        { containerPort = 3100, protocol = "tcp" }, # HTTP
        { containerPort = 9095, protocol = "tcp" }, # gRPC
        { containerPort = 7946, protocol = "tcp" }, # memberlist
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.loki[each.key].name
          "awslogs-region"        = var.aws-default-region
          "awslogs-stream-prefix" = "loki-${each.key}"
        }
      }
    }
  ])
}

# One service per component (runs it, wears the mesh SG, registers in Cloud Map).
resource "aws_ecs_service" "loki" {
  for_each = local.loki_components

  name            = "loki-${each.key}"
  cluster         = aws_ecs_cluster.loki-grafana.id
  task_definition = aws_ecs_task_definition.loki[each.key].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = data.aws_subnets.default.ids
    security_groups = [aws_security_group.loki-internal.id]
    # TODO: private subnets + NAT gatewayin VPC; public IP is only to reach Docker Hub.
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.loki[each.key].arn
  }
}
