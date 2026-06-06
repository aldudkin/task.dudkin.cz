##### Loki -> S3  #####

data "aws_iam_policy_document" "loki-iam-policy" {
  statement {
    actions = [
      "s3:ListBucket",
    ]

    resources = [
      "arn:aws:s3:::${var.loki_s3_bucket_name}",
    ]
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = [
      "arn:aws:s3:::${var.loki_s3_bucket_name}/*"
    ]
  }
}

resource "aws_iam_policy" "loki-iam-policy" {
  name   = var.loki-iam-policy-name
  policy = data.aws_iam_policy_document.loki-iam-policy.json
}

resource "aws_iam_role" "loki-iam-role" {
  name = var.loki-iam-role-name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com" # Data plane (ecs.amazonaws.com is for control plane)
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "loki-iam-role-attach" {
  role       = aws_iam_role.loki-iam-role.name
  policy_arn = aws_iam_policy.loki-iam-policy.arn
}

##### ECS Image pulling + Cloudwatch logs  #####

resource "aws_iam_role" "ecs" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "test-attach" {
  role       = aws_iam_role.ecs.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
