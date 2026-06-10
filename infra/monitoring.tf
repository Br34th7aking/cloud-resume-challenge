# Alerting chain (session 2, adopted): alarms -> SNS -> PagerDuty (-> Slack).

# The PagerDuty integration URL embeds a key that lets anyone send events to
# our service — secret-ish, and this repo is public. So: declared here,
# value supplied via terraform.tfvars (gitignored).
variable "pagerduty_endpoint" {
  type        = string
  description = "PagerDuty CloudWatch-integration enqueue URL"
  sensitive   = true # redacted in plan/apply output
}

import {
  to = aws_sns_topic.alarms
  id = "arn:aws:sns:ap-south-1:695331051459:cloud-resume-alarms"
}

resource "aws_sns_topic" "alarms" {
  name = "cloud-resume-alarms"
}

import {
  to = aws_sns_topic_subscription.pagerduty
  id = "arn:aws:sns:ap-south-1:695331051459:cloud-resume-alarms:ed4555fd-673b-4aa7-bb38-90569895d26b"
}

resource "aws_sns_topic_subscription" "pagerduty" {
  topic_arn              = aws_sns_topic.alarms.arn
  protocol               = "https"
  endpoint               = var.pagerduty_endpoint
  endpoint_auto_confirms = true # PagerDuty auto-confirms the subscription
}

import {
  to = aws_cloudwatch_metric_alarm.lambda_errors
  id = "cloud-resume-lambda-errors"
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "cloud-resume-lambda-errors"
  alarm_description   = "Visitor counter Lambda threw an error"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300 # one 5-minute window
  evaluation_periods  = 1
  threshold           = 1 # any single error pages
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching" # no invocations = healthy, not unknown

  dimensions = {
    FunctionName = aws_lambda_function.counter.function_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn] # OK -> PagerDuty auto-resolve
}

import {
  to = aws_cloudwatch_metric_alarm.api_5xx
  id = "cloud-resume-api-5xx"
}

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "cloud-resume-api-5xx"
  alarm_description   = "Cloud Resume API returned 5xx server errors"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiId = aws_apigatewayv2_api.api.id
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}
