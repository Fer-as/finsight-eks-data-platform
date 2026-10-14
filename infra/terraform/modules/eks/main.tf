variable "name" {
  description = "EKS cluster and role prefix."
  type        = string
}
variable "subnet_ids" {
  description = "Two private worker/control-plane subnet IDs."
  type        = list(string)
}
variable "tags" {
  description = "Common tags propagated to EC2 instances and root EBS volumes."
  type        = map(string)
  default     = {}
}
variable "config" {
  description = "Cluster version, verified add-on pins, access restrictions and managed node sizing."
  type = object({
    version                = string, public_access_cidrs = list(string), admin_role_arns = set(string),
    instance_types         = list(string), min_size = number, desired_size = number, max_size = number,
    disk_size_gb           = number, ami_release_version = optional(string), log_retention_days = number,
    compatibility_verified = bool, addon_versions = map(string)
  })
  validation {
    condition     = var.config.version == "1.36"
    error_message = "This approved environment targets Kubernetes 1.36."
  }
  validation {
    condition = length(var.config.public_access_cidrs) > 0 && alltrue([
      for cidr in var.config.public_access_cidrs :
      can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) >= 24, false)
    ])
    error_message = "Provide explicit IPv4 public access CIDRs, /24 or narrower; /32 is recommended."
  }
  validation {
    condition = length(var.config.admin_role_arns) > 0 && alltrue([
      for arn in var.config.admin_role_arns : can(regex("^arn:aws:iam::[0-9]{12}:role/.+", arn))
    ])
    error_message = "Provide at least one existing administrator IAM role, not an STS session or root ARN."
  }
  validation {
    condition = (
      var.config.min_size >= 1 && var.config.min_size <= var.config.desired_size &&
      var.config.desired_size <= var.config.max_size && var.config.disk_size_gb >= 20 &&
      alltrue([for n in [var.config.min_size, var.config.desired_size, var.config.max_size, var.config.disk_size_gb] : floor(n) == n])
    )
    error_message = "Use whole numbers with 1 <= minimum <= desired <= maximum and disks >= 20 GB."
  }
  validation {
    condition = var.config.compatibility_verified && alltrue([
      for addon in ["vpc-cni", "kube-proxy", "coredns", "eks-pod-identity-agent", "aws-ebs-csi-driver"] :
      can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", var.config.addon_versions[addon]))
    ])
    error_message = "Complete the approved regional compatibility checks, pin all five add-ons, then explicitly set compatibility_verified."
  }
}
locals {
  bootstrap_addons = toset(["vpc-cni", "kube-proxy"])
}
resource "aws_iam_role" "cluster" {
  name = "${var.name}-cluster"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{
      Effect = "Allow", Principal = { Service = "eks.amazonaws.com" }, Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
resource "aws_cloudwatch_log_group" "cluster" {
  #checkov:skip=CKV_AWS_158:CloudWatch default AES-GCM encryption is retained for seven-day assessment logs; no independent key-control requirement. See docs/evidence/day2-terraform-validation.md finding LOGS-KMS.
  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = var.config.log_retention_days
}
resource "aws_eks_cluster" "this" {
  #checkov:skip=CKV_AWS_39:Approved private plus CIDR-restricted public API, explicit admin roles and audit logs; no unrestricted CIDRs. See docs/evidence/day2-terraform-validation.md finding EKS-ENDPOINT.
  #checkov:skip=CKV_AWS_58:Version is constrained to 1.36; AWS documents default KMS v2 envelope encryption with an AWS-owned key for EKS >=1.28. See docs/evidence/day2-terraform-validation.md finding EKS-SECRETS.
  name                          = var.name
  role_arn                      = aws_iam_role.cluster.arn
  version                       = var.config.version
  bootstrap_self_managed_addons = false
  enabled_cluster_log_types     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }
  upgrade_policy { support_type = "STANDARD" }
  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.config.public_access_cidrs
  }
  # Kubernetes >= 1.28 has AWS-owned-key envelope encryption by default.
  depends_on = [aws_iam_role_policy_attachment.cluster, aws_cloudwatch_log_group.cluster]
}
resource "aws_eks_access_entry" "admin" {
  for_each      = var.config.admin_role_arns
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"
}
resource "aws_eks_access_policy_association" "admin" {
  for_each      = aws_eks_access_entry.admin
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
}
module "cni_role" {
  source          = "../pod-role"
  name            = "${var.name}-vpc-cni"
  cluster_arn     = aws_eks_cluster.this.arn
  namespace       = "kube-system"
  service_account = "aws-node"
  policy_arns     = ["arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"]
}
module "ebs_role" {
  source          = "../pod-role"
  name            = "${var.name}-ebs-csi"
  cluster_arn     = aws_eks_cluster.this.arn
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  policy_arns     = ["arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2"]
}
resource "aws_eks_addon" "identity_agent" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "eks-pod-identity-agent"
  addon_version               = var.config.addon_versions["eks-pod-identity-agent"]
  resolve_conflicts_on_create = "NONE"
  resolve_conflicts_on_update = "NONE"
}
resource "aws_eks_addon" "bootstrap" {
  for_each                    = local.bootstrap_addons
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.value
  addon_version               = var.config.addon_versions[each.value]
  resolve_conflicts_on_create = "NONE"
  resolve_conflicts_on_update = "NONE"
  depends_on                  = [aws_eks_addon.identity_agent]
  dynamic "pod_identity_association" {
    for_each = each.value == "vpc-cni" ? [1] : []
    content {
      role_arn        = module.cni_role.arn
      service_account = "aws-node"
    }
  }
}
resource "aws_iam_role" "node" {
  name = "${var.name}-node"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{
      Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}
resource "aws_launch_template" "node" {
  name_prefix            = "${var.name}-"
  update_default_version = true
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = var.config.disk_size_gb
      encrypted             = true
      delete_on_termination = true
    }
  }
  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.name}-worker" })
  }
  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags, { Name = "${var.name}-worker-root" })
  }
}
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name}-workers"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids
  instance_types  = var.config.instance_types
  capacity_type   = "ON_DEMAND"
  ami_type        = "AL2023_x86_64_STANDARD"
  version         = var.config.version
  release_version = var.config.ami_release_version
  scaling_config {
    min_size     = var.config.min_size
    desired_size = var.config.desired_size
    max_size     = var.config.max_size
  }
  update_config { max_unavailable = 1 }
  launch_template {
    id      = aws_launch_template.node.id
    version = tostring(aws_launch_template.node.latest_version)
  }
  depends_on = [aws_eks_addon.bootstrap, aws_iam_role_policy_attachment.node]
}
resource "aws_eks_addon" "workload" {
  for_each                    = toset(["coredns", "aws-ebs-csi-driver"])
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.value
  addon_version               = var.config.addon_versions[each.value]
  resolve_conflicts_on_create = "NONE"
  resolve_conflicts_on_update = "NONE"
  dynamic "pod_identity_association" {
    for_each = each.value == "aws-ebs-csi-driver" ? [1] : []
    content {
      role_arn        = module.ebs_role.arn
      service_account = "ebs-csi-controller-sa"
    }
  }
  depends_on = [aws_eks_node_group.this]
}
output "name" {
  description = "Cluster name."
  value       = aws_eks_cluster.this.name
}
output "arn" {
  description = "Cluster ARN."
  value       = aws_eks_cluster.this.arn
}
output "endpoint" {
  description = "API endpoint; network restrictions still apply."
  value       = aws_eks_cluster.this.endpoint
}
output "node_group_name" {
  description = "Managed node group name."
  value       = aws_eks_node_group.this.node_group_name
}
output "cluster_security_group_id" {
  description = "EKS-created cluster security group, shared by the control plane ENIs, managed nodes and pods."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}
output "addon_versions" {
  description = "Explicitly configured add-on pins."
  value       = var.config.addon_versions
}
