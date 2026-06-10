# The visitor-counter table. Created by hand in step 8; adopted here.

import {
  to = aws_dynamodb_table.visitors
  id = "cloud-resume-visitors" # DynamoDB tables import by name
}

resource "aws_dynamodb_table" "visitors" {
  name         = "cloud-resume-visitors"
  billing_mode = "PAY_PER_REQUEST" # on-demand, ~$0 at our traffic
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}
