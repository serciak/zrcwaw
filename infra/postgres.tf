# PostgreSQL on ECS Fargate + EFS for data persistence
# Self-hosted PostgreSQL to replace AWS RDS
# Uses internal NLB instead of Service Discovery (not available in Learner Labs)

# Cieszę się, że wszystko działa! 👍
# Podsumowując różnicę między ALB a NLB:
# ALB (Application Load Balancer)
# Warstwa 7 (HTTP/HTTPS)
# Rozumie zawartość żądań HTTP (nagłówki, ścieżki URL, cookies)
# Może routować ruch na podstawie URL, np. /api → backend, /static → frontend
# Obsługuje terminację SSL/TLS
# Użycie: aplikacje webowe, API REST, WebSocket
# NLB (Network Load Balancer)
# Warstwa 4 (TCP/UDP)
# Nie rozumie zawartości - przekazuje surowe pakiety TCP/UDP
# Ekstremalnie niski latency (~mikrosekundy)
# Zachowuje oryginalny IP klienta
# Użycie: bazy danych, gRPC, MQTT, gaming, protokoły binarne
# W Twoim projekcie:
# Serwis
# Load Balancer
# Dlaczego
# Frontend
# ALB
# HTTP (Nginx serwuje HTML/JS)
# Backend
# ALB
# HTTP (FastAPI REST API)
# Keycloak
# ALB
# HTTP (OAuth2/OpenID Connect)
# MinIO
# ALB
# HTTP (S3-compatible API)
# PostgreSQL
# NLB
# TCP (protokół binarny PostgreSQL)
# PostgreSQL komunikuje się przez własny protokół binarny na porcie 5432 - ALB by go nie zrozumiał i odrzucił jako "nieprawidłowy HTTP".

locals {
  postgres_container_name = "postgres"
  postgres_port           = 5432
}

# --- CloudWatch Log Group for PostgreSQL
resource "aws_cloudwatch_log_group" "postgres" {
  name              = "/ecs/postgres"
  retention_in_days = 14
}

# --- Security Groups for NLB
resource "aws_security_group" "nlb_postgres_sg" {
  name        = "nlb-postgres-sg"
  description = "Allow PostgreSQL access to NLB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Postgres from backend ECS tasks"
    from_port       = local.postgres_port
    to_port         = local.postgres_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks_sg.id]
  }

  ingress {
    description     = "Postgres from Keycloak ECS tasks"
    from_port       = local.postgres_port
    to_port         = local.postgres_port
    protocol        = "tcp"
    security_groups = [aws_security_group.keycloak_tasks_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "postgres_tasks_sg" {
  name        = "postgres-tasks-sg"
  description = "Allow PostgreSQL access from NLB"
  vpc_id      = data.aws_vpc.default.id

  # NLB does not have security groups, so we allow from VPC CIDR
  ingress {
    description = "Postgres from VPC (NLB)"
    from_port   = local.postgres_port
    to_port     = local.postgres_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- EFS for PostgreSQL data persistence
resource "aws_efs_file_system" "postgres" {
  creation_token = "postgres-data"
  encrypted      = true

  tags = {
    Name = "postgres-data"
  }
}

resource "aws_security_group" "efs_postgres_sg" {
  name        = "efs-postgres-sg"
  description = "Allow NFS from PostgreSQL tasks"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.postgres_tasks_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_efs_mount_target" "postgres" {
  count           = length(data.aws_subnets.default.ids)
  file_system_id  = aws_efs_file_system.postgres.id
  subnet_id       = data.aws_subnets.default.ids[count.index]
  security_groups = [aws_security_group.efs_postgres_sg.id]
}

# --- SSM Parameters for PostgreSQL credentials
resource "aws_ssm_parameter" "postgres_password" {
  name  = "/lab/postgres/password"
  type  = "SecureString"
  value = var.db_password
}

# --- Internal Network Load Balancer for PostgreSQL
resource "aws_lb" "postgres" {
  name               = "postgres-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = data.aws_subnets.default.ids

  tags = {
    Name = "postgres-nlb"
  }
}

resource "aws_lb_target_group" "postgres" {
  name        = "tg-postgres"
  port        = local.postgres_port
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 10
    interval            = 30
    protocol            = "TCP"
  }
}

resource "aws_lb_listener" "postgres" {
  load_balancer_arn = aws_lb.postgres.arn
  port              = local.postgres_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.postgres.arn
  }
}

# --- ECS Task Definition
resource "aws_ecs_task_definition" "postgres" {
  family                   = "postgres-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = data.aws_iam_role.labrole.arn
  task_role_arn            = data.aws_iam_role.labrole.arn

  volume {
    name = "postgres-data"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.postgres.id
      root_directory     = "/"
      transit_encryption = "ENABLED"
    }
  }

  container_definitions = jsonencode([
    {
      name  = local.postgres_container_name
      image = "postgres:16-alpine"

      portMappings = [
        {
          containerPort = local.postgres_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "POSTGRES_USER", value = var.db_username },
        { name = "POSTGRES_PASSWORD", value = var.db_password },
        { name = "POSTGRES_DB", value = var.db_name },
        { name = "PGDATA", value = "/var/lib/postgresql/data/pgdata" }
      ]

      mountPoints = [
        {
          sourceVolume  = "postgres-data"
          containerPath = "/var/lib/postgresql/data"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.postgres.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

# --- ECS Service with NLB
resource "aws_ecs_service" "postgres" {
  name            = "postgres-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.postgres.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  platform_version = "1.4.0"  # Required for EFS support

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.postgres_tasks_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.postgres.arn
    container_name   = local.postgres_container_name
    container_port   = local.postgres_port
  }

  depends_on = [
    aws_efs_mount_target.postgres,
    aws_lb_listener.postgres
  ]
}

# --- Output the NLB DNS name for PostgreSQL
output "postgres_nlb_dns" {
  description = "Internal NLB DNS name for PostgreSQL service"
  value       = aws_lb.postgres.dns_name
}
