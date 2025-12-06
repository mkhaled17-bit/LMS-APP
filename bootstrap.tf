# bootstrap.tf

provider "aws" {
  region = "us-east-1"
}

# 1. Generate a random suffix for unique names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# 2. Create the S3 Bucket for State
resource "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-state-${random_string.suffix.result}"
  
  # Force destroy allows deleting bucket even if it has files (Be careful in prod!)
  force_destroy = true 
  
  tags = {
    Name = "Terraform State Bucket"
  }
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 3. Create DynamoDB Table for Locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-locks-${random_string.suffix.result}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# 4. OUTPUT THE NAMES
output "s3_bucket_name" {
  value = aws_s3_bucket.terraform_state.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.terraform_locks.name
}