# CI/CD auth (steps 14-15): GitHub Actions assumes a role via OpenID Connect.
# No AWS keys are stored in GitHub — each workflow run trades a short-lived
# GitHub-signed token for ~1h of temporary AWS credentials.

# Registers GitHub as a trusted identity provider in this account.
# One of these per account, shared by every repo/role that uses GitHub OIDC.
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  # The "audience" CI tokens must be minted for. sts.amazonaws.com is the
  # value AWS's official configure-aws-credentials action requests.
  client_id_list = ["sts.amazonaws.com"]
}

# The role CI runs as. The trust policy is the security boundary: only
# workflow runs from OUR repo's main branch can assume it.
resource "aws_iam_role" "github_actions" {
  name = "cloud-resume-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          # Belt: token was minted for AWS...
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          # ...and suspenders: by our repo, on main. A fork, another repo,
          # or a feature branch gets AccessDenied.
          "token.actions.githubusercontent.com:sub" = "repo:Br34th7aking/cloud-resume-challenge:ref:refs/heads/main"
        }
      }
    }]
  })
}

# What CI may actually DO: scoped to this stack's resources, statement per
# service. Built to fail closed — a new resource type in infra/ will need a
# new statement here (applied from the laptop).
resource "aws_iam_role_policy" "github_actions_permissions" {
  name = "cloud-resume-ci"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "TfStateList"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::abhijitraj-crc-tfstate"
      },
      {
        Sid      = "TfStateObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::abhijitraj-crc-tfstate/cloud-resume-challenge/*"
      },
      {
        Sid      = "Dynamo"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = aws_dynamodb_table.visitors.arn
      },
      {
        Sid      = "Lambda"
        Effect   = "Allow"
        Action   = "lambda:*"
        Resource = aws_lambda_function.counter.arn
      },
      {
        # API Gateway IAM is REST-style verbs against path ARNs, not
        # per-API actions — so this is region-wide by necessity.
        Sid      = "ApiGateway"
        Effect   = "Allow"
        Action   = ["apigateway:GET", "apigateway:POST", "apigateway:PATCH", "apigateway:PUT", "apigateway:DELETE"]
        Resource = "arn:aws:apigateway:ap-south-1::/*"
      },
      {
        # Trailing * covers the topic AND its subscriptions
        # (subscription ARN = topic ARN + ":uuid").
        Sid      = "SnsAlarms"
        Effect   = "Allow"
        Action   = "sns:*"
        Resource = "${aws_sns_topic.alarms.arn}*"
      },
      {
        Sid      = "CloudWatchAlarms"
        Effect   = "Allow"
        Action   = ["cloudwatch:DescribeAlarms", "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:ListTagsForResource"]
        Resource = "arn:aws:cloudwatch:ap-south-1:${data.aws_caller_identity.current.account_id}:alarm:cloud-resume-*"
      },
      {
        # READ on everything Terraform refreshes — including this role
        # itself and the OIDC provider.
        Sid    = "IamRead"
        Effect = "Allow"
        Action = ["iam:Get*", "iam:List*"]
        Resource = [
          aws_iam_role.lambda_exec.arn,
          aws_iam_policy.lambda_logs.arn,
          aws_iam_role.github_actions.arn,
          aws_iam_openid_connect_provider.github.arn,
        ]
      },
      {
        # WRITE only on the Lambda's role/policy — deliberately NOT on
        # this CI role, so CI can never widen its own permissions.
        Sid    = "IamWriteLambdaRole"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:TagRole", "iam:UntagRole",
          "iam:CreatePolicy", "iam:DeletePolicy", "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion", "iam:TagPolicy", "iam:UntagPolicy",
        ]
        Resource = [
          aws_iam_role.lambda_exec.arn,
          aws_iam_policy.lambda_logs.arn,
        ]
      },
      {
        # Updating the function's config means handing it its execution
        # role — that handoff is a separate permission.
        Sid      = "PassExecRoleToLambda"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.lambda_exec.arn
        Condition = {
          StringEquals = { "iam:PassedToService" = "lambda.amazonaws.com" }
        }
      },
      {
        Sid      = "FrontendBucketList"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::abhijitraj-resume-crc"
      },
      {
        Sid      = "FrontendBucketSync"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::abhijitraj-resume-crc/*"
      },
      {
        Sid      = "FrontendInvalidate"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
        Resource = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/E2N3X21KFIF3UP"
      },
    ]
  })
}

output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions.arn
  description = "Role the GitHub Actions workflows assume via OIDC"
}
