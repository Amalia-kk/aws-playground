provider "aws" {
    region = "eu-west-2"
}

resource "aws_s3_bucket" "terraform_state" {
    bucket = "amalia-learning-bucket"  # This needs to be unique

    # Prevent accidental deletion of this S3 bucket
    lifecycle {
        prevent_destroy = true
    }
}

resource "aws_s3_bucket_versioning" "enabled" {
    bucket     = aws_s3_bucket.terraform-state.id

    versioning_configuration {
        status = "enabled"
    }
}

resource "aws_server_side_encryption_configuration" "default" {
    bucket                = aws_s3_bucket.terraform_state.id

    rule {
        apply_server_side_encryption_by_default {
            sse_algorithm = "AES256"
        }
    }
}

resource "aws_s3_bucket_public_access_block" "public_access" {
    bucket                  = aws_s3_bucket.terraform_state.id
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_locks" {     # Used for locking
    name         = "terraform-up-and-running-locks"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "LOCK_ID"

    attribute {
        name     = "LockID"
        type     = "S"
    }
}

terraform {
    backend "s3" {
        bucket         = "amalia-learning-bucket"
        key            = "global/s3/terraform.tfstate"     # Where the state file should be written
        region         = "eu-west-2"

        dynamodb_table = "terraform-up-and-running-locks"  
        encrypt        = true
    }
}

output "s3_bucket_arn" {
    value       = aws_s3_bucket.terraform_state.arn
    description = "The ARN of the S3 bucket"
}

output "dynamodb_table_name" {
    value       = aws_dynamodb_table.terraform_locks.name
    description = "The name of the DynamoDB table"
}

