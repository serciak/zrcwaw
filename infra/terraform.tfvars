region         = "us-east-1"
backend_image  = "docker.io/serciak/todos-backend:latest"
frontend_image = "docker.io/serciak/todos-frontend:latest"
backend_port   = 8000
frontend_port  = 80
db_username    = "todosuser"
db_password    = "todospassword"
db_name        = "todosdb"

# Keycloak / OIDC
keycloak_admin_password = "change-me"
keycloak_db_password    = "todospassword"
keycloak_db_name        = "todosdb"
oidc_realm              = "todos"
oidc_spa_client_id      = "todos-spa"
oidc_api_audience       = "todos-api"

# MinIO (S3-compatible storage)
minio_root_user     = "minioadmin"
minio_root_password = "minioadmin123"
minio_bucket_name   = "todos-files"

# Monitoring (Prometheus + Grafana)
prometheus_image       = "docker.io/serciak/todos-prometheus:latest"
grafana_image          = "docker.io/serciak/todos-grafana:latest"
grafana_admin_user     = "admin"
grafana_admin_password = "admin123"

