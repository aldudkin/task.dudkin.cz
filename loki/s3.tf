resource "aws_s3_bucket" "loki" {
  bucket = var.loki-s3-bucket-name
}

# https://registry.terraform.io/providers/-/aws/5.10.0/docs/resources/s3_bucket_public_access_block
resource "aws_s3_bucket_public_access_block" "loki" {
  bucket                  = aws_s3_bucket.loki.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


resource "aws_s3_bucket_server_side_encryption_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    apply_server_side_encryption_by_default {
      # kms_master_key_id = aws_kms_key.loki-encryption-key.arn
      # sse_algorithm     = "aws:kms" - placena sluzba
      sse_algorithm = "AES256"
    }
  }
}

# TODO: Data lifecycle managment (move old logs to Glacier)
