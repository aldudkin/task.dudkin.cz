resource "aws_s3_bucket" "terraform-state" {
  bucket = "terraform-state-0sl22y554u"
}

resource "aws_s3_bucket_versioning" "terraform-state-versioning" {
  bucket = aws_s3_bucket.terraform-state.id
  versioning_configuration {
    status = "Enabled"
  }
}