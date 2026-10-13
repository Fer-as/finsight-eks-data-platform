module "config" { source = "../../../modules/config" }
locals { config = module.config.value }
provider "aws" {
  region              = local.config.region
  allowed_account_ids = [local.config.account_id]
  default_tags { tags = module.config.tags }
}
data "aws_route53_zone" "existing" {
  zone_id = local.config.dns.zone_id
  lifecycle {
    postcondition {
      condition = (
        !self.private_zone &&
        trimsuffix(self.name, ".") == trimsuffix(local.config.dns.zone_name, ".") &&
        contains(["eks.${trimsuffix(self.name, ".")}", "eks.labs.${trimsuffix(self.name, ".")}"], local.config.dns.application_hostname)
      )
      error_message = "Use the intended existing PUBLIC hosted zone and eks.<zone> or eks.labs.<zone>."
    }
  }
}
module "network" {
  source = "../../../modules/network"
  name   = module.config.name
  region = local.config.region
  config = local.config.network
}
module "eks" {
  source     = "../../../modules/eks"
  name       = module.config.name
  subnet_ids = module.network.private_subnet_ids
  config     = local.config.eks
  tags       = module.config.tags
  # Ensure private NAT/S3 routes and flow logging exist before workers bootstrap.
  depends_on = [module.network]
}
module "etl_role" {
  source          = "../../../modules/pod-role"
  name            = "${module.config.name}-etl"
  cluster_arn     = module.eks.arn
  namespace       = "finsight"
  service_account = "finsight-etl"
  inline_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow", Action = ["s3:ListBucket"], Resource = "arn:aws:s3:::${local.config.data_bucket}",
        Condition = { StringLike = { "s3:prefix" = ["raw/*", "curated/*"] } }
      },
      {
        Effect   = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"],
        Resource = ["arn:aws:s3:::${local.config.data_bucket}/raw/*", "arn:aws:s3:::${local.config.data_bucket}/curated/*"]
      }
    ]
  })
}
resource "aws_eks_pod_identity_association" "etl" {
  cluster_name    = module.eks.name
  namespace       = "finsight"
  service_account = "finsight-etl"
  role_arn        = module.etl_role.arn
}
output "cluster_name" {
  description = "Cluster name for later kubeconfig setup."
  value       = module.eks.name
}
output "cluster_endpoint" {
  description = "Restricted public/private EKS API endpoint."
  value       = module.eks.endpoint
}
output "node_group_name" {
  description = "Managed node group to verify after provisioning."
  value       = module.eks.node_group_name
}
output "network" {
  description = "IDs for later verification and teardown inventory."
  value = {
    vpc_id            = module.network.vpc_id, private_subnet_ids = module.network.private_subnet_ids,
    public_subnet_ids = module.network.public_subnet_ids, nat_gateway_id = module.network.nat_gateway_id
  }
}
output "application_hostname" {
  description = "Planned HTTPS hostname; no DNS record is created."
  value       = local.config.dns.application_hostname
}
output "etl_role_arn" {
  description = "Reserved for the later finsight/finsight-etl service account; no Kubernetes object is created."
  value       = module.etl_role.arn
}
