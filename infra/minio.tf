# MinIO on ECS Fargate + ALB HTTPS (self-signed)
# S3-compatible object storage to replace AWS S3

locals {
  minio_container_name = "minio"
  minio_api_port       = 9000
  minio_console_port   = 9001
}

# --- CloudWatch Log Group for MinIO
resource "aws_cloudwatch_log_group" "minio" {
  name              = "/ecs/minio"
  retention_in_days = 14
}

# --- Self-signed certificate for MinIO ALB
resource "tls_private_key" "minio" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "minio" {
  private_key_pem = tls_private_key.minio.private_key_pem

  subject {
    common_name  = "minio.local"
    organization = "LearnerLab"
  }

  validity_period_hours = 24 * 365

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "minio" {
  private_key      = tls_private_key.minio.private_key_pem
  certificate_body = tls_self_signed_cert.minio.cert_pem

  lifecycle {
    create_before_destroy = true
  }
}

# --- Security Groups
resource "aws_security_group" "alb_minio_sg" {
  name        = "alb-minio-sg"
  description = "Allow HTTPS to MinIO ALB"
  vpc_id      = data.aws_vpc.default.id

  # API port (S3 compatible)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Console port
  ingress {
    from_port   = 9001
    to_port     = 9001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "minio_tasks_sg" {
  name        = "minio-tasks-sg"
  description = "Allow MinIO from its ALB and ECS tasks"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "MinIO API from ALB"
    from_port       = local.minio_api_port
    to_port         = local.minio_api_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_minio_sg.id]
  }

  ingress {
    description     = "MinIO Console from ALB"
    from_port       = local.minio_console_port
    to_port         = local.minio_console_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_minio_sg.id]
  }

  # Allow backend ECS tasks to access MinIO directly
  ingress {
    description     = "MinIO API from ECS tasks"
    from_port       = local.minio_api_port
    to_port         = local.minio_api_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- ALB for MinIO
resource "aws_lb" "minio" {
  name               = "minio-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_minio_sg.id]
  subnets            = data.aws_subnets.default.ids
}

# --- Target Groups
resource "aws_lb_target_group" "minio_api" {
  name        = "tg-minio-api"
  port        = local.minio_api_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id

  health_check {
    path                = "/minio/health/live"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }
}

resource "aws_lb_target_group" "minio_console" {
  name        = "tg-minio-console"
  port        = local.minio_console_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
    matcher             = "200-399"
  }
}

# --- Listeners
resource "aws_lb_listener" "minio_https" {
  load_balancer_arn = aws_lb.minio.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.minio.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.minio_api.arn
  }
}

resource "aws_lb_listener" "minio_console" {
  load_balancer_arn = aws_lb.minio.arn
  port              = 9001
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.minio.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.minio_console.arn
  }
}

# --- EFS for MinIO data persistence
resource "aws_efs_file_system" "minio" {
  creation_token = "minio-data"
  encrypted      = true

  tags = {
    Name = "minio-data"
  }
}

resource "aws_security_group" "efs_minio_sg" {
  name        = "efs-minio-sg"
  description = "Allow NFS from MinIO tasks"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.minio_tasks_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_efs_mount_target" "minio" {
  count           = length(data.aws_subnets.default.ids)
  file_system_id  = aws_efs_file_system.minio.id
  subnet_id       = data.aws_subnets.default.ids[count.index]
  security_groups = [aws_security_group.efs_minio_sg.id]
}

# --- SSM Parameters for MinIO credentials
resource "aws_ssm_parameter" "minio_root_user" {
  name  = "/lab/minio/root_user"
  type  = "SecureString"
  value = var.minio_root_user
}

resource "aws_ssm_parameter" "minio_root_password" {
  name  = "/lab/minio/root_password"
  type  = "SecureString"
  value = var.minio_root_password
}

# --- ECS Task Definition
resource "aws_ecs_task_definition" "minio" {
  family                   = "minio-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = data.aws_iam_role.labrole.arn
  task_role_arn            = data.aws_iam_role.labrole.arn

  volume {
    name = "minio-data"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.minio.id
      root_directory     = "/"
      transit_encryption = "ENABLED"
    }
  }

  container_definitions = jsonencode([
    {
      name  = local.minio_container_name
      image = var.minio_image

      command = ["server", "/data", "--console-address", ":9001"]

      portMappings = [
        {
          containerPort = local.minio_api_port
          protocol      = "tcp"
        },
        {
          containerPort = local.minio_console_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "MINIO_ROOT_USER", value = var.minio_root_user },
        { name = "MINIO_ROOT_PASSWORD", value = var.minio_root_password },
        { name = "MINIO_BROWSER_REDIRECT_URL", value = "https://${aws_lb.minio.dns_name}:9001" }
      ]

      mountPoints = [
        {
          sourceVolume  = "minio-data"
          containerPath = "/data"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.minio.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

# --- ECS Service
resource "aws_ecs_service" "minio" {
  name            = "minio-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.minio.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  platform_version = "1.4.0"  # Required for EFS support

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.minio_tasks_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.minio_api.arn
    container_name   = local.minio_container_name
    container_port   = local.minio_api_port
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.minio_console.arn
    container_name   = local.minio_container_name
    container_port   = local.minio_console_port
  }

  depends_on = [
    aws_lb_listener.minio_https,
    aws_lb_listener.minio_console,
    aws_efs_mount_target.minio
  ]
}

