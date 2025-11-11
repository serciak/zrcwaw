variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "backend_image" {
  description = "Docker image for backend (Docker Hub), e.g. docker.io/serciak/my-backend:latest"
  type        = string
}

variable "frontend_image" {
  description = "Docker image for frontend (Docker Hub), e.g. docker.io/serciak/my-frontend:latest"
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
  description = "RDS PostgreSQL username"
  type        = string
  default     = "todosuser"
}

variable "db_password" {
  description = "RDS PostgreSQL password"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "RDS PostgreSQL database name"
  type        = string
  default     = "todosdb"
}