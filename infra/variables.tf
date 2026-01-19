# =============================================================================
# PLIK VARIABLES.TF - DEFINICJE ZMIENNYCH TERRAFORM
# =============================================================================
# Ten plik definiuje wszystkie zmienne wejściowe używane w konfiguracji
# Terraform. Zmienne pozwalają na parametryzację konfiguracji i ułatwiają
# ponowne wykorzystanie kodu w różnych środowiskach.
# =============================================================================

# -----------------------------------------------------------------------------
# SEKCJA: KONFIGURACJA AWS
# Zmienne związane z podstawową konfiguracją AWS
# -----------------------------------------------------------------------------

variable "region" {                    # Deklaracja zmiennej o nazwie "region"
  description = "AWS region"           # Opis zmiennej wyświetlany w dokumentacji i terraform plan
  type        = string                 # Typ zmiennej - ciąg znaków (np. "us-east-1")
  default     = "us-east-1"            # Wartość domyślna używana gdy zmienna nie zostanie nadpisana
}

# -----------------------------------------------------------------------------
# SEKCJA: OBRAZY DOCKER DLA APLIKACJI
# Zmienne określające obrazy Docker dla frontendu i backendu
# -----------------------------------------------------------------------------

variable "backend_image" {             # Zmienna przechowująca ścieżkę do obrazu Docker backendu
  description = "Docker image for backend"  # Opis - obraz Docker dla serwisu backendowego
  type        = string                 # Typ string - oczekiwana wartość np. "docker.io/user/image:tag"
}                                      # Brak default = zmienna jest WYMAGANA

variable "frontend_image" {            # Zmienna przechowująca ścieżkę do obrazu Docker frontendu
  description = "Docker image for frontend" # Opis - obraz Docker dla serwisu frontendowego
  type        = string                 # Typ string - oczekiwana wartość np. "docker.io/user/image:tag"
}                                      # Brak default = zmienna jest WYMAGANA

# -----------------------------------------------------------------------------
# SEKCJA: PORTY APLIKACJI
# Zmienne definiujące porty na których nasłuchują kontenery
# -----------------------------------------------------------------------------

variable "backend_port" {              # Zmienna definiująca port backendu
  description = "Backend container port"  # Opis - port na którym nasłuchuje kontener backendowy
  type        = number                 # Typ number - wartość numeryczna (integer)
  default     = 8000                   # Domyślnie FastAPI nasłuchuje na porcie 8000
}

variable "frontend_port" {             # Zmienna definiująca port frontendu
  description = "Frontend container port (Nginx)" # Opis - port Nginx serwującego frontend
  type        = number                 # Typ number - wartość numeryczna
  default     = 80                     # Domyślnie Nginx nasłuchuje na standardowym porcie HTTP 80
}

# -----------------------------------------------------------------------------
# SEKCJA: KONFIGURACJA BAZY DANYCH POSTGRESQL
# Zmienne związane z bazą danych PostgreSQL hostowaną na Fargate
# -----------------------------------------------------------------------------

variable "db_username" {               # Zmienna z nazwą użytkownika bazy danych
  description = "PostgreSQL username (Fargate-hosted)" # Opis - nazwa użytkownika PostgreSQL
  type        = string                 # Typ string
  default     = "todosuser"            # Domyślna nazwa użytkownika dla aplikacji todos
}

variable "db_password" {               # Zmienna z hasłem do bazy danych
  description = "PostgreSQL password (Fargate-hosted)" # Opis - hasło do PostgreSQL
  type        = string                 # Typ string
  sensitive   = true                   # WAŻNE: sensitive=true ukrywa wartość w logach terraform
}                                      # Brak default = zmienna WYMAGANA (bezpieczna praktyka dla haseł)

variable "db_name" {                   # Zmienna z nazwą bazy danych
  description = "PostgreSQL database name (Fargate-hosted)" # Opis - nazwa bazy danych
  type        = string                 # Typ string
  default     = "todosdb"              # Domyślna nazwa bazy dla aplikacji todos
}

# -----------------------------------------------------------------------------
# SEKCJA: KONFIGURACJA KEYCLOAK (SERWER AUTORYZACJI OIDC)
# Zmienne związane z Keycloak - serwerem Identity and Access Management
# -----------------------------------------------------------------------------

variable "keycloak_image" {            # Zmienna z obrazem Docker Keycloak
  description = "Docker image for Keycloak" # Opis - obraz Docker dla Keycloak
  type        = string                 # Typ string
  default     = "quay.io/keycloak/keycloak:25.0.6" # Oficjalny obraz Keycloak z Quay.io, wersja 25.0.6
}

variable "keycloak_admin_user" {       # Zmienna z nazwą administratora Keycloak
  description = "Keycloak admin username" # Opis - nazwa użytkownika admina Keycloak
  type        = string                 # Typ string
  default     = "admin"                # Domyślna nazwa administratora
}

variable "keycloak_admin_password" {   # Zmienna z hasłem administratora Keycloak
  description = "Keycloak admin password" # Opis - hasło admina Keycloak
  type        = string                 # Typ string
  sensitive   = true                   # Ukrywa hasło w logach terraform (bezpieczeństwo)
}

variable "keycloak_db_password" {      # Zmienna z hasłem do bazy danych używanej przez Keycloak
  description = "Database password used by Keycloak" # Opis - hasło DB dla Keycloak
  type        = string                 # Typ string
  sensitive   = true                   # Ukrywa hasło w logach (bezpieczeństwo)
}

variable "keycloak_db_name" {          # Zmienna z nazwą bazy danych Keycloak
  description = "Database name used by Keycloak (schema/db)" # Opis - nazwa bazy/schematu
  type        = string                 # Typ string
  default     = "todosdb"              # Używa tej samej bazy co aplikacja (różne tabele)
}

variable "keycloak_db_username" {      # Zmienna z nazwą użytkownika bazy Keycloak
  description = "Database username used by Keycloak" # Opis - użytkownik DB dla Keycloak
  type        = string                 # Typ string
  default     = "todosuser"            # Ten sam użytkownik co aplikacja
}

# -----------------------------------------------------------------------------
# SEKCJA: KONFIGURACJA OIDC (OpenID Connect)
# Zmienne związane z konfiguracją protokołu autoryzacji OIDC
# -----------------------------------------------------------------------------

variable "oidc_realm" {                # Zmienna z nazwą realm'u Keycloak
  description = "Keycloak realm name"  # Opis - nazwa realm'u (przestrzeni nazw) w Keycloak
  type        = string                 # Typ string
  default     = "todos"                # Realm dla aplikacji todos
}

variable "oidc_spa_client_id" {        # Zmienna z client_id dla aplikacji SPA (frontend)
  description = "Keycloak client_id for SPA" # Opis - identyfikator klienta dla Single Page App
  type        = string                 # Typ string
  default     = "todos-spa"            # Nazwa klienta zarejestrowanego w Keycloak dla frontendu
}

variable "oidc_api_audience" {         # Zmienna z audience/client_id dla API (backend)
  description = "Audience/client_id expected by backend when verifying tokens" # Opis
  type        = string                 # Typ string
  default     = "todos-api"            # Backend sprawdza czy token ma tę wartość w "aud" claim
}

# -----------------------------------------------------------------------------
# SEKCJA: KONFIGURACJA MINIO (S3-COMPATIBLE STORAGE)
# Zmienne związane z MinIO - samodzielnie hostowalnym magazynem obiektów
# kompatybilnym z AWS S3 API
# -----------------------------------------------------------------------------

variable "minio_image" {               # Zmienna z obrazem Docker MinIO
  description = "Docker image for MinIO" # Opis - obraz Docker dla MinIO
  type        = string                 # Typ string
  default     = "minio/minio:latest"   # Oficjalny obraz MinIO, najnowsza wersja
}

variable "minio_root_user" {           # Zmienna z nazwą użytkownika root MinIO
  description = "MinIO root username"  # Opis - nazwa użytkownika root (odpowiednik AWS access key)
  type        = string                 # Typ string
  default     = "minioadmin"           # Domyślna nazwa użytkownika MinIO
}

variable "minio_root_password" {       # Zmienna z hasłem root MinIO
  description = "MinIO root password"  # Opis - hasło root (odpowiednik AWS secret key)
  type        = string                 # Typ string
  sensitive   = true                   # Ukrywa hasło w logach (bezpieczeństwo)
}

variable "minio_bucket_name" {         # Zmienna z nazwą bucketu MinIO
  description = "MinIO bucket name for file storage" # Opis - nazwa bucketu na pliki
  type        = string                 # Typ string
  default     = "todos-files"          # Nazwa bucketu dla plików aplikacji todos
}

# -----------------------------------------------------------------------------
# SEKCJA: KONFIGURACJA MONITORINGU (PROMETHEUS + GRAFANA)
# Zmienne związane ze stosem monitoringu aplikacji
# -----------------------------------------------------------------------------

variable "prometheus_image" {          # Zmienna z obrazem Docker Prometheus
  description = "Docker image for Prometheus" # Opis - obraz Docker dla Prometheus
  type        = string                 # Typ string
}                                      # Brak default = WYMAGANA (używamy własnego obrazu z konfiguracją)

variable "grafana_image" {             # Zmienna z obrazem Docker Grafana
  description = "Docker image for Grafana" # Opis - obraz Docker dla Grafana
  type        = string                 # Typ string
  default     = "grafana/grafana:11.4.0" # Oficjalny obraz Grafana, wersja 11.4.0
}

variable "grafana_admin_user" {        # Zmienna z nazwą administratora Grafana
  description = "Grafana admin username" # Opis - nazwa admina Grafana
  type        = string                 # Typ string
  default     = "admin"                # Domyślna nazwa administratora
}

variable "grafana_admin_password" {    # Zmienna z hasłem administratora Grafana
  description = "Grafana admin password" # Opis - hasło admina Grafana
  type        = string                 # Typ string
  sensitive   = true                   # Ukrywa hasło w logach (bezpieczeństwo)
}
