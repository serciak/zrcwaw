# =============================================================================
# PLIK MAIN.TF - GŁÓWNA KONFIGURACJA INFRASTRUKTURY AWS
# =============================================================================
# Ten plik zawiera podstawową konfigurację Terraform oraz zasoby dla:
# - Konfiguracji Terraform i providerów
# - Domyślnego VPC i sieci
# - Security Groups dla ALB i ECS Tasks
# - Klastra ECS
# - Load Balancerów dla frontendu i backendu
# - Certyfikatów SSL (self-signed)
# - Definicji zadań ECS dla frontendu i backendu
# - Serwisów ECS dla frontendu i backendu
# =============================================================================

# -----------------------------------------------------------------------------
# SEKCJA: KONFIGURACJA TERRAFORM I PROVIDERÓW
# Określa wymagania dotyczące wersji Terraform i używanych providerów
# -----------------------------------------------------------------------------

terraform {                              # Blok konfiguracji Terraform
  required_version = ">= 1.6.0"          # Minimalna wymagana wersja Terraform (1.6.0 lub nowsza)
  required_providers {                   # Blok definiujący wymagane providery
    aws = {                              # Konfiguracja providera AWS
      source  = "hashicorp/aws"          # Źródło providera - oficjalny provider od HashiCorp
      version = "~> 5.0"                 # Wersja providera: ~> oznacza >= 5.0 i < 6.0 (pesymistyczne ograniczenie)
    }
  }
}

provider "aws" {                         # Blok konfiguracji providera AWS
  region = var.region                    # Ustawia region AWS z wartości zmiennej (np. "us-east-1")
}

# -----------------------------------------------------------------------------
# SEKCJA: DOMYŚLNY VPC I PODSIECI
# Pobiera istniejące zasoby sieciowe z konta AWS (Default VPC)
# Data sources pozwalają odczytać dane o istniejących zasobach
# -----------------------------------------------------------------------------

data "aws_vpc" "default" {               # Data source pobierający informacje o VPC
  default = true                         # Pobiera domyślny VPC utworzony automatycznie przez AWS
}

data "aws_subnets" "default" {           # Data source pobierający listę podsieci
  filter {                               # Filtr do zawężenia wyników
    name   = "vpc-id"                    # Nazwa atrybutu do filtrowania
    values = [data.aws_vpc.default.id]   # Wartości filtra - ID domyślnego VPC
  }
}

data "aws_route_tables" "default" {      # Data source pobierający tabele routingu
  filter {                               # Filtr do zawężenia wyników
    name   = "vpc-id"                    # Nazwa atrybutu do filtrowania
    values = [data.aws_vpc.default.id]   # Wartości filtra - ID domyślnego VPC
  }
}

# -----------------------------------------------------------------------------
# SEKCJA: ROLA IAM
# Pobiera istniejącą rolę IAM "LabRole" z AWS Academy/Learner Lab
# Ta rola ma już skonfigurowane uprawnienia potrzebne do działania
# -----------------------------------------------------------------------------

data "aws_iam_role" "labrole" {          # Data source pobierający informacje o roli IAM
  name = "LabRole"                       # Nazwa roli - "LabRole" to standardowa rola w AWS Academy
}

# -----------------------------------------------------------------------------
# SEKCJA: GENEROWANIE LOSOWEGO SUFIKSU
# Używane do tworzenia unikalnych nazw zasobów
# -----------------------------------------------------------------------------

resource "random_id" "suffix" {          # Zasób generujący losowy identyfikator
  byte_length = 4                        # Długość w bajtach - wygeneruje 8 znaków hex (4 bajty * 2)
}

# -----------------------------------------------------------------------------
# SEKCJA: CLOUDWATCH LOG GROUPS
# Grupy logów dla kontenerów ECS - logi są wysyłane do CloudWatch
# Pozwala na centralne przeglądanie logów aplikacji w konsoli AWS
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "backend" {  # Grupa logów dla backendu
  name              = "/ecs/backend"             # Ścieżka/nazwa grupy logów w CloudWatch
  retention_in_days = 14                         # Okres retencji logów - 14 dni (potem auto-usunięcie)
}

resource "aws_cloudwatch_log_group" "frontend" { # Grupa logów dla frontendu
  name              = "/ecs/frontend"            # Ścieżka/nazwa grupy logów w CloudWatch
  retention_in_days = 14                         # Okres retencji logów - 14 dni
}

# -----------------------------------------------------------------------------
# SEKCJA: SECURITY GROUPS DLA ALB (APPLICATION LOAD BALANCER)
# Security Groups to wirtualne firewalle kontrolujące ruch sieciowy
# Definiują jakie połączenia są dozwolone do/z zasobów
# -----------------------------------------------------------------------------

# Security Group dla ALB backendu - kontroluje ruch do Load Balancera
resource "aws_security_group" "alb_backend_sg" {
  name        = "alb-backend-sg"                 # Nazwa Security Group
  description = "Allow HTTP and HTTPS to backend ALB"  # Opis przeznaczenia
  vpc_id      = data.aws_vpc.default.id          # ID VPC w którym tworzymy SG

  # Reguła INGRESS (ruch PRZYCHODZĄCY) - pozwala na HTTP (port 80)
  ingress {
    from_port   = 80                             # Port źródłowy - początek zakresu
    to_port     = 80                             # Port źródłowy - koniec zakresu (ten sam = jeden port)
    protocol    = "tcp"                          # Protokół - TCP
    cidr_blocks = ["0.0.0.0/0"]                  # Dozwolone źródła - 0.0.0.0/0 = cały internet
  }

  # Reguła INGRESS - pozwala na HTTPS (port 443)
  ingress {
    from_port   = 443                            # Port HTTPS
    to_port     = 443                            # Port HTTPS
    protocol    = "tcp"                          # Protokół TCP
    cidr_blocks = ["0.0.0.0/0"]                  # Dozwolone źródła - cały internet
  }

  # Reguła EGRESS (ruch WYCHODZĄCY) - pozwala na wszystko
  egress {
    from_port   = 0                              # Wszystkie porty (0 = dowolny)
    to_port     = 0                              # Wszystkie porty
    protocol    = "-1"                           # Wszystkie protokoły (-1 = all)
    cidr_blocks = ["0.0.0.0/0"]                  # Do wszystkich adresów
  }
}

# Security Group dla ALB frontendu - analogiczna konfiguracja
resource "aws_security_group" "alb_frontend_sg" {
  name        = "alb-frontend-sg"                # Nazwa Security Group
  description = "Allow HTTP and HTTPS to frontend ALB"  # Opis przeznaczenia
  vpc_id      = data.aws_vpc.default.id          # ID VPC

  # Reguła INGRESS - HTTP
  ingress {
    from_port   = 80                             # Port HTTP
    to_port     = 80                             # Port HTTP
    protocol    = "tcp"                          # Protokół TCP
    cidr_blocks = ["0.0.0.0/0"]                  # Z całego internetu
  }

  # Reguła INGRESS - HTTPS
  ingress {
    from_port   = 443                            # Port HTTPS
    to_port     = 443                            # Port HTTPS
    protocol    = "tcp"                          # Protokół TCP
    cidr_blocks = ["0.0.0.0/0"]                  # Z całego internetu
  }

  # Reguła EGRESS - wszystko dozwolone
  egress {
    from_port   = 0                              # Wszystkie porty
    to_port     = 0                              # Wszystkie porty
    protocol    = "-1"                           # Wszystkie protokoły
    cidr_blocks = ["0.0.0.0/0"]                  # Do wszystkich adresów
  }
}

# -----------------------------------------------------------------------------
# SEKCJA: SECURITY GROUP DLA ECS TASKS
# Kontroluje ruch sieciowy do kontenerów uruchomionych w ECS Fargate
# Pozwala tylko na ruch z ALB - to jest bezpieczniejsze niż dostęp z internetu
# -----------------------------------------------------------------------------

resource "aws_security_group" "ecs_tasks_sg" {
  name        = "ecs-tasks-sg"                   # Nazwa Security Group
  description = "Allow ALBs to reach ECS tasks"  # Opis - tylko ALB może się połączyć
  vpc_id      = data.aws_vpc.default.id          # ID VPC

  # Reguła INGRESS - Backend dostępny tylko z jego ALB
  ingress {
    description     = "Backend from ALB"          # Opis reguły
    from_port       = var.backend_port            # Port backendu (8000)
    to_port         = var.backend_port            # Port backendu
    protocol        = "tcp"                       # Protokół TCP
    security_groups = [aws_security_group.alb_backend_sg.id]  # Tylko z ALB backendu!
  }

  # Reguła INGRESS - Frontend dostępny tylko z jego ALB
  ingress {
    description     = "Frontend from ALB"         # Opis reguły
    from_port       = var.frontend_port           # Port frontendu (80)
    to_port         = var.frontend_port           # Port frontendu
    protocol        = "tcp"                       # Protokół TCP
    security_groups = [aws_security_group.alb_frontend_sg.id]  # Tylko z ALB frontendu!
  }

  # Reguła EGRESS - pozwala na połączenia wychodzące (np. do bazy danych)
  egress {
    from_port   = 0                              # Wszystkie porty
    to_port     = 0                              # Wszystkie porty
    protocol    = "-1"                           # Wszystkie protokoły
    cidr_blocks = ["0.0.0.0/0"]                  # Do wszystkich adresów
  }
}

# -----------------------------------------------------------------------------
# SEKCJA: KLASTER ECS
# ECS Cluster to logiczne zgrupowanie serwisów i zadań ECS
# Wszystkie kontenery w tym projekcie będą uruchamiane w tym klastrze
# -----------------------------------------------------------------------------

resource "aws_ecs_cluster" "this" {              # Zasób klastra ECS
  name = "lab-ecs-cluster"                       # Nazwa klastra
}

# -----------------------------------------------------------------------------
# SEKCJA: APPLICATION LOAD BALANCERS (ALB)
# ALB rozdziela ruch HTTP/HTTPS do kontenerów
# Zapewnia wysoką dostępność i automatyczne skalowanie
# -----------------------------------------------------------------------------

# ALB dla backendu - przyjmuje ruch i kieruje do kontenerów backendowych
resource "aws_lb" "backend" {
  name               = "backend-alb"             # Nazwa Load Balancera
  internal           = false                     # false = publiczny (dostępny z internetu)
  load_balancer_type = "application"             # Typ: Application (warstwa 7 - HTTP/HTTPS)
  security_groups    = [aws_security_group.alb_backend_sg.id]  # Przypisany Security Group
  subnets            = data.aws_subnets.default.ids  # Podsieci gdzie ALB będzie działać
}

# ALB dla frontendu - przyjmuje ruch i kieruje do kontenerów frontendowych
resource "aws_lb" "frontend" {
  name               = "frontend-alb"            # Nazwa Load Balancera
  internal           = false                     # false = publiczny (dostępny z internetu)
  load_balancer_type = "application"             # Typ: Application (warstwa 7 - HTTP/HTTPS)
  security_groups    = [aws_security_group.alb_frontend_sg.id]  # Przypisany Security Group
  subnets            = data.aws_subnets.default.ids  # Podsieci gdzie ALB będzie działać
}

# -----------------------------------------------------------------------------
# SEKCJA: TARGET GROUPS
# Target Group to grupa "celów" (kontenerów) do których ALB kieruje ruch
# Zawiera konfigurację health checków - sprawdzanie czy kontenery są zdrowe
# -----------------------------------------------------------------------------

# Target Group dla backendu
resource "aws_lb_target_group" "backend" {
  name        = "tg-backend"                     # Nazwa Target Group
  port        = var.backend_port                 # Port na którym nasłuchują kontenery (8000)
  protocol    = "HTTP"                           # Protokół komunikacji z kontenerami
  target_type = "ip"                             # Typ targetu: "ip" dla Fargate (awsvpc network mode)
  vpc_id      = data.aws_vpc.default.id          # VPC w którym są kontenery

  # Konfiguracja Health Check - sprawdza czy kontener jest zdrowy
  health_check {
    path                = "/"                    # Ścieżka URL do sprawdzenia
    healthy_threshold   = 2                      # Ile kolejnych sukcesów = zdrowy
    unhealthy_threshold = 5                      # Ile kolejnych niepowodzeń = niezdrowy
    timeout             = 5                      # Timeout pojedynczego sprawdzenia (sekundy)
    interval            = 30                     # Odstęp między sprawdzeniami (sekundy)
    matcher             = "200-399"              # Kody HTTP uznawane za sukces
  }
}

# Target Group dla frontendu - analogiczna konfiguracja
resource "aws_lb_target_group" "frontend" {
  name        = "tg-frontend"                    # Nazwa Target Group
  port        = var.frontend_port                # Port (80)
  protocol    = "HTTP"                           # Protokół HTTP
  target_type = "ip"                             # Typ targetu dla Fargate
  vpc_id      = data.aws_vpc.default.id          # VPC

  health_check {
    path                = "/"                    # Ścieżka URL do sprawdzenia
    healthy_threshold   = 2                      # Próg zdrowy
    unhealthy_threshold = 5                      # Próg niezdrowy
    timeout             = 5                      # Timeout
    interval            = 30                     # Interwał
    matcher             = "200-399"              # Akceptowane kody HTTP
  }
}

# -----------------------------------------------------------------------------
# SEKCJA: CERTYFIKATY SSL DLA BACKENDU
# Self-signed certyfikaty dla środowiska developerskiego/laboratoryjnego
# Na produkcji użyj certyfikatów z AWS Certificate Manager (ACM) lub Let's Encrypt
# -----------------------------------------------------------------------------

# Generowanie klucza prywatnego RSA dla backendu
resource "tls_private_key" "backend" {
  algorithm = "RSA"                              # Algorytm: RSA
  rsa_bits  = 2048                               # Długość klucza: 2048 bitów (standard bezpieczeństwa)
}

# Generowanie self-signed certyfikatu dla backendu
resource "tls_self_signed_cert" "backend" {
  private_key_pem = tls_private_key.backend.private_key_pem  # Klucz prywatny do podpisania

  subject {                                      # Dane podmiotu certyfikatu (Subject)
    common_name  = "backend.local"               # Common Name (CN) - nazwa domenowa
    organization = "LearnerLab"                  # Nazwa organizacji
  }

  validity_period_hours = 24 * 365               # Ważność: 1 rok (24h * 365 dni)

  allowed_uses = [                               # Dozwolone użycia certyfikatu
    "key_encipherment",                          # Szyfrowanie kluczy
    "digital_signature",                         # Podpisy cyfrowe
    "server_auth",                               # Uwierzytelnianie serwera (TLS)
  ]
}

# Import certyfikatu do AWS Certificate Manager
resource "aws_acm_certificate" "backend" {
  private_key      = tls_private_key.backend.private_key_pem     # Klucz prywatny
  certificate_body = tls_self_signed_cert.backend.cert_pem       # Treść certyfikatu

  lifecycle {
    create_before_destroy = true                 # Utwórz nowy przed usunięciem starego (zero downtime)
  }
}

# -----------------------------------------------------------------------------
# SEKCJA: LISTENERY ALB DLA BACKENDU
# Listenery "nasłuchują" na określonych portach i kierują ruch do Target Groups
# -----------------------------------------------------------------------------

# Listener HTTP (port 80) - przekierowuje na HTTPS
resource "aws_lb_listener" "backend_http" {
  load_balancer_arn = aws_lb.backend.arn         # ARN Load Balancera
  port              = 80                          # Port nasłuchu
  protocol          = "HTTP"                      # Protokół

  default_action {                                # Domyślna akcja
    type = "redirect"                             # Typ: przekierowanie

    redirect {                                    # Konfiguracja przekierowania
      port        = "443"                         # Przekieruj na port 443
      protocol    = "HTTPS"                       # Przekieruj na HTTPS
      status_code = "HTTP_301"                    # Kod HTTP 301 (permanent redirect)
    }
  }
}

# Listener HTTPS (port 443) - terminacja SSL i forward do kontenerów
resource "aws_lb_listener" "backend_https" {
  load_balancer_arn = aws_lb.backend.arn         # ARN Load Balancera
  port              = 443                         # Port HTTPS
  protocol          = "HTTPS"                     # Protokół HTTPS
  ssl_policy        = "ELBSecurityPolicy-2016-08" # Polityka SSL (zestaw szyfrów)
  certificate_arn   = aws_acm_certificate.backend.arn  # ARN certyfikatu z ACM

  default_action {                                # Domyślna akcja
    type             = "forward"                  # Typ: przekazanie ruchu
    target_group_arn = aws_lb_target_group.backend.arn  # Do Target Group backendu
  }
}

# -----------------------------------------------------------------------------
# SEKCJA: CERTYFIKATY SSL DLA FRONTENDU
# Analogiczna konfiguracja jak dla backendu
# -----------------------------------------------------------------------------

# Generowanie klucza prywatnego RSA dla frontendu
resource "tls_private_key" "frontend" {
  algorithm = "RSA"                              # Algorytm RSA
  rsa_bits  = 2048                               # 2048 bitów
}

# Generowanie self-signed certyfikatu dla frontendu
resource "tls_self_signed_cert" "frontend" {
  private_key_pem = tls_private_key.frontend.private_key_pem  # Klucz prywatny

  subject {
    common_name  = "frontend.local"              # CN - nazwa domenowa frontendu
    organization = "LearnerLab"                  # Organizacja
  }

  validity_period_hours = 24 * 365               # Ważność: 1 rok

  allowed_uses = [
    "key_encipherment",                          # Szyfrowanie kluczy
    "digital_signature",                         # Podpisy cyfrowe
    "server_auth",                               # Uwierzytelnianie serwera
  ]
}

# Import certyfikatu frontendu do ACM
resource "aws_acm_certificate" "frontend" {
  private_key      = tls_private_key.frontend.private_key_pem
  certificate_body = tls_self_signed_cert.frontend.cert_pem

  lifecycle {
    create_before_destroy = true                 # Zero downtime przy update
  }
}

# -----------------------------------------------------------------------------
# SEKCJA: LISTENERY ALB DLA FRONTENDU
# -----------------------------------------------------------------------------

# Listener HTTP frontendu - przekierowanie na HTTPS
resource "aws_lb_listener" "frontend_http" {
  load_balancer_arn = aws_lb.frontend.arn        # ARN Load Balancera frontendu
  port              = 80                          # Port HTTP
  protocol          = "HTTP"                      # Protokół HTTP

  default_action {
    type = "redirect"                             # Przekierowanie

    redirect {
      port        = "443"                         # Na port 443
      protocol    = "HTTPS"                       # Na HTTPS
      status_code = "HTTP_301"                    # Permanent redirect
    }
  }
}

# Listener HTTPS frontendu - terminacja SSL
resource "aws_lb_listener" "frontend_https" {
  load_balancer_arn = aws_lb.frontend.arn        # ARN Load Balancera
  port              = 443                         # Port HTTPS
  protocol          = "HTTPS"                     # Protokół HTTPS
  ssl_policy        = "ELBSecurityPolicy-2016-08" # Polityka SSL
  certificate_arn   = aws_acm_certificate.frontend.arn  # Certyfikat frontendu

  default_action {
    type             = "forward"                  # Przekazanie ruchu
    target_group_arn = aws_lb_target_group.frontend.arn  # Do Target Group frontendu
  }
}

# -----------------------------------------------------------------------------
# SEKCJA: LOKALNE ZMIENNE
# locals pozwalają na definiowanie zmiennych pomocniczych używanych wielokrotnie
# -----------------------------------------------------------------------------

locals {
  backend_container_name  = "backend"            # Nazwa kontenera backendowego (używana w wielu miejscach)
  frontend_container_name = "frontend"           # Nazwa kontenera frontendowego
}

# -----------------------------------------------------------------------------
# SEKCJA: ECS TASK DEFINITION DLA BACKENDU
# Task Definition definiuje jak uruchomić kontener:
# - jaki obraz Docker
# - ile CPU/pamięci
# - zmienne środowiskowe
# - konfiguracja logów
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "backend" {
  family                   = "backend-task"       # Nazwa rodziny zadań (wersjonowanie)
  requires_compatibilities = ["FARGATE"]          # Wymagany typ uruchomienia: Fargate (serverless)
  network_mode             = "awsvpc"             # Tryb sieci: awsvpc (każde zadanie ma własny ENI)
  cpu                      = 256                  # CPU units: 256 = 0.25 vCPU
  memory                   = 512                  # Pamięć RAM w MB
  execution_role_arn       = data.aws_iam_role.labrole.arn  # Rola do pobierania obrazów i logowania
  task_role_arn            = data.aws_iam_role.labrole.arn  # Rola używana przez aplikację w runtime

  # Definicja kontenerów w formacie JSON
  container_definitions = jsonencode([            # jsonencode() konwertuje HCL na JSON
    {
      name  = local.backend_container_name        # Nazwa kontenera
      image = var.backend_image                   # Obraz Docker z rejestru

      # Mapowanie portów - ekspozycja portu kontenera
      portMappings = [
        {
          containerPort = var.backend_port        # Port wewnątrz kontenera (8000)
          protocol      = "tcp"                   # Protokół TCP
        }
      ]

      # Zmienne środowiskowe przekazywane do kontenera
      environment = [
        { name = "BACKEND_HOST", value = "0.0.0.0" },  # Nasłuchuj na wszystkich interfejsach
        { name = "BACKEND_PORT", value = tostring(var.backend_port) },  # Port (konwersja na string)
        { name = "MEDIA_ROOT", value = "/app/uploads" },  # Ścieżka do uploadowanych plików
        { name = "CORS_ORIGINS", value = "*" },        # CORS: dozwolone pochodzenia (wszystkie - do zmiany na prod)
        # Connection string do PostgreSQL - składany dynamicznie z danych innych zasobów
        { name = "DATABASE_URL", value = "postgresql+psycopg2://${var.db_username}:${var.db_password}@${aws_lb.postgres.dns_name}:5432/${var.db_name}" },
        { name = "AWS_REGION", value = var.region },   # Region AWS

        # Konfiguracja MinIO (S3-compatible storage)
        { name = "S3_BUCKET_NAME", value = var.minio_bucket_name },          # Nazwa bucketu
        { name = "S3_ENDPOINT_URL", value = "https://${aws_lb.minio.dns_name}" },  # URL endpointu MinIO
        { name = "S3_PUBLIC_ENDPOINT_URL", value = "https://${aws_lb.minio.dns_name}" },  # Publiczny URL
        { name = "S3_ACCESS_KEY", value = var.minio_root_user },             # Access key (jak AWS)
        { name = "S3_SECRET_KEY", value = var.minio_root_password },         # Secret key (jak AWS)

        # Konfiguracja OIDC / Keycloak
        { name = "OIDC_ISSUER_URL", value = "https://${aws_lb.keycloak.dns_name}/realms/${var.oidc_realm}" },  # URL issuer'a tokenów
        { name = "OIDC_AUDIENCE", value = var.oidc_api_audience },           # Oczekiwany audience w tokenach
        { name = "SSL_VERIFY", value = "false" }       # Wyłącz weryfikację SSL (dla self-signed w lab)
      ]

      # Konfiguracja logowania do CloudWatch
      logConfiguration = {
        logDriver = "awslogs"                     # Driver: AWS CloudWatch Logs
        options = {
          awslogs-group         = aws_cloudwatch_log_group.backend.name  # Grupa logów
          awslogs-region        = var.region                             # Region
          awslogs-stream-prefix = "ecs"                                  # Prefix dla strumieni logów
        }
      }
    }
  ])
}

# -----------------------------------------------------------------------------
# SEKCJA: ECS TASK DEFINITION DLA FRONTENDU
# Analogiczna struktura jak dla backendu
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "frontend" {
  family                   = "frontend-task"      # Nazwa rodziny zadań
  requires_compatibilities = ["FARGATE"]          # Fargate (serverless)
  network_mode             = "awsvpc"             # Tryb sieci awsvpc
  cpu                      = 256                  # 0.25 vCPU
  memory                   = 512                  # 512 MB RAM
  execution_role_arn       = data.aws_iam_role.labrole.arn
  task_role_arn            = data.aws_iam_role.labrole.arn

  container_definitions = jsonencode([
    {
      name  = local.frontend_container_name       # Nazwa kontenera
      image = var.frontend_image                  # Obraz Docker frontendu

      portMappings = [
        {
          containerPort = var.frontend_port       # Port 80 (Nginx)
          protocol      = "tcp"
        }
      ]

      # Zmienne środowiskowe dla frontendu
      environment = [
        { name = "API_URL", value = "https://${aws_lb.backend.dns_name}" },  # URL backendu (do API calls)

        # Konfiguracja OIDC / Keycloak dla SPA
        { name = "OIDC_AUTHORITY", value = "https://${aws_lb.keycloak.dns_name}/realms/${var.oidc_realm}" },  # Authority OIDC
        { name = "OIDC_CLIENT_ID", value = var.oidc_spa_client_id },         # Client ID dla SPA
        { name = "OIDC_REDIRECT_URI", value = "https://${aws_lb.frontend.dns_name}/auth/callback" },  # URL callback po logowaniu
        { name = "OIDC_POST_LOGOUT_REDIRECT_URI", value = "https://${aws_lb.frontend.dns_name}/" },   # URL po wylogowaniu
        { name = "OIDC_SCOPE", value = "openid profile email" }              # Żądane scopy OIDC
      ]

      # Logowanie do CloudWatch
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

# -----------------------------------------------------------------------------
# SEKCJA: ECS SERVICES
# Service zarządza uruchomieniem zadań:
# - utrzymuje żądaną liczbę instancji
# - integruje z Load Balancerem
# - obsługuje rolling deployments
# -----------------------------------------------------------------------------

# ECS Service dla backendu
resource "aws_ecs_service" "backend" {
  name            = "backend-svc"                 # Nazwa serwisu
  cluster         = aws_ecs_cluster.this.id       # ID klastra ECS
  task_definition = aws_ecs_task_definition.backend.arn  # ARN Task Definition
  desired_count   = 1                             # Żądana liczba uruchomionych instancji
  launch_type     = "FARGATE"                     # Typ uruchomienia: Fargate (serverless)

  # Konfiguracja sieci dla zadań
  network_configuration {
    subnets          = data.aws_subnets.default.ids       # Podsieci gdzie uruchomić
    security_groups  = [aws_security_group.ecs_tasks_sg.id]  # Security Group dla zadań
    assign_public_ip = true                       # Przypisz publiczny IP (potrzebny do pobierania obrazów)
  }

  # Integracja z Load Balancerem
  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn  # ARN Target Group
    container_name   = local.backend_container_name     # Nazwa kontenera (musi pasować do task def)
    container_port   = var.backend_port                 # Port kontenera
  }

  # Zależności - poczekaj na te zasoby przed utworzeniem
  depends_on = [
    aws_lb_listener.backend_http,                 # Listener musi istnieć przed serwisem
    aws_ecs_service.postgres                      # Baza danych musi być uruchomiona
  ]
}

# ECS Service dla frontendu
resource "aws_ecs_service" "frontend" {
  name            = "frontend-svc"                # Nazwa serwisu
  cluster         = aws_ecs_cluster.this.id       # ID klastra
  task_definition = aws_ecs_task_definition.frontend.arn  # ARN Task Definition
  desired_count   = 1                             # 1 instancja
  launch_type     = "FARGATE"                     # Fargate

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
    aws_lb_listener.frontend_http                 # Poczekaj na listener
  ]
}
