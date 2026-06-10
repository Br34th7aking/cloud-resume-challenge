# The visitor-counter function. Terraform also takes over CODE deployment:
# the archive_file data source zips backend/lambda_function.py at plan time,
# and source_code_hash makes any source change show up in the plan.

data "archive_file" "counter_zip" {
  type        = "zip"
  source_file = "${path.module}/../backend/lambda_function.py"
  output_path = "${path.module}/build/lambda_function.zip"
}

import {
  to = aws_lambda_function.counter
  id = "cloud-resume-visitor-counter" # functions import by name
}

resource "aws_lambda_function" "counter" {
  function_name = "cloud-resume-visitor-counter"
  role          = aws_iam_role.lambda_exec.arn
  runtime       = "python3.14"
  handler       = "lambda_function.lambda_handler" # file.function
  architectures = ["x86_64"]
  timeout       = 3   # seconds (AWS default)
  memory_size   = 128 # MB (smallest = cheapest; plenty for one DB call)

  filename         = data.archive_file.counter_zip.output_path
  source_code_hash = data.archive_file.counter_zip.output_base64sha256
}
