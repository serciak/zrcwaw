# Keycloak on ECS Fargate + ALB HTTPS (self-signed)

locals {
  keycloak_container_name = "keycloak"
  keycloak_port           = 8080
}

# --- Realm config loaded from template with dynamic frontend URL
locals {
  realm_json = templatefile("${path.module}/../keycloak/realm-export.json", {
    frontend_url = "https://${aws_lb.frontend.dns_name}"
  })
}

resource "aws_cloudwatch_log_group" "keycloak" {
  name              = "/ecs/keycloak"
  retention_in_days = 14
}

# --- Self-signed certificate -> ACM
resource "tls_private_key" "keycloak" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "keycloak" {
  private_key_pem = tls_private_key.keycloak.private_key_pem

  subject {
    common_name  = "keycloak.local"
    organization = "LearnerLab"
  }

  validity_period_hours = 24 * 365

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "keycloak" {
  private_key      = tls_private_key.keycloak.private_key_pem
  certificate_body = tls_self_signed_cert.keycloak.cert_pem

  lifecycle {
    create_before_destroy = true
  }
}

# --- Security groups
resource "aws_security_group" "alb_keycloak_sg" {
  name        = "alb-keycloak-sg"
  description = "Allow HTTPS to Keycloak ALB"
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

resource "aws_security_group" "keycloak_tasks_sg" {
  name        = "keycloak-tasks-sg"
  description = "Allow Keycloak from its ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Keycloak from ALB"
    from_port       = local.keycloak_port
    to_port         = local.keycloak_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_keycloak_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- Keycloak admin password in SSM SecureString
resource "aws_ssm_parameter" "keycloak_admin_password" {
  name  = "/lab/keycloak/admin_password"
  type  = "SecureString"
  value = var.keycloak_admin_password
}

resource "aws_ssm_parameter" "keycloak_db_password" {
  name  = "/lab/keycloak/db_password"
  type  = "SecureString"
  value = var.keycloak_db_password
}

# --- ALB
resource "aws_lb" "keycloak" {
  name               = "keycloak-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_keycloak_sg.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "keycloak" {
  name        = "tg-keycloak"
  port        = local.keycloak_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id

  health_check {
    path                = "/health/ready"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
    matcher             = "200-399"
  }
}

resource "aws_lb_listener" "keycloak_http" {
  load_balancer_arn = aws_lb.keycloak.arn
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

resource "aws_lb_listener" "keycloak_https" {
  load_balancer_arn = aws_lb.keycloak.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.keycloak.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.keycloak.arn
  }
}

# --- Task Definition
resource "aws_ecs_task_definition" "keycloak" {
  family                   = "keycloak-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = data.aws_iam_role.labrole.arn
  task_role_arn            = data.aws_iam_role.labrole.arn

  volume {
    name = "realm-import"
  }

  container_definitions = jsonencode([
    # Init container - creates realm file from embedded config
    {
      name      = "init-realm"
      image     = "busybox:latest"
      essential = false

      command = [
        "sh", "-c",
        "mkdir -p /opt/keycloak/data/import && echo $REALM_JSON > /opt/keycloak/data/import/realm-export.json"
      ]

      environment = [
        {
          name  = "REALM_JSON"
          value = local.realm_json
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "realm-import"
          containerPath = "/opt/keycloak/data/import"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.keycloak.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "init"
        }
      }
    },
    # Keycloak main container
    {
      name  = local.keycloak_container_name
      image = var.keycloak_image
      portMappings = [
        {
          containerPort = local.keycloak_port
          protocol      = "tcp"
        }
      ]

      essential = true

      dependsOn = [
        {
          containerName = "init-realm"
          condition     = "SUCCESS"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "realm-import"
          containerPath = "/opt/keycloak/data/import"
          readOnly      = true
        }
      ]

      environment = [
        { name = "KC_PROXY", value = "edge" },
        { name = "KC_HTTP_ENABLED", value = "true" },
        { name = "KC_HOSTNAME_STRICT", value = "false" },
        { name = "KC_HEALTH_ENABLED", value = "true" },
        { name = "KC_METRICS_ENABLED", value = "false" },
        { name = "KEYCLOAK_ADMIN", value = var.keycloak_admin_user },

        { name = "KC_DB", value = "postgres" },
        { name = "KC_DB_URL", value = "jdbc:postgresql://${aws_lb.postgres.dns_name}:5432/${var.keycloak_db_name}" },
        { name = "KC_DB_USERNAME", value = var.keycloak_db_username },
        { name = "KC_DB_SCHEMA", value = "public" }
      ]

      secrets = [
        {
          name      = "KEYCLOAK_ADMIN_PASSWORD"
          valueFrom = aws_ssm_parameter.keycloak_admin_password.arn
        },
        {
          name      = "KC_DB_PASSWORD"
          valueFrom = aws_ssm_parameter.keycloak_db_password.arn
        }
      ]

      command = ["start", "--http-port=8080", "--http-relative-path=/", "--import-realm"]

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

# --- Service
resource "aws_ecs_service" "keycloak" {
  name            = "keycloak-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.keycloak.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.keycloak_tasks_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.keycloak.arn
    container_name   = local.keycloak_container_name
    container_port   = local.keycloak_port
  }

  # daj Keycloakowi czas na bootstrap i migracje DB zanim ALB uzna go za unhealthy
  health_check_grace_period_seconds = 300

  depends_on = [
    aws_lb_listener.keycloak_https,
    aws_ecs_service.postgres
  ]
}
