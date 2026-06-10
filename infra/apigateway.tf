# The HTTP API in front of the Lambda (step 9, adopted). Five pieces:
# api -> integration -> route -> stage, plus the permission that lets
# API Gateway invoke the function.

import {
  to = aws_apigatewayv2_api.api
  id = "z8v6craitg"
}

resource "aws_apigatewayv2_api" "api" {
  name          = "cloud-resume-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["POST", "OPTIONS"]
    allow_headers     = ["content-type"]
    max_age           = 0
  }
}

import {
  to = aws_apigatewayv2_integration.lambda
  id = "z8v6craitg/gewxpxh" # api-id/integration-id
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY" # hand the whole request to Lambda
  integration_uri        = aws_lambda_function.counter.arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

import {
  to = aws_apigatewayv2_route.post_count
  id = "z8v6craitg/sapbrz8" # api-id/route-id
}

resource "aws_apigatewayv2_route" "post_count" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /count" # the ONLY route — everything else 404s
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

import {
  to = aws_apigatewayv2_stage.default
  id = "z8v6craitg/$default" # api-id/stage-name
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true

  # Throttling (denial-of-wallet guard) — set by CLI on 2026-06-10, now code.
  default_route_settings {
    throttling_rate_limit  = 5  # steady requests/sec
    throttling_burst_limit = 10 # short spike allowance
  }
}

import {
  to = aws_lambda_permission.apigw_invoke
  id = "cloud-resume-visitor-counter/93b65cac-0fbb-59d2-a3eb-1a5ba18b4c7d" # function/statement-id
}

# Resource policy ON THE LAMBDA: only this API's /count route may invoke it.
resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "93b65cac-0fbb-59d2-a3eb-1a5ba18b4c7d" # console-generated UUID
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*/count"
}

# Printed after apply; other configs (and humans) can read it.
output "api_endpoint" {
  value       = "${aws_apigatewayv2_api.api.api_endpoint}/count"
  description = "The visitor-counter endpoint counter.js calls"
}
