# =============================================================================
# PLIK KEYCLOAK.TF - KONFIGURACJA SERWERA AUTORYZACJI KEYCLOAK
# =============================================================================
# Ten plik konfiguruje Keycloak - serwer Identity and Access Management (IAM)
# implementujący protokoły OpenID Connect (OIDC) i OAuth 2.0.
# Keycloak działa na ECS Fargate z ALB HTTPS (self-signed certificate).
#
# Komponenty:
# - Self-signed certyfikat SSL dla ALB
# - Security Groups dla ALB i kontenerów
# - SSM Parameters dla sekretów
# - ALB z HTTPS
# - ECS Task Definition z init containerem
# - ECS Service
# =============================================================================

# -----------------------------------------------------------------------------
# SEKCJA: ZMIENNE LOKALNE
# Definiują stałe używane w wielu miejscach w tym pliku
# -----------------------------------------------------------------------------

locals {
  keycloak_container_name = "keycloak"           # Nazwa głównego kontenera Keycloak
  keycloak_port           = 8080                 # Port na którym Keycloak nasłuchuje (HTTP wewnętrzny)
}

# -----------------------------------------------------------------------------
# SEKCJA: KONFIGURACJA REALM
# Realm to izolowana przestrzeń konfiguracji w Keycloak (użytkownicy, klienci, role)
# Plik realm-export.json zawiera prekonfigurowaną konfigurację realm'u
# -----------------------------------------------------------------------------

locals {
  # templatefile() - ładuje plik JSON i podmienia zmienne dynamiczne
  realm_json = templatefile("${path.module}/../keycloak/realm-export.json", {
    frontend_url = "https://${aws_lb.frontend.dns_name}"  # URL frontendu wstrzykiwany do konfiguracji realm'u
  })
}

# -----------------------------------------------------------------------------
# SEKCJA: CLOUDWATCH LOG GROUP
# Grupa logów dla kontenerów Keycloak
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "keycloak" {
  name              = "/ecs/keycloak"            # Ścieżka grupy logów w CloudWatch
  retention_in_days = 14                         # Przechowuj logi przez 14 dni
}

# -----------------------------------------------------------------------------
# SEKCJA: CERTYFIKAT SSL SELF-SIGNED
# Generowanie certyfikatu SSL dla Keycloak ALB
# Self-signed = nie wymaga zewnętrznego CA, ale przeglądarka pokaże ostrzeżenie
# -----------------------------------------------------------------------------

# Generowanie klucza prywatnego RSA
resource "tls_private_key" "keycloak" {
  algorithm = "RSA"                              # Algorytm kryptograficzny RSA
  rsa_bits  = 2048                               # Długość klucza 2048 bitów
}

# Generowanie samopodpisanego certyfikatu
resource "tls_self_signed_cert" "keycloak" {
  private_key_pem = tls_private_key.keycloak.private_key_pem  # Użyj wygenerowanego klucza

  subject {                                      # Dane podmiotu certyfikatu
    common_name  = "keycloak.local"              # CN - Common Name (nazwa domeny)
    organization = "LearnerLab"                  # Organizacja
  }

  validity_period_hours = 24 * 365               # Ważność: 365 dni

  allowed_uses = [                               # Dozwolone zastosowania certyfikatu
    "key_encipherment",                          # Szyfrowanie kluczy sesji
    "digital_signature",                         # Podpisy cyfrowe
    "server_auth",                               # Uwierzytelnianie serwera (HTTPS)
  ]
}

# Import certyfikatu do AWS Certificate Manager
resource "aws_acm_certificate" "keycloak" {
  private_key      = tls_private_key.keycloak.private_key_pem    # Klucz prywatny
  certificate_body = tls_self_signed_cert.keycloak.cert_pem      # Certyfikat

  lifecycle {
    create_before_destroy = true                 # Przy update: utwórz nowy przed usunięciem starego
  }
}

# -----------------------------------------------------------------------------
# SEKCJA: SECURITY GROUPS
# Kontrola ruchu sieciowego do ALB Keycloak i kontenerów
# -----------------------------------------------------------------------------

# Security Group dla ALB Keycloak
resource "aws_security_group" "alb_keycloak_sg" {
  name        = "alb-keycloak-sg"                # Nazwa Security Group
  description = "Allow HTTPS to Keycloak ALB"   # Opis przeznaczenia
  vpc_id      = data.aws_vpc.default.id          # VPC w którym tworzymy SG

  # Reguła INGRESS - HTTP (dla przekierowania na HTTPS)
  ingress {
    from_port   = 80                             # Port HTTP
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]                  # Dostęp z całego internetu
  }

  # Reguła INGRESS - HTTPS
  ingress {
    from_port   = 443                            # Port HTTPS
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]                  # Dostęp z całego internetu
  }

  # Reguła EGRESS - pozwól na wszystko wychodzące
  egress {
    from_port   = 0                              # Wszystkie porty
    to_port     = 0
    protocol    = "-1"                           # Wszystkie protokoły
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group dla kontenerów Keycloak
resource "aws_security_group" "keycloak_tasks_sg" {
  name        = "keycloak-tasks-sg"              # Nazwa
  description = "Allow Keycloak from its ALB"   # Opis - ruch tylko z ALB
  vpc_id      = data.aws_vpc.default.id

  # Reguła INGRESS - tylko z ALB Keycloak
  ingress {
    description     = "Keycloak from ALB"        # Opis reguły
    from_port       = local.keycloak_port        # Port 8080
    to_port         = local.keycloak_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_keycloak_sg.id]  # Tylko z ALB!
  }

  # Reguła EGRESS - pozwól na wszystko (np. połączenie do DB)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------------------------------------------------------
# SEKCJA: SSM PARAMETERS (SECRETS)
# AWS Systems Manager Parameter Store przechowuje sekrety bezpiecznie
# SecureString = wartość zaszyfrowana za pomocą KMS
# -----------------------------------------------------------------------------

# Hasło administratora Keycloak
resource "aws_ssm_parameter" "keycloak_admin_password" {
  name  = "/lab/keycloak/admin_password"         # Ścieżka parametru w SSM
  type  = "SecureString"                         # Typ: zaszyfrowany string
  value = var.keycloak_admin_password            # Wartość z zmiennej
}

# Hasło do bazy danych Keycloak
resource "aws_ssm_parameter" "keycloak_db_password" {
  name  = "/lab/keycloak/db_password"            # Ścieżka parametru
  type  = "SecureString"                         # Zaszyfrowany
  value = var.keycloak_db_password               # Wartość z zmiennej
}

# -----------------------------------------------------------------------------
# SEKCJA: APPLICATION LOAD BALANCER
# ALB dla Keycloak - przyjmuje ruch HTTPS i kieruje do kontenerów
# -----------------------------------------------------------------------------

resource "aws_lb" "keycloak" {
  name               = "keycloak-alb"            # Nazwa Load Balancera
  internal           = false                     # false = publiczny (dostępny z internetu)
  load_balancer_type = "application"             # Typ: Application (warstwa 7 HTTP/HTTPS)
  security_groups    = [aws_security_group.alb_keycloak_sg.id]  # Security Group
  subnets            = data.aws_subnets.default.ids  # Podsieci
}

# Target Group dla Keycloak
resource "aws_lb_target_group" "keycloak" {
  name        = "tg-keycloak"                    # Nazwa Target Group
  port        = local.keycloak_port              # Port 8080
  protocol    = "HTTP"                           # HTTP (terminacja SSL na ALB)
  target_type = "ip"                             # Typ IP dla Fargate
  vpc_id      = data.aws_vpc.default.id

  # Health check - sprawdza czy Keycloak jest gotowy
  health_check {
    path                = "/health/ready"        # Keycloak readiness endpoint
    healthy_threshold   = 2                      # 2 sukcesy = zdrowy
    unhealthy_threshold = 5                      # 5 niepowodzeń = niezdrowy
    timeout             = 5                      # Timeout 5 sekund
    interval            = 30                     # Sprawdzaj co 30 sekund
    matcher             = "200-399"              # Akceptowane kody HTTP
  }
}

# Listener HTTP - przekierowuje na HTTPS
resource "aws_lb_listener" "keycloak_http" {
  load_balancer_arn = aws_lb.keycloak.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"                            # Przekierowanie

    redirect {
      port        = "443"                        # Na port HTTPS
      protocol    = "HTTPS"
      status_code = "HTTP_301"                   # Permanent redirect
    }
  }
}

# Listener HTTPS - terminacja SSL
resource "aws_lb_listener" "keycloak_https" {
  load_balancer_arn = aws_lb.keycloak.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"  # Polityka szyfrowania
  certificate_arn   = aws_acm_certificate.keycloak.arn  # Certyfikat

  default_action {
    type             = "forward"                 # Przekaż ruch
    target_group_arn = aws_lb_target_group.keycloak.arn
  }
}

# -----------------------------------------------------------------------------
# SEKCJA: ECS TASK DEFINITION
# Definiuje jak uruchomić Keycloak - używa init containera do przygotowania realm'u
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "keycloak" {
  family                   = "keycloak-task"     # Nazwa rodziny zadań
  requires_compatibilities = ["FARGATE"]         # Fargate (serverless)
  network_mode             = "awsvpc"            # Każde zadanie ma własny ENI
  cpu                      = 512                 # 0.5 vCPU (Keycloak potrzebuje więcej niż backend)
  memory                   = 1024                # 1 GB RAM
  execution_role_arn       = data.aws_iam_role.labrole.arn  # Rola do pobierania obrazów i sekretów
  task_role_arn            = data.aws_iam_role.labrole.arn  # Rola runtime

  # Volume - współdzielony między init containerem a Keycloak
  volume {
    name = "realm-import"                        # Nazwa wolumenu
  }

  # Definicja kontenerów - 2 kontenery: init + main
  container_definitions = jsonencode([
    # ----- INIT CONTAINER -----
    # Przygotowuje plik konfiguracji realm'u przed uruchomieniem Keycloak
    {
      name      = "init-realm"                   # Nazwa init containera
      image     = "busybox:latest"               # Lekki obraz z podstawowymi narzędziami
      essential = false                          # false = zadanie może kontynuować po zakończeniu tego kontenera

      # Komenda tworząca plik realm-export.json
      command = [
        "sh", "-c",
        "mkdir -p /opt/keycloak/data/import && echo $REALM_JSON > /opt/keycloak/data/import/realm-export.json"
      ]

      # Zmienna środowiskowa z konfiguracją realm'u
      environment = [
        {
          name  = "REALM_JSON"
          value = local.realm_json               # JSON z konfiguracji realm'u
        }
      ]

      # Montowanie wolumenu współdzielonego
      mountPoints = [
        {
          sourceVolume  = "realm-import"         # Nazwa wolumenu
          containerPath = "/opt/keycloak/data/import"  # Ścieżka w kontenerze
          readOnly      = false                  # Zapisywalny
        }
      ]

      # Konfiguracja logów
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.keycloak.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "init"         # Prefix "init" dla łatwej identyfikacji
        }
      }
    },

    # ----- MAIN CONTAINER - KEYCLOAK -----
    {
      name  = local.keycloak_container_name      # "keycloak"
      image = var.keycloak_image                 # Obraz Keycloak
      portMappings = [
        {
          containerPort = local.keycloak_port    # Port 8080
          protocol      = "tcp"
        }
      ]

      essential = true                           # Kontener wymagany - zadanie kończy się gdy ten kontener zakończy

      # Zależność od init containera - poczekaj na sukces
      dependsOn = [
        {
          containerName = "init-realm"
          condition     = "SUCCESS"              # Init musi zakończyć się sukcesem
        }
      ]

      # Montowanie wolumenu z konfiguracją realm'u
      mountPoints = [
        {
          sourceVolume  = "realm-import"
          containerPath = "/opt/keycloak/data/import"
          readOnly      = true                   # Tylko odczyt
        }
      ]

      # Zmienne środowiskowe konfigurujące Keycloak
      environment = [
        { name = "KC_PROXY", value = "edge" },                    # Keycloak za proxy (ALB)
        { name = "KC_HTTP_ENABLED", value = "true" },             # Włącz HTTP (terminacja SSL na ALB)
        { name = "KC_HOSTNAME_STRICT", value = "false" },         # Nie wymuszaj konkretnego hostname
        { name = "KC_HEALTH_ENABLED", value = "true" },           # Włącz health endpoints
        { name = "KC_METRICS_ENABLED", value = "false" },         # Metryki wyłączone
        { name = "KEYCLOAK_ADMIN", value = var.keycloak_admin_user },  # Nazwa admina

        # Konfiguracja bazy danych PostgreSQL
        { name = "KC_DB", value = "postgres" },                   # Typ bazy: PostgreSQL
        { name = "KC_DB_URL", value = "jdbc:postgresql://${aws_lb.postgres.dns_name}:5432/${var.keycloak_db_name}" },  # JDBC URL
        { name = "KC_DB_USERNAME", value = var.keycloak_db_username },  # Użytkownik DB
        { name = "KC_DB_SCHEMA", value = "public" }               # Schema w bazie
      ]

      # Sekrety pobierane z SSM Parameter Store
      secrets = [
        {
          name      = "KEYCLOAK_ADMIN_PASSWORD"                   # Nazwa zmiennej środowiskowej
          valueFrom = aws_ssm_parameter.keycloak_admin_password.arn  # ARN parametru SSM
        },
        {
          name      = "KC_DB_PASSWORD"
          valueFrom = aws_ssm_parameter.keycloak_db_password.arn
        }
      ]

      # Komenda startowa Keycloak z importem realm'u
      command = ["start", "--http-port=8080", "--http-relative-path=/", "--import-realm"]

      # Konfiguracja logów
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.keycloak.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

# -----------------------------------------------------------------------------
# SEKCJA: ECS SERVICE
# Zarządza uruchomieniem i utrzymaniem zadań Keycloak
# -----------------------------------------------------------------------------

resource "aws_ecs_service" "keycloak" {
  name            = "keycloak-svc"               # Nazwa serwisu
  cluster         = aws_ecs_cluster.this.id      # ID klastra
  task_definition = aws_ecs_task_definition.keycloak.arn
  desired_count   = 1                            # 1 instancja
  launch_type     = "FARGATE"                    # Fargate

  # Konfiguracja sieci
  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.keycloak_tasks_sg.id]
    assign_public_ip = true                      # Publiczny IP
  }

  # Integracja z ALB
  load_balancer {
    target_group_arn = aws_lb_target_group.keycloak.arn
    container_name   = local.keycloak_container_name
    container_port   = local.keycloak_port
  }

  # Grace period dla health checków - Keycloak potrzebuje czasu na start i migracje DB
  health_check_grace_period_seconds = 300        # 5 minut na rozruch

  # Zależności
  depends_on = [
    aws_lb_listener.keycloak_https,              # Listener musi istnieć
    aws_ecs_service.postgres                     # Baza danych musi działać
  ]
}
