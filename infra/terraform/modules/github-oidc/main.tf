variable "name" {
  description = "Project/environment prefix."
  type        = string
}
variable "account_id" {
  description = "Expected AWS account ID."
  type        = string
}
variable "region" {
  description = "Region for platform resource ARNs."
  type        = string
}
variable "config" {
  description = "Explicit provider ownership and exact repository OIDC subject prefix/environments."
  type = object({
    create_provider   = bool, existing_provider_arn = string, subject_prefix = string,
    infra_environment = string, images_environment = string, apply_environment = string
  })
  validation {
    condition = (
      startswith(var.config.subject_prefix, "repo:") &&
      length(split("/", var.config.subject_prefix)) == 2 &&
      length(regexall("[*?]", var.config.subject_prefix)) == 0 &&
      !strcontains(trimprefix(var.config.subject_prefix, "repo:"), ":") &&
      length(regexall("[*?:]", var.config.infra_environment)) == 0 &&
      length(regexall("[*?:]", var.config.images_environment)) == 0 &&
      length(regexall("[*?:]", var.config.apply_environment)) == 0 &&
      length(var.config.infra_environment) > 0 && length(var.config.images_environment) > 0 &&
      length(var.config.apply_environment) > 0 &&
      length(distinct([var.config.infra_environment, var.config.images_environment, var.config.apply_environment])) == 3
    )
    error_message = "Supply an exact repository subject prefix (no wildcard/ref/environment suffix) and three distinct named GitHub environments."
  }
  validation {
    condition = (
      (var.config.create_provider && var.config.existing_provider_arn == "") ||
      (!var.config.create_provider && can(regex("^arn:aws:iam::[0-9]{12}:oidc-provider/token.actions.githubusercontent.com$", var.config.existing_provider_arn)))
    )
    error_message = "Explicitly choose one: create a GitHub provider, or reference the existing provider ARN."
  }
}
variable "state_bucket_arn" {
  description = "Retained state bucket ARN."
  type        = string
}
variable "platform_state_key" {
  description = "Only this platform state object is readable by CI."
  type        = string
}
variable "repository_arns" {
  description = "Only these ECR repositories are writable by the image role."
  type        = list(string)
}
locals {
  provider_arn = var.config.create_provider ? aws_iam_openid_connect_provider.github[0].arn : var.config.existing_provider_arn
  subjects = {
    infra_plan  = "${var.config.subject_prefix}:environment:${var.config.infra_environment}"
    images      = "${var.config.subject_prefix}:environment:${var.config.images_environment}"
    infra_apply = "${var.config.subject_prefix}:environment:${var.config.apply_environment}"
  }
}
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.config.create_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS uses trusted root CAs for GitHub. Do not pin an obsolete leaf thumbprint.
}
resource "aws_iam_role" "this" {
  for_each             = local.subjects
  name                 = "${var.name}-github-${replace(each.key, "_", "-")}"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow", Principal = { Federated = local.provider_arn }, Action = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub" = each.value
        }
      }
    }]
  })
}
resource "aws_iam_role_policy" "images" {
  name = "publish-application-images"
  role = aws_iam_role.this["images"].id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      {
        Effect = "Allow", Resource = var.repository_arns,
        Action = ["ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
        "ecr:DescribeImages", "ecr:DescribeImageScanFindings"]
      }
    ]
  })
}
resource "aws_iam_role_policy" "infra_plan" {
  name = "read-platform-for-plan"
  role = aws_iam_role.this["infra_plan"].id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow", Action = ["s3:ListBucket"], Resource = var.state_bucket_arn,
        Condition = { StringLike = { "s3:prefix" = [var.platform_state_key, "${var.platform_state_key}.tflock"] } }
      },
      { Effect = "Allow", Action = ["s3:GetObject"], Resource = "${var.state_bucket_arn}/${var.platform_state_key}" },
      {
        Effect   = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
        Resource = "${var.state_bucket_arn}/${var.platform_state_key}.tflock"
      },
      {
        Effect   = "Allow",
        Action   = ["ec2:Describe*", "autoscaling:DescribeAutoScalingGroups", "eks:DescribeAddonVersions", "eks:DescribeClusterVersions"],
        Resource = "*", Condition = { StringEquals = { "aws:RequestedRegion" = var.region } }
      },
      {
        Effect = "Allow", Action = ["eks:Describe*", "eks:List*"],
        Resource = [
          "arn:aws:eks:${var.region}:${var.account_id}:cluster/${var.name}",
          "arn:aws:eks:${var.region}:${var.account_id}:nodegroup/${var.name}/*",
          "arn:aws:eks:${var.region}:${var.account_id}:addon/${var.name}/*",
          "arn:aws:eks:${var.region}:${var.account_id}:access-entry/${var.name}/*",
          "arn:aws:eks:${var.region}:${var.account_id}:podidentityassociation/${var.name}/*"
        ]
      },
      {
        Effect   = "Allow",
        Action   = ["iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole"],
        Resource = "arn:aws:iam::${var.account_id}:role/${var.name}-*"
      },
      {
        Effect    = "Allow", Action = ["logs:DescribeLogGroups"], Resource = "*",
        Condition = { StringEquals = { "aws:RequestedRegion" = var.region } }
      },
      {
        Effect = "Allow", Action = ["logs:ListTagsForResource"],
        Resource = ["arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/eks/${var.name}/cluster",
        "arn:aws:logs:${var.region}:${var.account_id}:log-group:/finsight/${var.name}/vpc-flow"]
      },
      { Effect = "Allow", Action = ["route53:GetHostedZone", "route53:ListTagsForResource"], Resource = "arn:aws:route53:::hostedzone/${var.zone_id}" }
    ]
  })
}
# Apply role for the platform root only, assumable only by jobs that run in the protected apply
# environment (required reviewers, main only; configured in GitHub). This policy grants the
# platform state object and its lock only; the scoped permissions to change platform resources are
# the managed policies the foundation root attaches (modules/terraform-ci-policies, issue #8). It has
# no access to bootstrap or foundation state, so CI can never modify the GitHub roles, OIDC trust or
# state buckets that govern it.
resource "aws_iam_role_policy" "infra_apply_state" {
  name = "platform-state-only"
  role = aws_iam_role.this["infra_apply"].id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "ListPlatformStateKeys", Effect = "Allow", Action = ["s3:ListBucket"], Resource = var.state_bucket_arn,
        Condition = { StringLike = { "s3:prefix" = [var.platform_state_key, "${var.platform_state_key}.tflock"] } }
      },
      {
        Sid      = "ReadWritePlatformState", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"],
        Resource = "${var.state_bucket_arn}/${var.platform_state_key}"
      },
      {
        Sid      = "PlatformStateLock", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
        Resource = "${var.state_bucket_arn}/${var.platform_state_key}.tflock"
      }
    ]
  })
}
variable "zone_id" {
  description = "Existing hosted zone ID; plan role can read only this zone."
  type        = string
  validation {
    condition     = can(regex("^Z[A-Z0-9]+$", var.zone_id))
    error_message = "Supply the existing hosted zone ID without the /hostedzone/ prefix."
  }
}
output "role_arns" {
  description = "Separate plan-only, ECR publisher and approval-gated platform apply role ARNs."
  value       = { for k, v in aws_iam_role.this : k => v.arn }
}
