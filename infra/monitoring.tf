# Monitoring Stack: Prometheus + Grafana on ECS Fargate
# Prometheus collects metrics from backend, Grafana visualizes them

locals {
  prometheus_container_name = "prometheus"
  prometheus_port           = 9090
  grafana_container_name    = "grafana"
  grafana_port              = 3000
}

# --- CloudWatch Log Groups for Monitoring
resource "aws_cloudwatch_log_group" "prometheus" {
  name              = "/ecs/prometheus"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "grafana" {
  name              = "/ecs/grafana"
  retention_in_days = 14
}

# --- Security Groups for Monitoring ALB
resource "aws_security_group" "alb_monitoring_sg" {
  name        = "alb-monitoring-sg"
  description = "Allow HTTP/HTTPS to Monitoring ALB (Grafana)"
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

  # Prometheus port for internal access
  ingress {
    from_port   = local.prometheus_port
    to_port     = local.prometheus_port
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

resource "aws_security_group" "monitoring_tasks_sg" {
  name        = "monitoring-tasks-sg"
  description = "Allow ALB to reach monitoring tasks"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Prometheus from ALB"
    from_port       = local.prometheus_port
    to_port         = local.prometheus_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_monitoring_sg.id]
  }

  ingress {
    description     = "Grafana from ALB"
    from_port       = local.grafana_port
    to_port         = local.grafana_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_monitoring_sg.id]
  }

  # Internal access for scraping
  ingress {
    description = "Prometheus scraping from VPC"
    from_port   = local.prometheus_port
    to_port     = local.prometheus_port
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

# Allow Prometheus to scrape backend metrics
resource "aws_security_group_rule" "backend_metrics_from_prometheus" {
  type                     = "ingress"
  from_port                = var.backend_port
  to_port                  = var.backend_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ecs_tasks_sg.id
  source_security_group_id = aws_security_group.monitoring_tasks_sg.id
  description              = "Allow Prometheus to scrape backend metrics"
}

# --- ALB for Monitoring (Grafana + Prometheus)
resource "aws_lb" "monitoring" {
  name               = "monitoring-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_monitoring_sg.id]
  subnets            = data.aws_subnets.default.ids
}

# --- Target Groups
resource "aws_lb_target_group" "prometheus" {
  name        = "tg-prometheus"
  port        = local.prometheus_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id

  health_check {
    path                = "/-/healthy"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }
}

resource "aws_lb_target_group" "grafana" {
  name        = "tg-grafana"
  port        = local.grafana_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id

  health_check {
    path                = "/api/health"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }
}

# --- Self-signed certificate for Monitoring ALB
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

# --- ALB Listeners
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

resource "aws_lb_listener" "monitoring_https" {
  load_balancer_arn = aws_lb.monitoring.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.monitoring.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }
}

# Prometheus listener on port 9090
resource "aws_lb_listener" "prometheus" {
  load_balancer_arn = aws_lb.monitoring.arn
  port              = local.prometheus_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prometheus.arn
  }
}

# --- EFS for Prometheus data persistence
resource "aws_efs_file_system" "prometheus" {
  creation_token = "prometheus-data"
  encrypted      = true

  tags = {
    Name = "prometheus-data"
  }
}

resource "aws_efs_access_point" "prometheus" {
  file_system_id = aws_efs_file_system.prometheus.id

  posix_user {
    uid = 0
    gid = 0
  }

  root_directory {
    path = "/prometheus"
    creation_info {
      owner_uid   = 0
      owner_gid   = 0
      permissions = "755"
    }
  }

  tags = {
    Name = "prometheus-access-point"
  }
}

resource "aws_efs_mount_target" "prometheus" {
  count           = length(data.aws_subnets.default.ids)
  file_system_id  = aws_efs_file_system.prometheus.id
  subnet_id       = data.aws_subnets.default.ids[count.index]
  security_groups = [aws_security_group.efs_prometheus_sg.id]
}

resource "aws_security_group" "efs_prometheus_sg" {
  name        = "efs-prometheus-sg"
  description = "Allow NFS for Prometheus EFS"
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

# --- EFS for Grafana data persistence
resource "aws_efs_file_system" "grafana" {
  creation_token = "grafana-data"
  encrypted      = true

  tags = {
    Name = "grafana-data"
  }
}

resource "aws_efs_access_point" "grafana" {
  file_system_id = aws_efs_file_system.grafana.id

  posix_user {
    uid = 0
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

resource "aws_efs_mount_target" "grafana" {
  count           = length(data.aws_subnets.default.ids)
  file_system_id  = aws_efs_file_system.grafana.id
  subnet_id       = data.aws_subnets.default.ids[count.index]
  security_groups = [aws_security_group.efs_grafana_sg.id]
}

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

# --- Prometheus Task Definition
resource "aws_ecs_task_definition" "prometheus" {
  family                   = "prometheus-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = data.aws_iam_role.labrole.arn
  task_role_arn            = data.aws_iam_role.labrole.arn

  volume {
    name = "prometheus-data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.prometheus.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.prometheus.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name  = local.prometheus_container_name
      image = var.prometheus_image
      user  = "root"
      portMappings = [
        {
          containerPort = local.prometheus_port
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "BACKEND_TARGET", value = "${aws_lb.backend.dns_name}" },
        { name = "PROMETHEUS_ENV", value = "aws" }
      ]
      mountPoints = [
        {
          sourceVolume  = "prometheus-data"
          containerPath = "/prometheus"
          readOnly      = false
        }
      ]
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

# --- Grafana Task Definition
resource "aws_ecs_task_definition" "grafana" {
  family                   = "grafana-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = data.aws_iam_role.labrole.arn
  task_role_arn            = data.aws_iam_role.labrole.arn

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
      name  = local.grafana_container_name
      image = var.grafana_image
      user  = "root"
      portMappings = [
        {
          containerPort = local.grafana_port
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "GF_SECURITY_ADMIN_USER", value = var.grafana_admin_user },
        { name = "GF_SECURITY_ADMIN_PASSWORD", value = var.grafana_admin_password },
        { name = "GF_SERVER_ROOT_URL", value = "https://${aws_lb.monitoring.dns_name}" },
        { name = "GF_SERVER_DOMAIN", value = aws_lb.monitoring.dns_name },
        # Auto-provision Prometheus datasource
        { name = "GF_INSTALL_PLUGINS", value = "" },
        { name = "GF_USERS_ALLOW_SIGN_UP", value = "false" },
        # Prometheus datasource URL - internal ALB DNS
        { name = "PROMETHEUS_URL", value = "http://${aws_lb.monitoring.dns_name}:${local.prometheus_port}" }
      ]
      mountPoints = [
        {
          sourceVolume  = "grafana-data"
          containerPath = "/var/lib/grafana"
          readOnly      = false
        }
      ]
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

# --- ECS Services
resource "aws_ecs_service" "prometheus" {
  name            = "prometheus-svc"
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
    aws_lb_listener.prometheus,
    aws_efs_mount_target.prometheus
  ]
}

resource "aws_ecs_service" "grafana" {
  name            = "grafana-svc"
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
    aws_lb_listener.monitoring_https,
    aws_efs_mount_target.grafana,
    aws_ecs_service.prometheus
  ]
}
