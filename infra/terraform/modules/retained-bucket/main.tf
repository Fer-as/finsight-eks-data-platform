variable "name" {
  description = "Globally unique S3 bucket name."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.name))
    error_message = "Supply a valid unique lowercase bucket name."
  }
}
variable "access_log_bucket" {
  description = "Separate same-account, same-Region destination for S3 server access logs."
  type        = string
  validation {
    condition     = var.access_log_bucket != var.name
    error_message = "Use a separate access-log destination; never log a bucket into itself."
  }
}
variable "access_log_prefix" {
  description = "Prefix authorized by the destination policy, e.g. state/ or data/."
  type        = string
}
resource "aws_s3_bucket" "this" {
  #checkov:skip=CKV_AWS_145:SSE-S3 AES256 is intentional for temporary assessment state/data; IAM/TLS/versioning protect access. See docs/evidence/day2-terraform-validation.md finding S3-KMS.
  #checkov:skip=CKV_AWS_144:Single-Region assessment with versioning and retained state/data; regional disaster recovery is not claimed. See docs/evidence/day2-terraform-validation.md finding S3-CRR.
  #checkov:skip=CKV2_AWS_62:State locking and explicitly invoked ETL have no event consumer; notifications are not an audit control. See docs/evidence/day2-terraform-validation.md finding S3-EVENTS.
  bucket        = var.name
  force_destroy = false
  lifecycle { prevent_destroy = true }
}
resource "aws_s3_bucket_logging" "this" {
  bucket        = aws_s3_bucket.this.id
  target_bucket = var.access_log_bucket
  target_prefix = var.access_log_prefix
}
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule { object_ownership = "BucketOwnerEnforced" }
}
resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport", Effect = "Deny", Principal = "*", Action = "s3:*",
      Resource  = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"],
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.this]
}
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
  depends_on = [aws_s3_bucket_versioning.this]
}
output "id" {
  description = "Bucket name."
  value       = aws_s3_bucket.this.id
}
output "arn" {
  description = "Bucket ARN."
  value       = aws_s3_bucket.this.arn
}
