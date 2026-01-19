# =============================================================================
# PLIK MINIO.TF - KONFIGURACJA MINIO (S3-COMPATIBLE STORAGE)
# =============================================================================
# Ten plik konfiguruje MinIO - samodzielnie hostowany magazyn obiektów
# w pełni kompatybilny z AWS S3 API. Używany jako zamiennik AWS S3
# w środowisku laboratoryjnym/developerskim.
#
# MinIO działa na ECS Fargate z:
# - ALB HTTPS dla API i Console
# - EFS dla trwałego przechowywania danych
#
# Porty MinIO:
# - 9000 - S3 API (upload/download plików)
# - 9001 - Web Console (zarządzanie przez przeglądarkę)
# =============================================================================

# -----------------------------------------------------------------------------
# SEKCJA: ZMIENNE LOKALNE
# Stałe wartości używane w wielu miejscach
# -----------------------------------------------------------------------------

locals {
  minio_container_name = "minio"                 # Nazwa kontenera MinIO
  minio_api_port       = 9000                    # Port S3 API
  minio_console_port   = 9001                    # Port Web Console
}

# -----------------------------------------------------------------------------
# SEKCJA: CLOUDWATCH LOG GROUP
# Grupa logów dla MinIO
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "minio" {
  name              = "/ecs/minio"               # Ścieżka grupy logów
  retention_in_days = 14                         # Retencja 14 dni
}

# -----------------------------------------------------------------------------
# SEKCJA: CERTYFIKAT SSL SELF-SIGNED
# Certyfikat dla MinIO ALB
# -----------------------------------------------------------------------------

# Generowanie klucza prywatnego RSA
resource "tls_private_key" "minio" {
  algorithm = "RSA"                              # Algorytm RSA
  rsa_bits  = 2048                               # 2048 bitów
}

# Generowanie certyfikatu self-signed
resource "tls_self_signed_cert" "minio" {
  private_key_pem = tls_private_key.minio.private_key_pem

  subject {
    common_name  = "minio.local"                 # Common Name
    organization = "LearnerLab"                  # Organizacja
  }

  validity_period_hours = 24 * 365               # Ważność 1 rok

  allowed_uses = [
    "key_encipherment",                          # Szyfrowanie kluczy
    "digital_signature",                         # Podpisy cyfrowe
    "server_auth",                               # Uwierzytelnianie serwera
  ]
}

# Import certyfikatu do ACM
resource "aws_acm_certificate" "minio" {
  private_key      = tls_private_key.minio.private_key_pem
  certificate_body = tls_self_signed_cert.minio.cert_pem

  lifecycle {
    create_before_destroy = true                 # Zero downtime przy update
  }
}

# -----------------------------------------------------------------------------
# SEKCJA: SECURITY GROUPS
# Kontrola ruchu sieciowego do ALB MinIO i kontenerów
# -----------------------------------------------------------------------------

# Security Group dla ALB MinIO
resource "aws_security_group" "alb_minio_sg" {
  name        = "alb-minio-sg"
  description = "Allow HTTPS to MinIO ALB"
  vpc_id      = data.aws_vpc.default.id

  # Reguła INGRESS - port 443 dla S3 API
  ingress {
    from_port   = 443                            # HTTPS dla S3 API
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]                  # Dostęp z internetu
  }

  # Reguła INGRESS - port 9001 dla Console
  ingress {
    from_port   = 9001                           # Port Console
    to_port     = 9001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]                  # Dostęp z internetu
  }

  # Reguła EGRESS
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group dla kontenerów MinIO
resource "aws_security_group" "minio_tasks_sg" {
  name        = "minio-tasks-sg"
  description = "Allow MinIO from its ALB and ECS tasks"
  vpc_id      = data.aws_vpc.default.id

  # Reguła INGRESS - API z ALB
  ingress {
    description     = "MinIO API from ALB"
    from_port       = local.minio_api_port       # Port 9000
    to_port         = local.minio_api_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_minio_sg.id]
  }

  # Reguła INGRESS - Console z ALB
  ingress {
    description     = "MinIO Console from ALB"
    from_port       = local.minio_console_port   # Port 9001
    to_port         = local.minio_console_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_minio_sg.id]
  }

  # Reguła INGRESS - pozwól backendowi na bezpośredni dostęp do MinIO
  ingress {
    description     = "MinIO API from ECS tasks"
    from_port       = local.minio_api_port
    to_port         = local.minio_api_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks_sg.id]  # Z backendu
  }

  # Reguła EGRESS
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------------------------------------------------------
# SEKCJA: APPLICATION LOAD BALANCER
# ALB dla MinIO z dwoma listenerami (API i Console)
# -----------------------------------------------------------------------------

resource "aws_lb" "minio" {
  name               = "minio-alb"               # Nazwa ALB
  internal           = false                     # Publiczny
  load_balancer_type = "application"             # Application (HTTP/HTTPS)
  security_groups    = [aws_security_group.alb_minio_sg.id]
  subnets            = data.aws_subnets.default.ids
}

# -----------------------------------------------------------------------------
# SEKCJA: TARGET GROUPS
# Dwa target groups - jeden dla API, jeden dla Console
# -----------------------------------------------------------------------------

# Target Group dla MinIO S3 API
resource "aws_lb_target_group" "minio_api" {
  name        = "tg-minio-api"                   # Nazwa
  port        = local.minio_api_port             # Port 9000
  protocol    = "HTTP"                           # HTTP (terminacja SSL na ALB)
  target_type = "ip"                             # IP dla Fargate
  vpc_id      = data.aws_vpc.default.id

  # Health check dla S3 API
  health_check {
    path                = "/minio/health/live"   # MinIO health endpoint
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
    matcher             = "200"                  # Tylko kod 200
  }
}

# Target Group dla MinIO Console
resource "aws_lb_target_group" "minio_console" {
  name        = "tg-minio-console"               # Nazwa
  port        = local.minio_console_port         # Port 9001
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id

  # Health check dla Console
  health_check {
    path                = "/"                    # Strona główna Console
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
    matcher             = "200-399"              # Akceptuj przekierowania
  }
}

# -----------------------------------------------------------------------------
# SEKCJA: ALB LISTENERS
# Dwa listenery HTTPS - jeden dla API, jeden dla Console
# -----------------------------------------------------------------------------

# Listener HTTPS dla S3 API (port 443)
resource "aws_lb_listener" "minio_https" {
  load_balancer_arn = aws_lb.minio.arn
  port              = 443                        # Standardowy port HTTPS
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.minio.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.minio_api.arn  # Do S3 API
  }
}

# Listener HTTPS dla Console (port 9001)
resource "aws_lb_listener" "minio_console" {
  load_balancer_arn = aws_lb.minio.arn
  port              = 9001                       # Port Console
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.minio.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.minio_console.arn  # Do Console
  }
}

# -----------------------------------------------------------------------------
# SEKCJA: EFS (ELASTIC FILE SYSTEM)
# Trwałe przechowywanie danych MinIO (buckety i obiekty)
# -----------------------------------------------------------------------------

# System plików EFS dla MinIO
resource "aws_efs_file_system" "minio" {
  creation_token = "minio-data"                  # Unikalny token
  encrypted      = true                          # Szyfrowanie at-rest

  tags = {
    Name = "minio-data"
  }
}

# Security Group dla EFS MinIO
resource "aws_security_group" "efs_minio_sg" {
  name        = "efs-minio-sg"
  description = "Allow NFS from MinIO tasks"
  vpc_id      = data.aws_vpc.default.id

  # Reguła INGRESS - NFS tylko z MinIO tasks
  ingress {
    from_port       = 2049                       # Port NFS
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

# Mount Targets - jeden per podsieć
resource "aws_efs_mount_target" "minio" {
  count           = length(data.aws_subnets.default.ids)  # Dla każdej podsieci
  file_system_id  = aws_efs_file_system.minio.id
  subnet_id       = data.aws_subnets.default.ids[count.index]
  security_groups = [aws_security_group.efs_minio_sg.id]
}

# -----------------------------------------------------------------------------
# SEKCJA: SSM PARAMETERS
# Bezpieczne przechowywanie credentials MinIO
# -----------------------------------------------------------------------------

# Root User (odpowiednik AWS Access Key ID)
resource "aws_ssm_parameter" "minio_root_user" {
  name  = "/lab/minio/root_user"
  type  = "SecureString"                         # Zaszyfrowany
  value = var.minio_root_user
}

# Root Password (odpowiednik AWS Secret Access Key)
resource "aws_ssm_parameter" "minio_root_password" {
  name  = "/lab/minio/root_password"
  type  = "SecureString"                         # Zaszyfrowany
  value = var.minio_root_password
}

# -----------------------------------------------------------------------------
# SEKCJA: ECS TASK DEFINITION
# Definicja jak uruchomić MinIO z EFS
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "minio" {
  family                   = "minio-task"        # Nazwa rodziny
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512                 # 0.5 vCPU
  memory                   = 1024                # 1 GB RAM
  execution_role_arn       = data.aws_iam_role.labrole.arn
  task_role_arn            = data.aws_iam_role.labrole.arn

  # Volume z EFS dla danych
  volume {
    name = "minio-data"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.minio.id
      root_directory     = "/"                   # Główny katalog
      transit_encryption = "ENABLED"             # Szyfrowanie w transmisji
    }
  }

  container_definitions = jsonencode([
    {
      name  = local.minio_container_name         # "minio"
      image = var.minio_image                    # Obraz MinIO

      # Komenda startowa MinIO
      command = ["server", "/data", "--console-address", ":9001"]
      # server - uruchom w trybie serwera
      # /data - katalog z danymi
      # --console-address - port Console

      # Mapowanie portów
      portMappings = [
        {
          containerPort = local.minio_api_port   # Port 9000 - S3 API
          protocol      = "tcp"
        },
        {
          containerPort = local.minio_console_port  # Port 9001 - Console
          protocol      = "tcp"
        }
      ]

      # Zmienne środowiskowe
      environment = [
        { name = "MINIO_ROOT_USER", value = var.minio_root_user },          # Access Key
        { name = "MINIO_ROOT_PASSWORD", value = var.minio_root_password },  # Secret Key
        { name = "MINIO_BROWSER_REDIRECT_URL", value = "https://${aws_lb.minio.dns_name}:9001" }  # URL Console
      ]

      # Montowanie EFS
      mountPoints = [
        {
          sourceVolume  = "minio-data"
          containerPath = "/data"                # Ścieżka do danych w kontenerze
          readOnly      = false
        }
      ]

      # Logowanie
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

# -----------------------------------------------------------------------------
# SEKCJA: ECS SERVICE
# Zarządza uruchomieniem MinIO z integracją ALB
# -----------------------------------------------------------------------------

resource "aws_ecs_service" "minio" {
  name            = "minio-svc"                  # Nazwa serwisu
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.minio.arn
  desired_count   = 1                            # 1 instancja
  launch_type     = "FARGATE"

  platform_version = "1.4.0"                     # Wymagane dla EFS

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.minio_tasks_sg.id]
    assign_public_ip = true
  }

  # Integracja z ALB - S3 API
  load_balancer {
    target_group_arn = aws_lb_target_group.minio_api.arn
    container_name   = local.minio_container_name
    container_port   = local.minio_api_port      # Port 9000
  }

  # Integracja z ALB - Console
  load_balancer {
    target_group_arn = aws_lb_target_group.minio_console.arn
    container_name   = local.minio_container_name
    container_port   = local.minio_console_port  # Port 9001
  }

  # Zależności
  depends_on = [
    aws_lb_listener.minio_https,                 # Listener API
    aws_lb_listener.minio_console,               # Listener Console
    aws_efs_mount_target.minio                   # EFS mount targets
  ]
}
