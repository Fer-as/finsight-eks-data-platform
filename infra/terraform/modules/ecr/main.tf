variable "name" {
  description = "Project/environment resource prefix."
  type        = string
}
variable "repositories" {
  description = "Application image names below the project/environment prefix."
  type        = set(string)
}
variable "untagged_retention_days" {
  description = "Days before untagged images may be deleted. Tagged images are retained."
  type        = number
  validation {
    condition     = var.untagged_retention_days >= 1
    error_message = "Retention must be at least one day."
  }
}
resource "aws_ecr_repository" "this" {
  #checkov:skip=CKV_AWS_136:Explicit AES256 encrypts images at rest; scoped IAM and immutable tags retained. Independent KMS key control is not required for this assessment. See docs/evidence/day2-terraform-validation.md finding ECR-KMS.
  for_each             = var.repositories
  name                 = "${var.name}/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
  lifecycle { prevent_destroy = true }
}
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1, description = "Expire only untagged images",
      selection = {
        tagStatus = "untagged", countType = "sinceImagePushed",
        countUnit = "days", countNumber = var.untagged_retention_days
      },
      action = { type = "expire" }
    }]
  })
}
output "arns" {
  description = "Repository ARNs keyed by application."
  value       = { for k, v in aws_ecr_repository.this : k => v.arn }
}
output "urls" {
  description = "Repository URLs keyed by application."
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}
