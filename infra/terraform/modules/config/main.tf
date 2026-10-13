variable "override_file" {
  description = "Optional absolute JSON override path; default is the ignored central local.json."
  type        = string
  default     = null
}
locals {
  defaults      = jsondecode(file("${path.module}/../../config/defaults.json"))
  override_file = coalesce(var.override_file, "${path.module}/../../config/local.json")
  overrides     = jsondecode(fileexists(local.override_file) ? file(local.override_file) : "{}")
  # Merge one level within named sections; lists and deeper objects replace as a unit.
  config = merge(local.defaults, local.overrides, {
    for section in ["tags", "network", "eks", "dns", "github", "storage"] :
    section => merge(local.defaults[section], try(local.overrides[section], {}))
  })
}
output "value" {
  description = "Central configuration, with section-level overrides applied."
  value       = local.config
  precondition {
    condition     = can(regex("^[0-9]{12}$", local.config.account_id)) && local.config.account_id != "000000000000"
    error_message = "Set the intended account ID in ignored config/local.json before planning."
  }
  precondition {
    condition     = local.config.region == "eu-west-2" && can(regex("^[a-z][a-z0-9-]{1,19}$", local.config.project)) && can(regex("^[a-z][a-z0-9-]{1,9}$", local.config.environment))
    error_message = "This environment requires London and short lowercase project/environment names."
  }
  precondition {
    condition     = length(distinct([local.config.state_bucket, local.config.data_bucket, local.config.access_log_bucket])) == 3
    error_message = "State, financial data and access logs must use three different buckets."
  }
}
output "name" {
  description = "Stable resource prefix."
  value       = "${local.config.project}-${local.config.environment}"
}
output "tags" {
  description = "Common ownership tags. Reserved keys cannot be overridden."
  value = merge(local.config.tags, {
    Project = local.config.project, Environment = local.config.environment, ManagedBy = "Terraform"
  })
}
