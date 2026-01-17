output "backend_url" {
  description = "Public Backend URL"
  value       = "http://${aws_lb.backend.dns_name}"
}

output "frontend_url" {
  description = "Public Frontend URL"
  value       = "http://${aws_lb.frontend.dns_name}"
}

output "keycloak_url" {
  description = "Public Keycloak URL (HTTPS)"
  value       = "https://${aws_lb.keycloak.dns_name}"
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL used by backend/frontend"
  value       = "https://${aws_lb.keycloak.dns_name}/realms/${var.oidc_realm}"
}

output "rds_endpoint" {
  description = "RDS PostgreSQL Endpoint"
  value       = aws_db_instance.postgres.address
}

output "minio_api_url" {
  description = "MinIO S3 API URL (HTTPS)"
  value       = "https://${aws_lb.minio.dns_name}"
}

output "minio_console_url" {
  description = "MinIO Console URL (HTTPS)"
  value       = "https://${aws_lb.minio.dns_name}:9001"
}

