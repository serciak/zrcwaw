# =============================================================================
# PLIK POSTGRES.TF - KONFIGURACJA BAZY DANYCH POSTGRESQL
# =============================================================================
# Ten plik konfiguruje PostgreSQL działający na ECS Fargate z EFS dla
# trwałego przechowywania danych. Używa wewnętrznego NLB (Network Load Balancer)
# zamiast Service Discovery (niedostępnego w AWS Learner Labs).
#
# WAŻNE: Różnica między ALB a NLB:
# - ALB (Application Load Balancer) - warstwa 7 (HTTP/HTTPS)
#   * Rozumie zawartość żądań HTTP, może routować na podstawie URL
#   * Użycie: aplikacje webowe, API REST, WebSocket
#
# - NLB (Network Load Balancer) - warstwa 4 (TCP/UDP)
#   * Nie rozumie zawartości - przekazuje surowe pakiety TCP/UDP
#   * Ekstremalnie niski latency
#   * Użycie: bazy danych, gRPC, MQTT, protokoły binarne
#
# PostgreSQL używa NLB bo komunikuje się przez własny protokół binarny na
# porcie 5432 - ALB by go nie zrozumiał i odrzucił jako "nieprawidłowy HTTP".
# =============================================================================

# -----------------------------------------------------------------------------
# SEKCJA: ZMIENNE LOKALNE
# Stałe używane w wielu miejscach
# -----------------------------------------------------------------------------

locals {
  postgres_container_name = "postgres"           # Nazwa kontenera PostgreSQL
  postgres_port           = 5432                 # Standardowy port PostgreSQL
}

# -----------------------------------------------------------------------------
# SEKCJA: CLOUDWATCH LOG GROUP
# Grupa logów dla PostgreSQL
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "postgres" {
  name              = "/ecs/postgres"            # Ścieżka grupy logów
  retention_in_days = 14                         # Retencja 14 dni
}

# -----------------------------------------------------------------------------
# SEKCJA: SECURITY GROUPS
# Kontrola ruchu sieciowego do NLB i kontenerów PostgreSQL
# -----------------------------------------------------------------------------

# Security Group dla NLB PostgreSQL
resource "aws_security_group" "nlb_postgres_sg" {
  name        = "nlb-postgres-sg"                # Nazwa
  description = "Allow PostgreSQL access to NLB" # Opis
  vpc_id      = data.aws_vpc.default.id

  # Reguła INGRESS - pozwól backendowi na dostęp do PostgreSQL
  ingress {
    description     = "Postgres from backend ECS tasks"  # Opis reguły
    from_port       = local.postgres_port        # Port 5432
    to_port         = local.postgres_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks_sg.id]  # Tylko z ECS tasks (backend)
  }

  # Reguła INGRESS - pozwól Keycloak na dostęp do PostgreSQL
  ingress {
    description     = "Postgres from Keycloak ECS tasks"
    from_port       = local.postgres_port
    to_port         = local.postgres_port
    protocol        = "tcp"
    security_groups = [aws_security_group.keycloak_tasks_sg.id]  # Tylko z Keycloak
  }

  # Reguła EGRESS - wszystko dozwolone
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"                           # Wszystkie protokoły
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group dla kontenerów PostgreSQL
resource "aws_security_group" "postgres_tasks_sg" {
  name        = "postgres-tasks-sg"
  description = "Allow PostgreSQL access from NLB"
  vpc_id      = data.aws_vpc.default.id

  # NLB nie ma security groups, więc dozwalamy z całego VPC CIDR
  ingress {
    description = "Postgres from VPC (NLB)"      # Opis
    from_port   = local.postgres_port            # Port 5432
    to_port     = local.postgres_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]  # Z całego VPC
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
# SEKCJA: EFS (ELASTIC FILE SYSTEM)
# System plików do trwałego przechowywania danych PostgreSQL
# EFS = zarządzany NFS, dane przetrwają restart kontenerów
# -----------------------------------------------------------------------------

# Tworzenie systemu plików EFS
resource "aws_efs_file_system" "postgres" {
  creation_token = "postgres-data"               # Unikalny token identyfikujący EFS
  encrypted      = true                          # Szyfrowanie at-rest (bezpieczeństwo)

  tags = {
    Name = "postgres-data"                       # Tag z nazwą
  }
}

# Security Group dla EFS - pozwala na NFS z kontenerów PostgreSQL
resource "aws_security_group" "efs_postgres_sg" {
  name        = "efs-postgres-sg"
  description = "Allow NFS from PostgreSQL tasks"
  vpc_id      = data.aws_vpc.default.id

  # Reguła INGRESS - NFS (port 2049) tylko z kontenerów PostgreSQL
  ingress {
    from_port       = 2049                       # Port NFS
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.postgres_tasks_sg.id]  # Tylko z PostgreSQL tasks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Mount Targets - punkty montowania EFS w każdej podsieci
# Tworzy jeden mount target per podsieć (count = liczba podsieci)
resource "aws_efs_mount_target" "postgres" {
  count           = length(data.aws_subnets.default.ids)  # Dla każdej podsieci
  file_system_id  = aws_efs_file_system.postgres.id       # ID systemu plików
  subnet_id       = data.aws_subnets.default.ids[count.index]  # ID podsieci
  security_groups = [aws_security_group.efs_postgres_sg.id]    # Security Group
}

# -----------------------------------------------------------------------------
# SEKCJA: SSM PARAMETERS
# Bezpieczne przechowywanie hasła PostgreSQL
# -----------------------------------------------------------------------------

resource "aws_ssm_parameter" "postgres_password" {
  name  = "/lab/postgres/password"               # Ścieżka parametru
  type  = "SecureString"                         # Typ zaszyfrowany
  value = var.db_password                        # Hasło z zmiennej
}

# -----------------------------------------------------------------------------
# SEKCJA: NETWORK LOAD BALANCER (NLB)
# NLB dla PostgreSQL - wewnętrzny (internal), warstwa 4 (TCP)
# -----------------------------------------------------------------------------

resource "aws_lb" "postgres" {
  name               = "postgres-nlb"            # Nazwa NLB
  internal           = true                      # true = wewnętrzny (niedostępny z internetu!)
  load_balancer_type = "network"                 # Typ: Network (warstwa 4 - TCP)
  subnets            = data.aws_subnets.default.ids

  tags = {
    Name = "postgres-nlb"
  }
}

# Target Group dla PostgreSQL
resource "aws_lb_target_group" "postgres" {
  name        = "tg-postgres"                    # Nazwa
  port        = local.postgres_port              # Port 5432
  protocol    = "TCP"                            # Protokół TCP (nie HTTP!)
  target_type = "ip"                             # Typ IP dla Fargate
  vpc_id      = data.aws_vpc.default.id

  # Health check dla TCP - sprawdza czy port jest otwarty
  health_check {
    enabled             = true                   # Włączony
    healthy_threshold   = 3                      # 3 sukcesy = zdrowy
    unhealthy_threshold = 3                      # 3 niepowodzenia = niezdrowy
    timeout             = 10                     # Timeout 10 sekund
    interval            = 30                     # Interwał 30 sekund
    protocol            = "TCP"                  # Sprawdzenie TCP (nie HTTP!)
  }
}

# Listener NLB - nasłuchuje na porcie PostgreSQL
resource "aws_lb_listener" "postgres" {
  load_balancer_arn = aws_lb.postgres.arn
  port              = local.postgres_port        # Port 5432
  protocol          = "TCP"                      # Protokół TCP

  default_action {
    type             = "forward"                 # Przekaż ruch
    target_group_arn = aws_lb_target_group.postgres.arn
  }
}

# -----------------------------------------------------------------------------
# SEKCJA: ECS TASK DEFINITION
# Definicja jak uruchomić PostgreSQL z EFS dla danych
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "postgres" {
  family                   = "postgres-task"     # Nazwa rodziny
  requires_compatibilities = ["FARGATE"]         # Fargate
  network_mode             = "awsvpc"            # awsvpc
  cpu                      = 512                 # 0.5 vCPU
  memory                   = 1024                # 1 GB RAM
  execution_role_arn       = data.aws_iam_role.labrole.arn
  task_role_arn            = data.aws_iam_role.labrole.arn

  # Volume z EFS dla trwałych danych
  volume {
    name = "postgres-data"                       # Nazwa wolumenu

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.postgres.id  # ID EFS
      root_directory     = "/"                   # Główny katalog
      transit_encryption = "ENABLED"             # Szyfrowanie w transmisji
    }
  }

  container_definitions = jsonencode([
    {
      name  = local.postgres_container_name      # "postgres"
      image = "postgres:16-alpine"               # Oficjalny obraz PostgreSQL 16, wersja Alpine (lekka)

      portMappings = [
        {
          containerPort = local.postgres_port    # Port 5432
          protocol      = "tcp"
        }
      ]

      # Zmienne środowiskowe konfigurujące PostgreSQL
      environment = [
        { name = "POSTGRES_USER", value = var.db_username },     # Nazwa użytkownika
        { name = "POSTGRES_PASSWORD", value = var.db_password }, # Hasło
        { name = "POSTGRES_DB", value = var.db_name },           # Nazwa bazy danych
        { name = "PGDATA", value = "/var/lib/postgresql/data/pgdata" }  # Ścieżka do danych
      ]

      # Montowanie EFS
      mountPoints = [
        {
          sourceVolume  = "postgres-data"                        # Nazwa wolumenu
          containerPath = "/var/lib/postgresql/data"             # Ścieżka w kontenerze
          readOnly      = false                                  # Zapisywalny
        }
      ]

      # Logowanie
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

# -----------------------------------------------------------------------------
# SEKCJA: ECS SERVICE
# Zarządza uruchomieniem PostgreSQL z integracją NLB
# -----------------------------------------------------------------------------

resource "aws_ecs_service" "postgres" {
  name            = "postgres-svc"               # Nazwa serwisu
  cluster         = aws_ecs_cluster.this.id      # Klaster
  task_definition = aws_ecs_task_definition.postgres.arn
  desired_count   = 1                            # 1 instancja
  launch_type     = "FARGATE"

  platform_version = "1.4.0"                     # Wersja platformy Fargate (wymagana dla EFS!)

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.postgres_tasks_sg.id]
    assign_public_ip = true                      # Potrzebny do pobierania obrazów
  }

  # Integracja z NLB
  load_balancer {
    target_group_arn = aws_lb_target_group.postgres.arn
    container_name   = local.postgres_container_name
    container_port   = local.postgres_port
  }

  # Zależności - poczekaj na EFS mount targets i listener
  depends_on = [
    aws_efs_mount_target.postgres,               # Mount targets muszą istnieć
    aws_lb_listener.postgres                     # Listener musi istnieć
  ]
}

# -----------------------------------------------------------------------------
# SEKCJA: OUTPUT
# Eksport DNS NLB do użycia w innych zasobach/serwisach
# -----------------------------------------------------------------------------

output "postgres_nlb_dns" {
  description = "Internal NLB DNS name for PostgreSQL service"  # Opis
  value       = aws_lb.postgres.dns_name                        # Wartość - DNS name NLB
}
