# The Lambda's execution role + its two policies (created by console in step
# 10, adopted here). A "data" source reads facts instead of managing things.

data "aws_caller_identity" "current" {} # exposes our account id

import {
  to = aws_iam_role.lambda_exec
  id = "cloud-resume-visitor-counter-role-kca8vrd3" # roles import by name
}

resource "aws_iam_role" "lambda_exec" {
  name = "cloud-resume-visitor-counter-role-kca8vrd3"
  path = "/service-role/" # where the console puts roles it generates

  # Who may *become* this role: the Lambda service itself.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

import {
  to = aws_iam_role_policy.dynamodb_access
  id = "cloud-resume-visitor-counter-role-kca8vrd3:dynamodb-visitor-counter-access" # role:policy
}

# Least-privilege table access — aws/lambda-dynamodb-policy.json, now as code.
# Resource is a REFERENCE to the imported table, not a pasted ARN.
resource "aws_iam_role_policy" "dynamodb_access" {
  name = "dynamodb-visitor-counter-access"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AllowVisitorCounterTableAccess"
      Effect   = "Allow"
      Action   = ["dynamodb:UpdateItem", "dynamodb:GetItem"]
      Resource = aws_dynamodb_table.visitors.arn
    }]
  })
}

import {
  to = aws_iam_policy.lambda_logs
  id = "arn:aws:iam::695331051459:policy/service-role/AWSLambdaBasicExecutionRole-a268feb5-55d8-48c0-9d8c-65a20b9da120"
}

# Console-generated CloudWatch Logs policy (UUID name is console residue).
resource "aws_iam_policy" "lambda_logs" {
  name = "AWSLambdaBasicExecutionRole-a268feb5-55d8-48c0-9d8c-65a20b9da120"
  path = "/service-role/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "logs:CreateLogGroup"
        Resource = "arn:aws:logs:ap-south-1:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          "arn:aws:logs:ap-south-1:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/cloud-resume-visitor-counter:*"
        ]
      }
    ]
  })
}

import {
  to = aws_iam_role_policy_attachment.lambda_logs
  id = "cloud-resume-visitor-counter-role-kca8vrd3/arn:aws:iam::695331051459:policy/service-role/AWSLambdaBasicExecutionRole-a268feb5-55d8-48c0-9d8c-65a20b9da120"
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_logs.arn
}
