module "config" { source = "../../../modules/config" }
locals {
  config   =   module.config.value
  # Created by the foundation root (issue #8); every platform role must carry it.
  permissions_boundary = "arn:aws:iam::${local.config.account_id}:policy/${module.config.name}-workload-boundary"
}
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
  source               = "../../../modules/network"
  name                 = module.config.name
  region               = local.config.region
  config               = local.config.network
  permissions_boundary = local.permissions_boundary
}
module "eks" {
  source               = "../../../modules/eks"
  name                 = module.config.name
  subnet_ids           = module.network.private_subnet_ids
  config               = local.config.eks
  permissions_boundary = local.permissions_boundary
  tags                 = module.config.tags
  # Ensure private NAT/S3 routes and flow logging exist before workers bootstrap.
  depends_on = [module.network]
}
# The only inbound path from outside the cluster security group: the public NLB's group may
# reach the ingress controller pods' traffic and health-check ports (IP target mode).
# See docs/infrastructure/network-security.md.
resource "aws_vpc_security_group_ingress_rule" "nlb_to_ingress_pods" {
  for_each                     = { for p in module.network.ingress_target_ports : tostring(p) => p }
  security_group_id            = module.eks.cluster_security_group_id
  referenced_security_group_id = module.network.public_ingress_security_group_id
  description                  = "Public NLB to ingress controller pods (traffic and health checks)"
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
}
# AWS Load Balancer Controller: provisions the public NLB for F5 NGINX. Upstream v3.6.0 policy,
# narrowed to this account, Region, VPC and k8s-* NLBs. See docs/infrastructure/load-balancer-controller.md.
module "load_balancer_controller_policy" {
  source       = "../../../modules/load-balancer-controller-policy"
  region       = local.config.region
  account_id   = local.config.account_id
  vpc_id       = module.network.vpc_id
  cluster_name = module.config.name # the EKS cluster name; the Helm clusterName must match
}
module "load_balancer_controller_role" {
  source               = "../../../modules/pod-role"
  permissions_boundary = local.permissions_boundary
  name                 = "${module.config.name}-aws-load-balancer-controller"
  cluster_arn          = module.eks.arn
  namespace            = "kube-system"
  service_account      = "aws-load-balancer-controller"
  inline_policy        = module.load_balancer_controller_policy.policy
}
resource "aws_eks_pod_identity_association" "load_balancer_controller" {
  cluster_name    = module.eks.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = module.load_balancer_controller_role.arn
}
module "etl_role" {
  source               = "../../../modules/pod-role"
  permissions_boundary = local.permissions_boundary
  name                 = "${module.config.name}-etl"
  cluster_arn          = module.eks.arn
  namespace            = "finsight"
  service_account      = "finsight-etl"
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
# Separate DNS identities: ExternalDNS owns the application records, cert-manager only the
# DNS-01 challenge record. See docs/infrastructure/dns-and-certificates.md.
module "dns_policies" {
  source   = "../../../modules/dns-policies"
  zone_id  = data.aws_route53_zone.existing.zone_id
  hostname = local.config.dns.application_hostname
}
module "external_dns_role" {
  source               = "../../../modules/pod-role"
  permissions_boundary = local.permissions_boundary
  name                 = "${module.config.name}-external-dns"
  cluster_arn          = module.eks.arn
  namespace            = "external-dns"
  service_account      = "external-dns"
  inline_policy        = module.dns_policies.external_dns
}
resource "aws_eks_pod_identity_association" "external_dns" {
  cluster_name    = module.eks.name
  namespace       = "external-dns"
  service_account = "external-dns"
  role_arn        = module.external_dns_role.arn
}
module "cert_manager_role" {
  source               = "../../../modules/pod-role"
  permissions_boundary = local.permissions_boundary
  name                 = "${module.config.name}-cert-manager"
  cluster_arn          = module.eks.arn
  namespace            = "cert-manager"
  service_account      = "cert-manager"
  inline_policy        = module.dns_policies.cert_manager
}
resource "aws_eks_pod_identity_association" "cert_manager" {
  cluster_name    = module.eks.name
  namespace       = "cert-manager"
  service_account = "cert-manager"
  role_arn        = module.cert_manager_role.arn
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
    vpc_id                           = module.network.vpc_id, private_subnet_ids = module.network.private_subnet_ids,
    public_subnet_ids                = module.network.public_subnet_ids, nat_gateway_id = module.network.nat_gateway_id,
    public_ingress_security_group_id = module.network.public_ingress_security_group_id,
    cluster_security_group_id        = module.eks.cluster_security_group_id
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
output "load_balancer_controller" {
  description = "Values for the later AWS Load Balancer Controller Helm install (pods cannot read instance metadata)."
  value = {
    role_arn        = module.load_balancer_controller_role.arn
    namespace       = "kube-system"
    service_account = "aws-load-balancer-controller"
    cluster_name    = module.eks.name
    region          = local.config.region
    vpc_id          = module.network.vpc_id
    policy_source   = module.load_balancer_controller_policy.source
  }
}
output "dns_identity" {
  description = "Pod Identity roles and record scope for the later ExternalDNS and cert-manager installs."
  value = {
    external_dns_role_arn     = module.external_dns_role.arn
    external_dns_record_names = module.dns_policies.external_dns_record_names
    cert_manager_role_arn     = module.cert_manager_role.arn
    acme_challenge_record     = module.dns_policies.acme_challenge_record
  }
}
