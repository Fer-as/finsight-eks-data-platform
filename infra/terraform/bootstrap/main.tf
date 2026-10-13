module "config" { source = "../modules/config" }
locals { config = module.config.value }
provider "aws" {
  region              = local.config.region
  allowed_account_ids = [local.config.account_id]
  default_tags { tags = module.config.tags }
}
module "state" {
  source            = "../modules/retained-bucket"
  name              = local.config.state_bucket
  access_log_bucket = module.access_logs.id
  access_log_prefix = "state/"
}
module "access_logs" {
  source         = "../modules/access-log-bucket"
  name           = local.config.access_log_bucket
  account_id     = local.config.account_id
  retention_days = local.config.storage.access_log_retention_days
  source_buckets = {
    state = local.config.state_bucket
    data  = local.config.data_bucket
  }
}
output "access_log_bucket" {
  description = "Retained audit-log destination for state and data buckets."
  value       = module.access_logs.id
}
output "state_bucket" {
  description = "Retained remote-state bucket; migrate local bootstrap state only after creation."
  value       = module.state.id
}
