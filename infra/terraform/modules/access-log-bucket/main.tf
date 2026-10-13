variable "name" {
  description = "Globally unique same-Region access-log destination bucket name."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.name))
    error_message = "Supply a valid unique lowercase access-log bucket name."
  }
}
variable "account_id" {
  description = "Only log delivery from this account is permitted."
  type        = string
}
variable "source_buckets" {
  description = "Map of delivery prefix (without slash) to exact source bucket name."
  type        = map(string)
  validation {
    condition = length(var.source_buckets) > 0 && alltrue([
      for prefix, bucket in var.source_buckets :
      can(regex("^[a-z][a-z0-9]*$", prefix)) && bucket != var.name
    ])
    error_message = "Use non-empty exact sources and simple prefixes; never log the destination to itself."
  }
}
variable "retention_days" {
  description = "Expiry for current log objects and noncurrent versions; each age is measured separately."
  type        = number
  validation {
    condition     = var.retention_days >= 90 && floor(var.retention_days) == var.retention_days
    error_message = "Retain audit logs for at least 90 whole days."
  }
}
resource "aws_s3_bucket" "this" {
  #checkov:skip=CKV_AWS_18:Dedicated S3 server-log destination must not log to itself or start recursive logging. AWS recommends destination logging remain disabled. See docs/evidence/day2-terraform-validation.md finding LOG-DESTINATION.
  #checkov:skip=CKV_AWS_145:Direct S3 server-access-log delivery requires an SSE-S3 destination, not SSE-KMS. See docs/evidence/day2-terraform-validation.md finding LOG-DESTINATION.
  #checkov:skip=CKV_AWS_144:Same-Region assessment audit archive; versioning and protected retention do not claim regional disaster recovery. See docs/evidence/day2-terraform-validation.md finding LOG-DESTINATION.
  #checkov:skip=CKV2_AWS_62:No event-driven consumer for access logs; no unused notification target or event service. See docs/evidence/day2-terraform-validation.md finding LOG-DESTINATION.
  bucket        = var.name
  force_destroy = false
  lifecycle { prevent_destroy = true }
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
    Version = "2012-10-17",
    Statement = concat([
      {
        Sid       = "DenyInsecureTransport", Effect = "Deny", Principal = "*", Action = "s3:*",
        Resource  = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"],
        Condition = { Bool = { "aws:SecureTransport" = "false", "aws:PrincipalIsAWSService" = "false" } }
      }
      ], [
      for prefix, bucket in var.source_buckets : {
        Sid       = "Allow${title(prefix)}LogDelivery", Effect = "Allow",
        Principal = { Service = "logging.s3.amazonaws.com" },
        Action    = "s3:PutObject", Resource = "${aws_s3_bucket.this.arn}/${prefix}/*",
        Condition = {
          ArnEquals    = { "aws:SourceArn" = "arn:aws:s3:::${bucket}" },
          StringEquals = { "aws:SourceAccount" = var.account_id }
        }
      }
    ])
  })
  depends_on = [aws_s3_bucket_public_access_block.this]
}
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    id     = "expire-access-logs"
    status = "Enabled"
    filter {}
    expiration { days = var.retention_days }
    noncurrent_version_expiration { noncurrent_days = var.retention_days }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
  rule {
    id     = "remove-expired-delete-markers"
    status = "Enabled"
    filter {}
    expiration { expired_object_delete_marker = true }
  }
  depends_on = [aws_s3_bucket_versioning.this]
}
output "id" {
  description = "Destination name, available to sources after delivery policy and security controls exist."
  value       = aws_s3_bucket.this.id
  depends_on = [
    aws_s3_bucket_policy.this, aws_s3_bucket_ownership_controls.this,
    aws_s3_bucket_server_side_encryption_configuration.this,
    aws_s3_bucket_versioning.this, aws_s3_bucket_lifecycle_configuration.this
  ]
}
