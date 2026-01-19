# =============================================================================
# PLIK MONITORING.TF - KONFIGURACJA STOSU MONITORINGU
# =============================================================================
# Ten plik konfiguruje stos monitoringu oparty na:
# - Prometheus - system zbierania i przechowywania metryk time-series
# - Grafana - platforma wizualizacji i dashboardów
#
# Prometheus zbiera metryki z backendu (endpoint /metrics) i przechowuje je.
# Grafana łączy się z Prometheus jako źródłem danych i wyświetla dashboardy.
#
# Oba komponenty działają na ECS Fargate z:
# - Wspólnym ALB (Grafana na 443, Prometheus na 9090)
# - Osobnymi EFS dla trwałych danych
# =============================================================================

# -----------------------------------------------------------------------------
# SEKCJA: ZMIENNE LOKALNE
# Stałe wartości dla obu komponentów monitoringu
# -----------------------------------------------------------------------------

locals {
  prometheus_container_name = "prometheus"       # Nazwa kontenera Prometheus
  prometheus_port           = 9090               # Standardowy port Prometheus
  grafana_container_name    = "grafana"          # Nazwa kontenera Grafana
  grafana_port              = 3000               # Standardowy port Grafana
}

# -----------------------------------------------------------------------------
# SEKCJA: CLOUDWATCH LOG GROUPS
# Grupy logów dla Prometheus i Grafana
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "prometheus" {
  name              = "/ecs/prometheus"          # Ścieżka grupy logów
  retention_in_days = 14                         # Retencja 14 dni
}

resource "aws_cloudwatch_log_group" "grafana" {
  name              = "/ecs/grafana"             # Ścieżka grupy logów
  retention_in_days = 14                         # Retencja 14 dni
}

# -----------------------------------------------------------------------------
# SEKCJA: SECURITY GROUPS
# Kontrola ruchu sieciowego do ALB monitoringu i kontenerów
# -----------------------------------------------------------------------------

# Security Group dla ALB monitoringu
resource "aws_security_group" "alb_monitoring_sg" {
  name        = "alb-monitoring-sg"
  description = "Allow HTTP/HTTPS to Monitoring ALB (Grafana)"
  vpc_id      = data.aws_vpc.default.id

  # Reguła INGRESS - HTTP dla przekierowania
  ingress {
    from_port   = 80                             # Port HTTP
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Reguła INGRESS - HTTPS dla Grafana
  ingress {
    from_port   = 443                            # Port HTTPS
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Reguła INGRESS - Prometheus (wewnętrzny dostęp)
  ingress {
    from_port   = local.prometheus_port          # Port 9090
    to_port     = local.prometheus_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]                  # Dostęp z internetu (tylko do odczytu)
  }

  # Reguła EGRESS
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group dla kontenerów monitoringu
resource "aws_security_group" "monitoring_tasks_sg" {
  name        = "monitoring-tasks-sg"
  description = "Allow ALB to reach monitoring tasks"
  vpc_id      = data.aws_vpc.default.id

  # Reguła INGRESS - Prometheus z ALB
  ingress {
    description     = "Prometheus from ALB"
    from_port       = local.prometheus_port      # Port 9090
    to_port         = local.prometheus_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_monitoring_sg.id]
  }

  # Reguła INGRESS - Grafana z ALB
  ingress {
    description     = "Grafana from ALB"
    from_port       = local.grafana_port         # Port 3000
    to_port         = local.grafana_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_monitoring_sg.id]
  }

  # Reguła INGRESS - wewnętrzny scraping z VPC
  ingress {
    description = "Prometheus scraping from VPC"
    from_port   = local.prometheus_port
    to_port     = local.prometheus_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]  # Z VPC
  }

  # Reguła EGRESS
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Reguła pozwalająca Prometheus na scraping metryk z backendu
resource "aws_security_group_rule" "backend_metrics_from_prometheus" {
  type                     = "ingress"           # Ruch przychodzący
  from_port                = var.backend_port    # Port backendu (8000)
  to_port                  = var.backend_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ecs_tasks_sg.id  # Do SG backendu
  source_security_group_id = aws_security_group.monitoring_tasks_sg.id  # Z Prometheus
  description              = "Allow Prometheus to scrape backend metrics"
}

# -----------------------------------------------------------------------------
# SEKCJA: APPLICATION LOAD BALANCER
# Wspólny ALB dla Prometheus i Grafana
# -----------------------------------------------------------------------------

resource "aws_lb" "monitoring" {
  name               = "monitoring-alb"          # Nazwa ALB
  internal           = false                     # Publiczny
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_monitoring_sg.id]
  subnets            = data.aws_subnets.default.ids
}

# -----------------------------------------------------------------------------
# SEKCJA: TARGET GROUPS
# Osobne target groups dla Prometheus i Grafana
# -----------------------------------------------------------------------------

# Target Group dla Prometheus
resource "aws_lb_target_group" "prometheus" {
  name        = "tg-prometheus"                  # Nazwa
  port        = local.prometheus_port            # Port 9090
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id

  # Health check dla Prometheus
  health_check {
    path                = "/-/healthy"           # Prometheus health endpoint
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }
}

# Target Group dla Grafana
resource "aws_lb_target_group" "grafana" {
  name        = "tg-grafana"                     # Nazwa
  port        = local.grafana_port               # Port 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id

  # Health check dla Grafana
  health_check {
    path                = "/api/health"          # Grafana health endpoint
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }
}

# -----------------------------------------------------------------------------
# SEKCJA: CERTYFIKAT SSL SELF-SIGNED
# Certyfikat dla ALB monitoringu (Grafana HTTPS)
# -----------------------------------------------------------------------------

resource "tls_private_key" "monitoring" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "monitoring" {
  private_key_pem = tls_private_key.monitoring.private_key_pem

  subject {
    common_name  = "monitoring.local"
    organization = "LearnerLab"
  }

  validity_period_hours = 24 * 365

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "monitoring" {
  private_key      = tls_private_key.monitoring.private_key_pem
  certificate_body = tls_self_signed_cert.monitoring.cert_pem

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# SEKCJA: ALB LISTENERS
# Trzy listenery: HTTP redirect, HTTPS Grafana, HTTP Prometheus
# -----------------------------------------------------------------------------

# Listener HTTP - przekierowanie na HTTPS
resource "aws_lb_listener" "monitoring_http" {
  load_balancer_arn = aws_lb.monitoring.arn
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

# Listener HTTPS dla Grafana (port 443)
resource "aws_lb_listener" "monitoring_https" {
  load_balancer_arn = aws_lb.monitoring.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.monitoring.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn  # Do Grafana
  }
}

# Listener HTTP dla Prometheus (port 9090)
# Prometheus bez HTTPS bo jest tylko do wewnętrznego użytku
resource "aws_lb_listener" "prometheus" {
  load_balancer_arn = aws_lb.monitoring.arn
  port              = local.prometheus_port      # Port 9090
  protocol          = "HTTP"                     # HTTP (nie HTTPS)

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prometheus.arn
  }
}

# -----------------------------------------------------------------------------
# SEKCJA: EFS DLA PROMETHEUS
# Trwałe przechowywanie danych metryk Prometheus
# -----------------------------------------------------------------------------

# System plików EFS
resource "aws_efs_file_system" "prometheus" {
  creation_token = "prometheus-data"
  encrypted      = true

  tags = {
    Name = "prometheus-data"
  }
}

# Access Point - punkt dostępu z określonymi uprawnieniami
resource "aws_efs_access_point" "prometheus" {
  file_system_id = aws_efs_file_system.prometheus.id

  # Użytkownik POSIX dla plików
  posix_user {
    uid = 0                                      # root (UID 0)
    gid = 0                                      # root group (GID 0)
  }

  # Katalog główny access point'u
  root_directory {
    path = "/prometheus"                         # Ścieżka w EFS

    creation_info {
      owner_uid   = 0                            # Właściciel: root
      owner_gid   = 0                            # Grupa: root
      permissions = "755"                        # rwxr-xr-x
    }
  }

  tags = {
    Name = "prometheus-access-point"
  }
}

# Mount Targets dla Prometheus EFS
resource "aws_efs_mount_target" "prometheus" {
  count           = length(data.aws_subnets.default.ids)
  file_system_id  = aws_efs_file_system.prometheus.id
  subnet_id       = data.aws_subnets.default.ids[count.index]
  security_groups = [aws_security_group.efs_prometheus_sg.id]
}

# Security Group dla EFS Prometheus
resource "aws_security_group" "efs_prometheus_sg" {
  name        = "efs-prometheus-sg"
  description = "Allow NFS for Prometheus EFS"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "NFS from monitoring tasks"
    from_port       = 2049                       # Port NFS
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.monitoring_tasks_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------------------------------------------------------
# SEKCJA: EFS DLA GRAFANA
# Trwałe przechowywanie danych Grafana (dashboardy, konfiguracja)
# -----------------------------------------------------------------------------

# System plików EFS
resource "aws_efs_file_system" "grafana" {
  creation_token = "grafana-data"
  encrypted      = true

  tags = {
    Name = "grafana-data"
  }
}

# Access Point dla Grafana
resource "aws_efs_access_point" "grafana" {
  file_system_id = aws_efs_file_system.grafana.id

  posix_user {
    uid = 0                                      # root
    gid = 0
  }

  root_directory {
    path = "/grafana"

    creation_info {
      owner_uid   = 0
      owner_gid   = 0
      permissions = "755"
    }
  }

  tags = {
    Name = "grafana-access-point"
  }
}

# Mount Targets dla Grafana EFS
resource "aws_efs_mount_target" "grafana" {
  count           = length(data.aws_subnets.default.ids)
  file_system_id  = aws_efs_file_system.grafana.id
  subnet_id       = data.aws_subnets.default.ids[count.index]
  security_groups = [aws_security_group.efs_grafana_sg.id]
}

# Security Group dla EFS Grafana
resource "aws_security_group" "efs_grafana_sg" {
  name        = "efs-grafana-sg"
  description = "Allow NFS for Grafana EFS"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "NFS from monitoring tasks"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.monitoring_tasks_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------------------------------------------------------
# SEKCJA: ECS TASK DEFINITION - PROMETHEUS
# Definicja uruchomienia Prometheus z EFS
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "prometheus" {
  family                   = "prometheus-task"   # Nazwa rodziny
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256                 # 0.25 vCPU
  memory                   = 512                 # 512 MB RAM
  execution_role_arn       = data.aws_iam_role.labrole.arn
  task_role_arn            = data.aws_iam_role.labrole.arn

  # Volume z EFS z access point'em
  volume {
    name = "prometheus-data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.prometheus.id
      transit_encryption = "ENABLED"             # Szyfrowanie w transmisji
      authorization_config {
        access_point_id = aws_efs_access_point.prometheus.id  # Access Point
        iam             = "ENABLED"              # Użyj IAM do autoryzacji
      }
    }
  }

  container_definitions = jsonencode([
    {
      name  = local.prometheus_container_name    # "prometheus"
      image = var.prometheus_image               # Własny obraz z konfiguracją
      user  = "root"                             # Uruchom jako root (dla EFS)

      portMappings = [
        {
          containerPort = local.prometheus_port  # Port 9090
          protocol      = "tcp"
        }
      ]

      # Zmienne środowiskowe
      environment = [
        { name = "BACKEND_TARGET", value = "${aws_lb.backend.dns_name}" },  # Target do scrapowania
        { name = "PROMETHEUS_ENV", value = "aws" }  # Środowisko (używane w konfiguracji)
      ]

      # Montowanie EFS
      mountPoints = [
        {
          sourceVolume  = "prometheus-data"
          containerPath = "/prometheus"          # Katalog danych Prometheus
          readOnly      = false
        }
      ]

      # Logowanie
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.prometheus.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

# -----------------------------------------------------------------------------
# SEKCJA: ECS TASK DEFINITION - GRAFANA
# Definicja uruchomienia Grafana z EFS
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "grafana" {
  family                   = "grafana-task"      # Nazwa rodziny
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256                 # 0.25 vCPU
  memory                   = 512                 # 512 MB RAM
  execution_role_arn       = data.aws_iam_role.labrole.arn
  task_role_arn            = data.aws_iam_role.labrole.arn

  # Volume z EFS
  volume {
    name = "grafana-data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.grafana.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.grafana.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name  = local.grafana_container_name       # "grafana"
      image = var.grafana_image                  # Własny obraz z dashboardami
      user  = "root"                             # Uruchom jako root

      portMappings = [
        {
          containerPort = local.grafana_port     # Port 3000
          protocol      = "tcp"
        }
      ]

      # Zmienne środowiskowe konfigurujące Grafana
      environment = [
        { name = "GF_SECURITY_ADMIN_USER", value = var.grafana_admin_user },        # Admin username
        { name = "GF_SECURITY_ADMIN_PASSWORD", value = var.grafana_admin_password },# Admin password
        { name = "GF_SERVER_ROOT_URL", value = "https://${aws_lb.monitoring.dns_name}" },  # URL root
        { name = "GF_SERVER_DOMAIN", value = aws_lb.monitoring.dns_name },          # Domena
        { name = "GF_INSTALL_PLUGINS", value = "" },                                # Pluginy do instalacji
        { name = "GF_USERS_ALLOW_SIGN_UP", value = "false" },                       # Wyłącz rejestrację
        # URL Prometheus jako datasource
        { name = "PROMETHEUS_URL", value = "http://${aws_lb.monitoring.dns_name}:${local.prometheus_port}" }
      ]

      # Montowanie EFS
      mountPoints = [
        {
          sourceVolume  = "grafana-data"
          containerPath = "/var/lib/grafana"     # Katalog danych Grafana
          readOnly      = false
        }
      ]

      # Logowanie
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.grafana.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

# -----------------------------------------------------------------------------
# SEKCJA: ECS SERVICES
# Serwisy dla Prometheus i Grafana
# -----------------------------------------------------------------------------

# ECS Service dla Prometheus
resource "aws_ecs_service" "prometheus" {
  name            = "prometheus-svc"             # Nazwa serwisu
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.prometheus.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.monitoring_tasks_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.prometheus.arn
    container_name   = local.prometheus_container_name
    container_port   = local.prometheus_port
  }

  depends_on = [
    aws_lb_listener.prometheus,                  # Listener musi istnieć
    aws_efs_mount_target.prometheus              # EFS musi być zamontowany
  ]
}

# ECS Service dla Grafana
resource "aws_ecs_service" "grafana" {
  name            = "grafana-svc"                # Nazwa serwisu
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.monitoring_tasks_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.grafana.arn
    container_name   = local.grafana_container_name
    container_port   = local.grafana_port
  }

  depends_on = [
    aws_lb_listener.monitoring_https,            # Listener HTTPS musi istnieć
    aws_efs_mount_target.grafana,                # EFS musi być zamontowany
    aws_ecs_service.prometheus                   # Prometheus musi działać (dla datasource)
  ]
}
