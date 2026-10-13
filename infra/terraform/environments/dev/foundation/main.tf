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
