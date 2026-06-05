resource "aws_s3_bucket" "loki" {
  bucket = "loki-data-366112400496-eu-central-1"
}

# https://registry.terraform.io/providers/-/aws/5.10.0/docs/resources/s3_bucket_public_access_block
resource "aws_s3_bucket_public_access_block" "loki" {
  bucket = aws_s3_bucket.loki.id
  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}


resource "aws_s3_bucket_server_side_encryption_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    apply_server_side_encryption_by_default {
      # sse_algorithm     = "aws:kms" - placena sluzba
      sse_algorithm = "AES256"
    }
  }
}