output "backend_url" {
  description = "Public Backend URL"
  value       = "http://${aws_lb.backend.dns_name}"
}

output "frontend_url" {
  description = "Public Frontend URL"
  value       = "http://${aws_lb.frontend.dns_name}"
}

output "rds_endpoint" {
  description = "RDS PostgreSQL Endpoint"
  value = aws_db_instance.postgres.address
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value = aws_cognito_user_pool.users.id
}
output "cognito_app_client_id" {
  description = "Cognito App Client ID"
  value = aws_cognito_user_pool_client.web.id
}