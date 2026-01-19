# =============================================================================
# PLIK TERRAFORM.TFVARS - WARTOŚCI ZMIENNYCH DLA ŚRODOWISKA
# =============================================================================
# Ten plik zawiera konkretne wartości zmiennych zdefiniowanych w variables.tf
# Terraform automatycznie ładuje pliki z rozszerzeniem .tfvars
# UWAGA: Ten plik często zawiera wrażliwe dane i NIE powinien być
# commitowany do publicznego repozytorium! Dodaj go do .gitignore
# =============================================================================

# -----------------------------------------------------------------------------
# SEKCJA: PODSTAWOWA KONFIGURACJA AWS I APLIKACJI
# -----------------------------------------------------------------------------

region         = "us-east-1"                              # Region AWS gdzie zostaną utworzone zasoby (US East - Virginia)
backend_image  = "docker.io/serciak/todos-backend:latest" # Pełna ścieżka do obrazu Docker backendu na Docker Hub
frontend_image = "docker.io/serciak/todos-frontend:latest" # Pełna ścieżka do obrazu Docker frontendu na Docker Hub
backend_port   = 8000                                     # Port na którym FastAPI nasłuchuje wewnątrz kontenera
frontend_port  = 80                                       # Port na którym Nginx serwuje frontend wewnątrz kontenera

# -----------------------------------------------------------------------------
# SEKCJA: KONFIGURACJA BAZY DANYCH POSTGRESQL
# -----------------------------------------------------------------------------

db_username    = "todosuser"                              # Nazwa użytkownika do połączenia z bazą PostgreSQL
db_password    = "todospassword"                          # Hasło użytkownika bazy danych (ZMIEŃ NA PRODUKCJI!)
db_name        = "todosdb"                                # Nazwa bazy danych dla aplikacji

# -----------------------------------------------------------------------------
# SEKCJA: KONFIGURACJA KEYCLOAK / OIDC
# Keycloak to serwer autoryzacji implementujący protokół OpenID Connect
# -----------------------------------------------------------------------------

keycloak_admin_password = "change-me"                     # Hasło administratora Keycloak (ZMIEŃ NA PRODUKCJI!)
keycloak_db_password    = "todospassword"                 # Hasło do bazy danych używanej przez Keycloak
keycloak_db_name        = "todosdb"                       # Nazwa bazy danych Keycloak (współdzielona z aplikacją)
oidc_realm              = "todos"                         # Nazwa realm'u w Keycloak - izolowana przestrzeń konfiguracji
oidc_spa_client_id      = "todos-spa"                     # Client ID dla frontendu (Single Page Application)
oidc_api_audience       = "todos-api"                     # Audience w tokenach JWT - backend sprawdza tę wartość

# -----------------------------------------------------------------------------
# SEKCJA: KONFIGURACJA MINIO (S3-COMPATIBLE STORAGE)
# MinIO to samodzielnie hostowany magazyn obiektów kompatybilny z AWS S3
# -----------------------------------------------------------------------------

minio_root_user     = "minioadmin"                        # Nazwa użytkownika root MinIO (jak AWS Access Key ID)
minio_root_password = "minioadmin123"                     # Hasło root MinIO (jak AWS Secret Access Key) - ZMIEŃ NA PRODUKCJI!
minio_bucket_name   = "todos-files"                       # Nazwa bucketu do przechowywania plików użytkowników

# -----------------------------------------------------------------------------
# SEKCJA: KONFIGURACJA MONITORINGU (PROMETHEUS + GRAFANA)
# Prometheus zbiera metryki, Grafana je wizualizuje na dashboardach
# -----------------------------------------------------------------------------

prometheus_image       = "docker.io/serciak/todos-prometheus:latest" # Własny obraz Prometheus z pre-konfiguracją
grafana_image          = "docker.io/serciak/todos-grafana:latest"    # Własny obraz Grafana z dashboardami
grafana_admin_user     = "admin"                                      # Nazwa użytkownika administratora Grafana
grafana_admin_password = "admin123"                                   # Hasło administratora Grafana (ZMIEŃ NA PRODUKCJI!)
