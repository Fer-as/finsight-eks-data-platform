# Provider-free builder for the FinSight workload permissions boundary and the CI apply role's
# policies (issue #8, Option A). Foundation creates them as managed policies; the platform root
# attaches the boundary to every role it creates. See docs/infrastructure/terraform-ci.md.
variable "name" {
  description = "Project-environment prefix, e.g. finsight-dev; also the EKS cluster name."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.name))
    error_message = "Use a short lowercase prefix."
  }
}
variable "account_id" {
  description = "AWS account ID."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Supply a 12-digit account ID."
  }
}
variable "region" {
  description = "The only Region the apply role and bounded roles may act in."
  type        = string
}
variable "project_tag" {
  description = "Value of the Project tag the platform provider applies to every taggable resource."
  type        = string
  default     = "finsight"
}
variable "state_bucket_arn" {
  description = "Terraform state bucket ARN."
  type        = string
}
variable "platform_state_key" {
  description = "The only state object the apply role may read and write."
  type        = string
}
variable "protected_state_keys" {
  description = "Bootstrap and foundation state keys; the apply role is explicitly denied all access to them."
  type        = list(string)
}
variable "data_bucket" {
  description = "Data bucket name; bounded workload roles may reach only its raw/ and curated/ objects."
  type        = string
}
variable "zone_id" {
  description = "Existing hosted zone ID."
  type        = string
}
variable "admin_role_arns" {
  description = "The only principals the apply role may grant EKS access entries to."
  type        = list(string)
}
variable "platform_roles" {
  description = "Name suffixes of the IAM roles the platform root creates (<name>-<suffix>); the apply role may manage and pass only these."
  type        = list(string)
  default     = ["cluster", "node", "flow-logs", "vpc-cni", "ebs-csi", "aws-load-balancer-controller", "etl", "external-dns", "cert-manager"]
  validation {
    condition     = alltrue([for r in var.platform_roles : can(regex("^[a-z0-9-]+$", r)) && !startswith(r, "github-") && r != "eks-admin"])
    error_message = "Use exact lowercase suffixes; GitHub and administrator roles can never be platform roles."
  }
}
locals {
  iam = "arn:aws:iam::${var.account_id}"
  # Exact names, not <name>-*: TagRole cannot be limited to creation, so a prefix would let the role
  # tag and then change the trust of any other role that happens to share the prefix.
  role   = [for r in var.platform_roles : "${local.iam}:role/${var.name}-${r}"]
  eks    = "arn:aws:eks:${var.region}:${var.account_id}"
  logs   = "arn:aws:logs:${var.region}:${var.account_id}:log-group"
  region = { StringEquals = { "aws:RequestedRegion" = var.region } }

  boundary_name = "${var.name}-workload-boundary"
  boundary_arn  = "${local.iam}:policy/${local.boundary_name}"
  # Roles the apply role must never create, change, pass or delete, although they match the prefix.
  protected_roles = ["${local.iam}:role/${var.name}-github-*", "${local.iam}:role/${var.name}-eks-admin"]
  managed_policies = [
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2",
  ]
  service_linked = ["eks.amazonaws.com", "eks-nodegroup.amazonaws.com", "autoscaling.amazonaws.com", "elasticloadbalancing.amazonaws.com"]

  # Ceiling for every role the platform creates (cluster, node, flow logs, Pod Identity roles).
  # Effective permissions are the intersection of this and each role's own policies.
  boundary = {
    Version = "2012-10-17"
    Statement = [
      { Sid = "RegionalInfrastructure", Effect = "Allow", Action = ["ec2:*", "elasticloadbalancing:*", "autoscaling:*"], Resource = "*", Condition = local.region },
      { Sid = "NodeAndPodIdentity", Effect = "Allow", Action = ["eks:DescribeCluster", "eks-auth:AssumeRoleForPodIdentity"], Resource = "*" },
      { Sid = "ImagePull", Effect = "Allow", Action = ["ecr:GetAuthorizationToken", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchImportUpstreamImage"], Resource = "*" },
      { Sid = "FlowLogs", Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams", "logs:DescribeLogGroups"], Resource = "*", Condition = local.region },
      { Sid = "Dns", Effect = "Allow", Action = ["route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets", "route53:GetHostedZone"], Resource = "arn:aws:route53:::hostedzone/${var.zone_id}" },
      { Sid = "DnsDiscovery", Effect = "Allow", Action = ["route53:ListHostedZones", "route53:GetChange"], Resource = "*" },
      { Sid = "EtlBucketList", Effect = "Allow", Action = ["s3:ListBucket"], Resource = "arn:aws:s3:::${var.data_bucket}" },
      { Sid = "EtlObjects", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"], Resource = ["arn:aws:s3:::${var.data_bucket}/raw/*", "arn:aws:s3:::${var.data_bucket}/curated/*"] },
      { Sid = "LoadBalancerFeatureReads", Effect = "Allow", Action = ["acm:ListCertificates", "acm:DescribeCertificate", "cognito-idp:DescribeUserPoolClient", "waf-regional:GetWebACL", "waf-regional:GetWebACLForResource", "wafv2:GetWebACL", "wafv2:GetWebACLForResource", "shield:GetSubscriptionState", "shield:DescribeProtection", "iam:ListServerCertificates", "iam:GetServerCertificate"], Resource = "*" },
      { Sid = "ServiceLinkedRoles", Effect = "Allow", Action = ["iam:CreateServiceLinkedRole"], Resource = "*", Condition = { StringEquals = { "iam:AWSServiceName" = local.service_linked } } },
      { Sid = "EbsEncryptionViaEc2", Effect = "Allow", Action = ["kms:CreateGrant", "kms:Decrypt", "kms:GenerateDataKeyWithoutPlaintext", "kms:ReEncryptFrom", "kms:ReEncryptTo"], Resource = "*", Condition = { StringEquals = { "kms:ViaService" = "ec2.${var.region}.amazonaws.com" } } },
      { Sid = "KeyMetadata", Effect = "Allow", Action = ["kms:DescribeKey"], Resource = "*" },
    ]
  }

  # Explicit denies attached to the apply role (they win over any allow).
  guardrails = {
    Version = "2012-10-17"
    Statement = [
      { Sid = "NeverRemoveBoundaries", Effect = "Deny", Action = ["iam:DeleteRolePermissionsBoundary", "iam:DeleteUserPermissionsBoundary"], Resource = "*" },
      { Sid = "NoPolicyAuthoring", Effect = "Deny", Action = ["iam:CreatePolicy", "iam:CreatePolicyVersion", "iam:DeletePolicy", "iam:DeletePolicyVersion", "iam:SetDefaultPolicyVersion", "iam:TagPolicy", "iam:UntagPolicy"], Resource = "*" },
      { Sid = "ProtectGovernanceRoles", Effect = "Deny", Action = ["iam:*"], Resource = local.protected_roles },
      { Sid = "ProtectOidcProviders", Effect = "Deny", Action = ["iam:*OpenIDConnectProvider*", "iam:*SAMLProvider*"], Resource = "*" },
      { Sid = "NoPrincipalsOrKeys", Effect = "Deny", Action = ["iam:CreateUser", "iam:CreateGroup", "iam:CreateAccessKey", "iam:CreateLoginProfile", "iam:CreateInstanceProfile", "iam:AddRoleToInstanceProfile", "iam:AttachUserPolicy", "iam:PutUserPolicy", "iam:AttachGroupPolicy", "iam:PutGroupPolicy"], Resource = "*" },
      { Sid = "NoRoleChaining", Effect = "Deny", Action = ["sts:AssumeRole", "sts:AssumeRoleWithWebIdentity", "sts:AssumeRoleWithSAML", "sts:GetFederationToken"], Resource = "*" },
      { Sid = "ProtectOtherStates", Effect = "Deny", Action = ["s3:*"], Resource = [for k in var.protected_state_keys : "${var.state_bucket_arn}/${k}*"] },
      { Sid = "NoResourcePolicies", Effect = "Deny", Action = ["s3:PutBucketPolicy", "s3:DeleteBucketPolicy", "s3:PutBucketAcl", "s3:PutObjectAcl", "ecr:SetRepositoryPolicy", "kms:PutKeyPolicy", "kms:CreateGrant", "logs:PutResourcePolicy", "lambda:AddPermission", "sns:SetTopicAttributes", "sqs:SetQueueAttributes"], Resource = "*" },
      { Sid = "ClusterAccessOnlyForAdminRoles", Effect = "Deny", Action = ["eks:CreateAccessEntry", "eks:AssociateAccessPolicy", "eks:UpdateAccessEntry"], Resource = "*", Condition = { ArnNotEquals = { "eks:principalArn" = var.admin_role_arns } } },
    ]
  }

  # The platform's IAM roles: exact names, mandatory boundary, approved managed policies only.
  apply_roles = {
    Version = "2012-10-17"
    Statement = [
      { Sid = "BoundedRoleManagement", Effect = "Allow", Action = ["iam:CreateRole", "iam:PutRolePermissionsBoundary", "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy"], Resource = local.role, Condition = { StringEquals = { "iam:PermissionsBoundary" = local.boundary_arn } } },
      # Not documented to carry iam:PermissionsBoundary, so limited to the exact platform role names and
      # their ownership tag instead; protected roles stay denied by the guardrails.
      { Sid = "UpdateOwnedRoles", Effect = "Allow", Action = ["iam:UpdateAssumeRolePolicy", "iam:UpdateRole", "iam:UpdateRoleDescription", "iam:TagRole", "iam:UntagRole", "iam:DeleteRole"], Resource = local.role, Condition = { StringEquals = { "aws:ResourceTag/Project" = var.project_tag } } },
      { Sid = "OnlyApprovedManagedPolicies", Effect = "Deny", Action = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"], Resource = "*", Condition = { ArnNotEquals = { "iam:PolicyARN" = local.managed_policies } } },
      { Sid = "TagRolesOnCreate", Effect = "Allow", Action = ["iam:TagRole"], Resource = local.role, Condition = { StringEquals = { "aws:RequestTag/Project" = var.project_tag } } },
      { Sid = "KeepOwnershipTags", Effect = "Deny", Action = ["iam:UntagRole", "ec2:DeleteTags", "eks:UntagResource", "logs:UntagResource"], Resource = "*", Condition = { "ForAnyValue:StringEquals" = { "aws:TagKeys" = ["Project"] } } },
      { Sid = "PassBoundedRolesToServices", Effect = "Allow", Action = ["iam:PassRole"], Resource = local.role, Condition = { StringEquals = { "iam:PassedToService" = ["eks.amazonaws.com", "pods.eks.amazonaws.com", "vpc-flow-logs.amazonaws.com"] } } },
      { Sid = "ServiceLinkedRoles", Effect = "Allow", Action = ["iam:CreateServiceLinkedRole"], Resource = "*", Condition = { StringEquals = { "iam:AWSServiceName" = local.service_linked } } },
      { Sid = "IamReads", Effect = "Allow", Action = ["iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole", "iam:ListRoleTags", "iam:GetPolicy", "iam:GetPolicyVersion"], Resource = "*" },
    ]
  }

  # State, EKS, logs and DNS reads for the platform root.
  apply_identity = {
    Version = "2012-10-17"
    Statement = [
      { Sid = "PlatformStateList", Effect = "Allow", Action = ["s3:ListBucket"], Resource = var.state_bucket_arn, Condition = { StringLike = { "s3:prefix" = [var.platform_state_key, "${var.platform_state_key}.tflock"] } } },
      { Sid = "PlatformState", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"], Resource = "${var.state_bucket_arn}/${var.platform_state_key}" },
      { Sid = "PlatformLock", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = "${var.state_bucket_arn}/${var.platform_state_key}.tflock" },
      { Sid = "EksCluster", Effect = "Allow", Action = ["eks:CreateCluster", "eks:DeleteCluster", "eks:UpdateClusterConfig", "eks:UpdateClusterVersion", "eks:TagResource", "eks:UntagResource", "eks:Describe*", "eks:List*", "eks:CreateNodegroup", "eks:DeleteNodegroup", "eks:UpdateNodegroupConfig", "eks:UpdateNodegroupVersion", "eks:CreateAddon", "eks:DeleteAddon", "eks:UpdateAddon", "eks:CreatePodIdentityAssociation", "eks:DeletePodIdentityAssociation", "eks:UpdatePodIdentityAssociation", "eks:DeleteAccessEntry", "eks:DisassociateAccessPolicy"], Resource = ["${local.eks}:cluster/${var.name}", "${local.eks}:nodegroup/${var.name}/*", "${local.eks}:addon/${var.name}/*", "${local.eks}:podidentityassociation/${var.name}/*", "${local.eks}:access-entry/${var.name}/*"] },
      { Sid = "EksAccessForAdminRolesOnly", Effect = "Allow", Action = ["eks:CreateAccessEntry", "eks:AssociateAccessPolicy", "eks:UpdateAccessEntry"], Resource = ["${local.eks}:cluster/${var.name}", "${local.eks}:access-entry/${var.name}/*"], Condition = { ArnEquals = { "eks:principalArn" = var.admin_role_arns } } },
      { Sid = "EksCatalogReads", Effect = "Allow", Action = ["eks:DescribeAddonVersions", "eks:DescribeClusterVersions", "eks:DescribeAddonConfiguration", "eks:ListClusters"], Resource = "*" },
      { Sid = "PlatformLogGroups", Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy", "logs:TagResource", "logs:UntagResource", "logs:TagLogGroup", "logs:ListTagsForResource", "logs:ListTagsLogGroup"], Resource = ["${local.logs}:/aws/eks/${var.name}/*", "${local.logs}:/finsight/${var.name}/*"] },
      { Sid = "LogReads", Effect = "Allow", Action = ["logs:DescribeLogGroups"], Resource = "*", Condition = local.region },
      { Sid = "ZoneReads", Effect = "Allow", Action = ["route53:GetHostedZone", "route53:ListTagsForResource"], Resource = "arn:aws:route53:::hostedzone/${var.zone_id}" },
    ]
  }

  ec2 = "arn:aws:ec2:${var.region}:${var.account_id}"
  # Each creation action and the one resource type it creates. aws:RequestTag is request-wide, so it
  # is granted only on the new resource; the existing resources a creation is also authorised against
  # (the VPC, subnet, Elastic IP, route tables or security groups) must already carry the ownership
  # tag, or a tagged request could place resources in another project's network.
  ec2_create = {
    CreateVpc            = "vpc", CreateSubnet = "subnet", CreateInternetGateway = "internet-gateway", AllocateAddress = "elastic-ip",
    CreateNatGateway     = "natgateway", CreateRouteTable = "route-table", CreateSecurityGroup = "security-group",
    CreateLaunchTemplate = "launch-template", CreateFlowLogs = "vpc-flow-log", CreateVpcEndpoint = "vpc-endpoint",
  }
  ec2_create_in_owned = ["ec2:CreateSubnet", "ec2:CreateNatGateway", "ec2:CreateRouteTable", "ec2:CreateSecurityGroup", "ec2:CreateFlowLogs", "ec2:CreateVpcEndpoint"]
  ec2_change = [
    "ec2:DeleteVpc", "ec2:ModifyVpcAttribute", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute", "ec2:AttachInternetGateway",
    "ec2:DetachInternetGateway", "ec2:DeleteInternetGateway", "ec2:DeleteNatGateway", "ec2:ReleaseAddress", "ec2:DisassociateAddress",
    "ec2:DeleteRouteTable", "ec2:CreateRoute", "ec2:ReplaceRoute", "ec2:DeleteRoute", "ec2:AssociateRouteTable",
    "ec2:DisassociateRouteTable", "ec2:DeleteSecurityGroup", "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
    "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress", "ec2:ModifySecurityGroupRules",
    "ec2:UpdateSecurityGroupRuleDescriptionsIngress", "ec2:UpdateSecurityGroupRuleDescriptionsEgress", "ec2:DeleteLaunchTemplate",
    "ec2:ModifyLaunchTemplate", "ec2:CreateLaunchTemplateVersion", "ec2:DeleteFlowLogs", "ec2:DeleteVpcEndpoints",
    "ec2:ModifyVpcEndpoint", "ec2:CreateTags", "ec2:DeleteTags",
  ]
  sg_rule_actions = [
    "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
    "ec2:ModifySecurityGroupRules", "ec2:UpdateSecurityGroupRuleDescriptionsIngress", "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
  ]
  eks_sg_rule_actions = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress", "ec2:ModifySecurityGroupRules", "ec2:UpdateSecurityGroupRuleDescriptionsIngress"]

  # FinSight VPC and networking, in this Region, by ownership tag. Nothing here can tag an existing
  # untagged resource, so another project's resources cannot be adopted by adding Project=finsight.
  # A new VPC's untagged default security group is therefore tagged once by a human (terraform-ci.md).
  apply_network = {
    Version = "2012-10-17"
    Statement = concat(
      [{ Sid = "Ec2Reads", Effect = "Allow", Action = ["ec2:Describe*", "ec2:Get*", "autoscaling:DescribeAutoScalingGroups"], Resource = "*", Condition = local.region }],
      [for a, t in local.ec2_create : { Sid = "New${replace(title(replace(t, "-", " ")), " ", "")}", Effect = "Allow", Action = "ec2:${a}", Resource = "${local.ec2}:${t}/*", Condition = { StringEquals = { "aws:RequestTag/Project" = var.project_tag } } }],
      [
        { Sid = "CreateInOwnedNetwork", Effect = "Allow", Action = local.ec2_create_in_owned, Resource = [for t in ["vpc", "subnet", "elastic-ip", "route-table", "security-group"] : "${local.ec2}:${t}/*"], Condition = { StringEquals = { "aws:ResourceTag/Project" = var.project_tag } } },
        # A gateway endpoint is also authorised against the AWS service it connects to.
        { Sid = "EndpointServices", Effect = "Allow", Action = "ec2:CreateVpcEndpoint", Resource = "arn:aws:ec2:${var.region}:*:vpc-endpoint-service/*" },
        { Sid = "TagOnCreate", Effect = "Allow", Action = "ec2:CreateTags", Resource = "*", Condition = { StringEquals = { "aws:RequestedRegion" = var.region, "ec2:CreateAction" = keys(local.ec2_create), "aws:RequestTag/Project" = var.project_tag } } },
        { Sid = "ChangeOwnedNetwork", Effect = "Allow", Action = local.ec2_change, Resource = "*", Condition = { StringEquals = { "aws:RequestedRegion" = var.region, "aws:ResourceTag/Project" = var.project_tag } } },
        # Every rule action also needs its security group, which must be owned or the EKS cluster group,
        # so the rule objects themselves (including untagged default rules) need no tag.
        { Sid = "SecurityGroupRules", Effect = "Allow", Action = local.sg_rule_actions, Resource = "${local.ec2}:security-group-rule/*" },
        { Sid = "TagNewRules", Effect = "Allow", Action = "ec2:CreateTags", Resource = "${local.ec2}:security-group-rule/*", Condition = { StringEquals = { "aws:RequestTag/Project" = var.project_tag } } },
        # EKS creates and tags the cluster security group itself (aws: tags cannot be set by users).
        { Sid = "EksClusterSecurityGroup", Effect = "Allow", Action = local.eks_sg_rule_actions, Resource = "${local.ec2}:security-group/*", Condition = { StringEquals = { "aws:ResourceTag/aws:eks:cluster-name" = var.name } } },
      ]
    )
  }
}
output "boundary_name" {
  description = "Name of the managed permissions boundary policy."
  value       = local.boundary_name
}
output "boundary_arn" {
  description = "ARN the platform must set as permissions_boundary on every role it creates."
  value       = local.boundary_arn
}
output "boundary_policy" {
  description = "Permissions boundary JSON."
  value       = jsonencode(local.boundary)
  precondition {
    condition     = length(jsonencode(local.boundary)) <= 6144
    error_message = "Managed policies are limited to 6,144 characters."
  }
}
output "apply_policies" {
  description = "Managed policies for the CI apply role: guardrails (denies), roles (platform IAM roles), identity (state/EKS/logs/DNS) and network (EC2)."
  value = {
    guardrails = jsonencode(local.guardrails)
    roles      = jsonencode(local.apply_roles)
    identity   = jsonencode(local.apply_identity)
    network    = jsonencode(local.apply_network)
  }
  precondition {
    condition     = alltrue([for p in [local.guardrails, local.apply_roles, local.apply_identity, local.apply_network] : length(jsonencode(p)) <= 6144])
    error_message = "Each managed policy is limited to 6,144 characters."
  }
}
