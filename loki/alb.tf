# internet :80  ->  aws_lb.loki-alb  ->  aws_lb_listener (:80, forward)
# -> aws_lb_target_group.loki-gateway-target-group (:8080)  ->  [nginx gateway tasks]


resource "aws_lb" "loki-alb" {
  name               = "loki-alb"
  internal           = false         # Public DNS name and IP
  load_balancer_type = "application" # L7 LB
  security_groups    = [aws_security_group.loki-alb.id]
  subnets            = data.aws_subnets.default.ids # By default has a list of 3 AZ subnets
}

# Makes the ALB listen on a port and decides what to do with arriving requests
resource "aws_lb_listener" "loki-alb-listener" {
  load_balancer_arn = aws_lb.loki-alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.loki-gateway-target-group.arn
  }
}

resource "aws_lb_target_group" "loki-gateway-target-group" {
  name        = "loki-gateway-target-group"
  port        = 8080 # the port on the TARGET the ALB connects TO
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip" # The only viable option for ECS ENI's

  # The ALB probes each target here; only "healthy" targets get traffic.
  # Wide matcher so a bare nginx 200 OR a redirect (3xx) on "/" still passes.
  # TODO: point at the gateway's real health path once the nginx config exists.
  health_check {
    protocol = "HTTP"
    path     = "/"
    matcher  = "200-399"
  }
}
