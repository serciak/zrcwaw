# =============================================================================
# PLIK OUTPUTS.TF - WARTOŚCI WYJŚCIOWE TERRAFORM
# =============================================================================
# Ten plik definiuje wartości wyjściowe (outputs), które są wyświetlane po
# wykonaniu `terraform apply`. Outputs służą do:
# - Wyświetlania ważnych informacji (URL, endpoints)
# - Przekazywania wartości do innych konfiguracji Terraform (remote state)
# - Udostępniania danych dla skryptów i automatyzacji
# =============================================================================

# -----------------------------------------------------------------------------
# SEKCJA: URL-E APLIKACJI
# Główne endpointy dla użytkowników
# -----------------------------------------------------------------------------

output "backend_url" {
  description = "Public Backend URL"             # Opis outputu
  value       = "http://${aws_lb.backend.dns_name}"  # Wartość - URL backendu
  # Uwaga: Używa HTTP, ale jest redirect na HTTPS
}

output "frontend_url" {
  description = "Public Frontend URL"            # Opis outputu
  value       = "http://${aws_lb.frontend.dns_name}"  # Wartość - URL frontendu
  # To jest główny URL aplikacji dla użytkowników
}

# -----------------------------------------------------------------------------
# SEKCJA: URL-E KEYCLOAK (OIDC)
# Endpointy dla serwera autoryzacji
# -----------------------------------------------------------------------------

output "keycloak_url" {
  description = "Public Keycloak URL (HTTPS)"    # Opis
  value       = "https://${aws_lb.keycloak.dns_name}"  # URL konsoli admina Keycloak
  # Panel administracyjny Keycloak - /admin
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL used by backend/frontend"  # Opis
  value       = "https://${aws_lb.keycloak.dns_name}/realms/${var.oidc_realm}"
  # URL issuer'a OIDC używany do weryfikacji tokenów JWT
  # Format: https://keycloak-url/realms/realm-name
}

# -----------------------------------------------------------------------------
# SEKCJA: ENDPOINT BAZY DANYCH
# Wewnętrzny endpoint PostgreSQL
# -----------------------------------------------------------------------------

output "postgres_endpoint" {
  description = "PostgreSQL Internal NLB DNS (Fargate)"  # Opis
  value       = "${aws_lb.postgres.dns_name}:5432"       # DNS NLB z portem
  # UWAGA: To jest wewnętrzny endpoint, niedostępny z internetu!
  # Używany przez backend i Keycloak do połączenia z bazą
}

# -----------------------------------------------------------------------------
# SEKCJA: URL-E MINIO (S3-COMPATIBLE STORAGE)
# Endpointy dla magazynu obiektów
# -----------------------------------------------------------------------------

output "minio_api_url" {
  description = "MinIO S3 API URL (HTTPS)"       # Opis
  value       = "https://${aws_lb.minio.dns_name}"  # URL S3 API
  # Endpoint do operacji S3 (upload/download plików)
  # Używany przez backend do przechowywania plików
}

output "minio_console_url" {
  description = "MinIO Console URL (HTTPS)"      # Opis
  value       = "https://${aws_lb.minio.dns_name}:9001"  # URL konsoli webowej
  # Panel webowy do zarządzania bucketami i plikami
  # Logowanie: minioadmin / hasło z terraform.tfvars
}

# -----------------------------------------------------------------------------
# SEKCJA: URL-E MONITORINGU
# Endpointy dla Grafana i Prometheus
# -----------------------------------------------------------------------------

output "grafana_url" {
  description = "Grafana Dashboard URL (HTTPS)"  # Opis
  value       = "https://${aws_lb.monitoring.dns_name}"  # URL Grafana
  # Panel dashboardów i wizualizacji metryk
  # Logowanie: admin / hasło z terraform.tfvars
}

output "prometheus_url" {
  description = "Prometheus URL (HTTP)"          # Opis
  value       = "http://${aws_lb.monitoring.dns_name}:9090"  # URL Prometheus
  # Interfejs zapytań Prometheus (PromQL)
  # Używany głównie do debugowania i sprawdzania metryk
}
