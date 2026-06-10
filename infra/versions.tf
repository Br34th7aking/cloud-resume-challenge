# Foundation: which Terraform, which providers, where state lives.

terraform {
  # Guard rail: anyone running this needs at least this Terraform version.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws" # the plugin that translates HCL -> AWS API calls
      version = "~> 6.0"        # any 6.x, never 7.x (majors can break things)
    }
  }

  # Remote state: the tfstate file lives in S3, not on this laptop.
  # The bucket itself is the one hand-made bootstrap resource.
  backend "s3" {
    bucket       = "abhijitraj-crc-tfstate"
    key          = "cloud-resume-challenge/terraform.tfstate" # path within the bucket
    region       = "ap-south-1"
    use_lockfile = true # native S3 locking (no DynamoDB lock table needed)
  }
}

provider "aws" {
  region = "ap-south-1" # uses the same ~/.aws credentials as the CLI
}
