module "config" { source = "../../../modules/config" }
locals { config = module.config.value }
provider "aws" {
  region              = local.config.region
  allowed_account_ids = [local.config.account_id]
  default_tags { tags = module.config.tags }
}
module "data" {
  source            = "../../../modules/retained-bucket"
  name              = local.config.data_bucket
  access_log_bucket = local.config.access_log_bucket
  access_log_prefix = "data/"
}
module "images" {
  source                  = "../../../modules/ecr"
  name                    = module.config.name
  repositories            = local.config.storage.repositories
  untagged_retention_days = local.config.storage.untagged_image_retention_days
}
module "github" {
  source             = "../../../modules/github-oidc"
  name               = module.config.name
  account_id         = local.config.account_id
  region             = local.config.region
  config             = local.config.github
  state_bucket_arn   = "arn:aws:s3:::${local.config.state_bucket}"
  platform_state_key = "${local.config.environment}/platform/terraform.tfstate"
  repository_arns    = values(module.images.arns)
  zone_id            = local.config.dns.zone_id
}
# Issue #8: the workload permissions boundary every platform role must carry, and the
# approval-gated CI apply role's managed policies. See docs/infrastructure/terraform-ci.md.
module "ci_policies" {
  source               = "../../../modules/terraform-ci-policies"
  name                 = module.config.name
  account_id           = local.config.account_id
  region               = local.config.region
  state_bucket_arn     = "arn:aws:s3:::${local.config.state_bucket}"
  platform_state_key   = "${local.config.environment}/platform/terraform.tfstate"
  protected_state_keys = ["bootstrap/terraform.tfstate", "${local.config.environment}/foundation/terraform.tfstate"]
  data_bucket          = local.config.data_bucket
  zone_id              = local.config.dns.zone_id
  admin_role_arns      = local.config.eks.admin_role_arns
}
resource "aws_iam_policy" "workload_boundary" {
  name        = module.ci_policies.boundary_name
  description = "Permissions boundary for every IAM role the FinSight platform root creates."
  policy      = module.ci_policies.boundary_policy
}
resource "aws_iam_policy" "ci_apply" {
  for_each    = module.ci_policies.apply_policies
  name        = "${module.config.name}-github-infra-apply-${each.key}"
  description = "Approval-gated CI apply role for the FinSight platform root (${each.key})."
  policy      = each.value
}
resource "aws_iam_role_policy_attachment" "ci_apply" {
  for_each   = aws_iam_policy.ci_apply
  role       = element(split("/", module.github.role_arns["infra_apply"]), 1)
  policy_arn = each.value.arn
}
output "workload_boundary_arn" {
  description = "Permissions boundary the platform root sets on every role it creates."
  value       = aws_iam_policy.workload_boundary.arn
}
output "data_bucket" {
  description = "Retained bucket; raw/ and curated/ are IAM-scoped object prefixes."
  value       = module.data.id
}
output "repository_urls" {
  description = "Image destinations."
  value       = module.images.urls
}
output "github_role_arns" {
  description = "Plan-only and image publisher roles for later workflows."
  value       = module.github.role_arns
}
