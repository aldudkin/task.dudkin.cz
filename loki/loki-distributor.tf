resource "aws_cloudwatch_log_group" "loki-distributor-logs" {
  name              = "/ecs/loki-distributor"
  retention_in_days = 7
}

# Blueprint for services (images, ports, cpu, memory ...)
resource "aws_ecs_task_definition" "loki-distributor" {
  family                   = "loki-distributor"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # mandatory for Fargate (own ENI/IP/SG)
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs.arn # pulls image, writes logs; used by ECS agent
  task_role_arn = aws_iam_role.loki-iam-role.arn # task role - the identity application code assumes when it calls AWS

  container_definitions = jsonencode([{
    name         = "loki-distributor"
    image        = var.aws-loki-image
    essential    = true
    command = ["sh", "-c", "printf '%s' \"$LOKI_CONFIG\" > /tmp/loki.yaml && exec /usr/bin/loki -config.file=/tmp/loki.yaml -target=distributor"]
    environment = [{ name = "LOKI_CONFIG", value = file("${path.module}/../config/loki-config.yml") }] # file() reads from local disk at `terraform apply` time
    portMappings = [
        { containerPort = 3100, protocol = "tcp" },
        { containerPort = 9095, protocol = "tcp" },
        { containerPort = 7946, protocol = "tcp" }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.loki-distributor-logs.name
        "awslogs-region"        = var.aws-default-region
        "awslogs-stream-prefix" = "loki-distributor"
      }
    }
  }])
}

# Actuall task (count, which network to deploy to, attaching to LB ...)
resource "aws_ecs_service" "loki-distributor" {
  name            = "loki-distributor"
  cluster         = aws_ecs_cluster.loki-grafana.id
  task_definition = aws_ecs_task_definition.loki-distributor.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = data.aws_subnets.default.ids
    security_groups = [aws_security_group.loki-internal.id]
    # TODO: migrate to NAT Gateway in VPC and use only private adress, public IP here is only connecting to docker hub
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.distributor.arn
  }
}