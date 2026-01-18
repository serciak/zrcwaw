variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "backend_image" {
  description = "Docker image for backend"
  type        = string
}

variable "frontend_image" {
  description = "Docker image for frontend"
  type        = string
}

variable "backend_port" {
  description = "Backend container port"
  type        = number
  default     = 8000
}

variable "frontend_port" {
  description = "Frontend container port (Nginx)"
  type        = number
  default     = 80
}

variable "db_username" {
  description = "PostgreSQL username (Fargate-hosted)"
  type        = string
  default     = "todosuser"
}

variable "db_password" {
  description = "PostgreSQL password (Fargate-hosted)"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "PostgreSQL database name (Fargate-hosted)"
  type        = string
  default     = "todosdb"
}

variable "keycloak_image" {
  description = "Docker image for Keycloak"
  type        = string
  default     = "quay.io/keycloak/keycloak:25.0.6"
}

variable "keycloak_admin_user" {
  description = "Keycloak admin username"
  type        = string
  default     = "admin"
}

variable "keycloak_admin_password" {
  description = "Keycloak admin password"
  type        = string
  sensitive   = true
}

variable "keycloak_db_password" {
  description = "Database password used by Keycloak"
  type        = string
  sensitive   = true
}

variable "keycloak_db_name" {
  description = "Database name used by Keycloak (schema/db)"
  type        = string
  default     = "todosdb"
}

variable "keycloak_db_username" {
  description = "Database username used by Keycloak"
  type        = string
  default     = "todosuser"
}

variable "oidc_realm" {
  description = "Keycloak realm name"
  type        = string
  default     = "todos"
}

variable "oidc_spa_client_id" {
  description = "Keycloak client_id for SPA"
  type        = string
  default     = "todos-spa"
}

variable "oidc_api_audience" {
  description = "Audience/client_id expected by backend when verifying tokens"
  type        = string
  default     = "todos-api"
}

# MinIO configuration
variable "minio_image" {
  description = "Docker image for MinIO"
  type        = string
  default     = "minio/minio:latest"
}

variable "minio_root_user" {
  description = "MinIO root username"
  type        = string
  default     = "minioadmin"
}

variable "minio_root_password" {
  description = "MinIO root password"
  type        = string
  sensitive   = true
}

variable "minio_bucket_name" {
  description = "MinIO bucket name for file storage"
  type        = string
  default     = "todos-files"
}

# Monitoring configuration (Prometheus + Grafana)
variable "prometheus_image" {
  description = "Docker image for Prometheus"
  type        = string
}

variable "grafana_image" {
  description = "Docker image for Grafana"
  type        = string
  default     = "grafana/grafana:11.4.0"
}

variable "grafana_admin_user" {
  description = "Grafana admin username"
  type        = string
  default     = "admin"
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}

