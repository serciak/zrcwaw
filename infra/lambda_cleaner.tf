resource "aws_lambda_function" "clean_completed_todos" {
  function_name = "clean-completed-todos"
  role          = data.aws_iam_role.labrole.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"

  filename         = "lambda_build/cleaner.zip"
  source_code_hash = filebase64sha256("lambda_build/cleaner.zip")

  environment {
    variables = {
      DB_HOST     = aws_db_instance.postgres.address
      DB_NAME     = var.db_name
      DB_USER     = var.db_username
      DB_PASSWORD = var.db_password
      S3_BUCKET   = aws_s3_bucket.files.bucket
    }
  }

  vpc_config {
    subnet_ids         = data.aws_subnets.default.ids
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
}

resource "aws_cloudwatch_event_rule" "cleaner_schedule" {
  name                = "clean-completed-todos-schedule"
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "cleaner_target" {
  rule      = aws_cloudwatch_event_rule.cleaner_schedule.name
  target_id = "lambda-cleaner"
  arn       = aws_lambda_function.clean_completed_todos.arn
}

resource "aws_lambda_permission" "allow_events_to_invoke_cleaner" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.clean_completed_todos.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cleaner_schedule.arn
}