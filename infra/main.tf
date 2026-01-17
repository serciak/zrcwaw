terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Default VPC + subnets
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_route_tables" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Role IAM
data "aws_iam_role" "labrole" {
  name = "LabRole"
}

# Cognito
# (usunięte – zastąpione przez Keycloak/OIDC na ECS)

resource "random_id" "suffix" {
  byte_length = 4
}

# S3 bucket removed - using MinIO instead
# If you need AWS S3, uncomment the following resources:
#
# resource "aws_s3_bucket" "files" {
#   bucket        = "todos-files-bucket-${random_id.suffix.hex}"
#   force_destroy = true
# }
#
# resource "aws_s3_bucket_public_access_block" "files" {
#   bucket                  = aws_s3_bucket.files.id
#   block_public_acls       = true
#   block_public_policy     = true
#   ignore_public_acls      = true
#   restrict_public_buckets = true
# }
#
# resource "aws_vpc_endpoint" "s3" {
#   vpc_id            = data.aws_vpc.default.id
#   service_name      = "com.amazonaws.${var.region}.s3"
#   vpc_endpoint_type = "Gateway"
#   route_table_ids   = data.aws_route_tables.default.ids
# }

# Log groups
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/backend"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/frontend"
  retention_in_days = 14
}

# Security Groups
# RDS security group removed - using PostgreSQL on Fargate instead
# See postgres.tf for PostgreSQL security group configuration

# resource "aws_security_group" "lambda_sg" {
#   name        = "lambda-sg"
#   description = "Allow Lambda to access RDS"
#   vpc_id      = data.aws_vpc.default.id
#
#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }

resource "aws_security_group" "alb_backend_sg" {
  name        = "alb-backend-sg"
  description = "Allow HTTP and HTTPS to backend ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
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

resource "aws_security_group" "alb_frontend_sg" {
  name        = "alb-frontend-sg"
  description = "Allow HTTP and HTTPS to frontend ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
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

resource "aws_security_group" "ecs_tasks_sg" {
  name        = "ecs-tasks-sg"
  description = "Allow ALBs to reach ECS tasks"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Backend from ALB"
    from_port       = var.backend_port
    to_port         = var.backend_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_backend_sg.id]
  }

  ingress {
    description     = "Frontend from ALB"
    from_port       = var.frontend_port
    to_port         = var.frontend_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_frontend_sg.id]
  }

  # Wyjście backend -> Keycloak HTTPS (Fargate -> ALB Keycloak)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# RDS PostgreSQL removed - using PostgreSQL on Fargate instead
# See postgres.tf for self-hosted PostgreSQL configuration

# ECS Cluster
resource "aws_ecs_cluster" "this" {
  name = "lab-ecs-cluster"
}

# Load Balancers
resource "aws_lb" "backend" {
  name               = "backend-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_backend_sg.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb" "frontend" {
  name               = "frontend-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_frontend_sg.id]
  subnets            = data.aws_subnets.default.ids
}

# Target Groups
resource "aws_lb_target_group" "backend" {
  name        = "tg-backend"
  port        = var.backend_port
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

resource "aws_lb_target_group" "frontend" {
  name        = "tg-frontend"
  port        = var.frontend_port
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

# Listeners

# Self-signed certificate for backend ALB
resource "tls_private_key" "backend" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "backend" {
  private_key_pem = tls_private_key.backend.private_key_pem

  subject {
    common_name  = "backend.local"
    organization = "LearnerLab"
  }

  validity_period_hours = 24 * 365

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "backend" {
  private_key      = tls_private_key.backend.private_key_pem
  certificate_body = tls_self_signed_cert.backend.cert_pem

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "backend_http" {
  load_balancer_arn = aws_lb.backend.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "backend_https" {
  load_balancer_arn = aws_lb.backend.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.backend.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}

# Self-signed certificate for frontend ALB
resource "tls_private_key" "frontend" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "frontend" {
  private_key_pem = tls_private_key.frontend.private_key_pem

  subject {
    common_name  = "frontend.local"
    organization = "LearnerLab"
  }

  validity_period_hours = 24 * 365

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "frontend" {
  private_key      = tls_private_key.frontend.private_key_pem
  certificate_body = tls_self_signed_cert.frontend.cert_pem

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "frontend_http" {
  load_balancer_arn = aws_lb.frontend.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "frontend_https" {
  load_balancer_arn = aws_lb.frontend.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.frontend.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# Task Definitions
locals {
  backend_container_name  = "backend"
  frontend_container_name = "frontend"
}

resource "aws_ecs_task_definition" "backend" {
  family                   = "backend-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = data.aws_iam_role.labrole.arn
  task_role_arn            = data.aws_iam_role.labrole.arn

  container_definitions = jsonencode([
    {
      name  = local.backend_container_name
      image = var.backend_image
      portMappings = [
        {
          containerPort = var.backend_port
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "BACKEND_HOST", value = "0.0.0.0" },
        { name = "BACKEND_PORT", value = tostring(var.backend_port) },
        { name = "MEDIA_ROOT", value = "/app/uploads" },
        { name = "CORS_ORIGINS", value = "*" },
        { name = "DATABASE_URL", value = "postgresql+psycopg2://${var.db_username}:${var.db_password}@${aws_lb.postgres.dns_name}:5432/${var.db_name}" },
        { name = "AWS_REGION", value = var.region },

        # MinIO (S3-compatible storage)
        { name = "S3_BUCKET_NAME", value = var.minio_bucket_name },
        { name = "S3_ENDPOINT_URL", value = "https://${aws_lb.minio.dns_name}" },
        { name = "S3_PUBLIC_ENDPOINT_URL", value = "https://${aws_lb.minio.dns_name}" },
        { name = "S3_ACCESS_KEY", value = var.minio_root_user },
        { name = "S3_SECRET_KEY", value = var.minio_root_password },

        # OIDC / Keycloak
        { name = "OIDC_ISSUER_URL", value = "https://${aws_lb.keycloak.dns_name}/realms/${var.oidc_realm}" },
        { name = "OIDC_AUDIENCE", value = var.oidc_api_audience },
        { name = "SSL_VERIFY", value = "false" }  # dla self-signed certs w środowisku lab
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.backend.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = "frontend-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = data.aws_iam_role.labrole.arn
  task_role_arn            = data.aws_iam_role.labrole.arn

  container_definitions = jsonencode([
    {
      name  = local.frontend_container_name
      image = var.frontend_image
      portMappings = [
        {
          containerPort = var.frontend_port
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "API_URL", value = "https://${aws_lb.backend.dns_name}" },

        # OIDC / Keycloak
        { name = "OIDC_AUTHORITY", value = "https://${aws_lb.keycloak.dns_name}/realms/${var.oidc_realm}" },
        { name = "OIDC_CLIENT_ID", value = var.oidc_spa_client_id },
        { name = "OIDC_REDIRECT_URI", value = "https://${aws_lb.frontend.dns_name}/auth/callback" },
        { name = "OIDC_POST_LOGOUT_REDIRECT_URI", value = "https://${aws_lb.frontend.dns_name}/" },
        { name = "OIDC_SCOPE", value = "openid profile email" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.frontend.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

# ECS Services
resource "aws_ecs_service" "backend" {
  name            = "backend-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_tasks_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = local.backend_container_name
    container_port   = var.backend_port
  }

  depends_on = [
    aws_lb_listener.backend_http,
    aws_ecs_service.postgres
  ]
}

resource "aws_ecs_service" "frontend" {
  name            = "frontend-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_tasks_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = local.frontend_container_name
    container_port   = var.frontend_port
  }

  depends_on = [
    aws_lb_listener.frontend_http
  ]
}
