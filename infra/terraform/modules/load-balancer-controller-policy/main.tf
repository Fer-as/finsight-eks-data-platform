variable "region" {
  description = "AWS Region of the cluster; scopes the narrowed Elastic Load Balancing ARNs."
  type        = string
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "Supply an AWS Region such as eu-west-2."
  }
}
variable "account_id" {
  description = "AWS account ID; scopes the narrowed ARNs."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Supply a 12-digit account ID."
  }
}
variable "vpc_id" {
  description = "Cluster VPC; security-group ingress changes are limited to it."
  type        = string
  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "Supply a VPC ID such as vpc-0123abcd."
  }
}
variable "cluster_name" {
  description = "EKS cluster name; must equal the controller's Helm clusterName, which it writes to the elbv2.k8s.aws/cluster tag."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,99}$", var.cluster_name))
    error_message = "Supply the lowercase EKS cluster name."
  }
}
locals {
  # Pinned upstream: kubernetes-sigs/aws-load-balancer-controller v3.6.0 (commit
  # 267b5458b4c4c3066d47673a36dda275af07a6d6), docs/install/iam_policy.json, byte-for-byte.
  controller_version = "v3.6.0"
  upstream_commit    = "267b5458b4c4c3066d47673a36dda275af07a6d6"
  upstream_file      = "${path.module}/iam_policy-v3.6.0.json"
  upstream_sha256    = "16f232c9d9f79366fe949c4550ad517a202380058a9e48d45a4e215044a20a6a"
  upstream           = jsondecode(file(local.upstream_file))

  arn_prefix = "arn:aws:elasticloadbalancing:${var.region}:${var.account_id}"
  # The controller names its NLBs and target groups k8s-<namespace>-<name>-<hash>. FinSight
  # uses NLBs only and never sets aws-load-balancer-name, so these patterns cover its resources.
  nlb_resources = [
    "${local.arn_prefix}:loadbalancer/net/k8s-*",
    "${local.arn_prefix}:listener/net/k8s-*",
    "${local.arn_prefix}:listener-rule/net/k8s-*",
  ]
  cluster_tag     = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = var.cluster_name }
  cluster_tag_key = "elbv2.k8s.aws/cluster"
  vpc_arn         = "arn:aws:ec2:${var.region}:${var.account_id}:vpc/${var.vpc_id}"
  sg_arn          = "arn:aws:ec2:${var.region}:${var.account_id}:security-group/*"
  lb_tg_resources = [local.nlb_resources[0], "${local.arn_prefix}:targetgroup/k8s-*"]
  # Only the upstream statements that can change existing resources without a cluster-tag
  # condition are narrowed, matched by their exact sorted action list. Resource types and
  # condition keys follow the AWS Service Authorization Reference (service reference v1.4).
  overrides = {
    # Request resources: security-group (has ec2:Vpc) and, when rules are tagged,
    # security-group-rule (has no ec2:Vpc). IfExists keeps the group check without denying the rule.
    "ec2:AuthorizeSecurityGroupIngress,ec2:RevokeSecurityGroupIngress" = {
      Resource  = [local.sg_arn, "arn:aws:ec2:${var.region}:${var.account_id}:security-group-rule/*"]
      Condition = { ArnEqualsIfExists = { "ec2:Vpc" = local.vpc_arn } }
    }
    # Creation authorizes both the new group and its VPC. Do not permit new groups in an
    # unrelated project's VPC. FinSight's custom-SG configuration does not call this action.
    "ec2:CreateSecurityGroup" = {
      Resource = [local.sg_arn, local.vpc_arn]
    }
    # CreateListener authorises on the load balancer; CreateRule and DeleteListener on the
    # listener; DeleteRule on the rule. All carry the cluster tag (listener and rule tagging is on
    # by default in v3.6.0, feature gate ListenerRulesTagging).
    "elasticloadbalancing:CreateListener,elasticloadbalancing:CreateRule,elasticloadbalancing:DeleteListener,elasticloadbalancing:DeleteRule" = {
      Resource  = local.nlb_resources
      Condition = { StringEquals = local.cluster_tag }
    }
    "elasticloadbalancing:DeregisterTargets,elasticloadbalancing:RegisterTargets" = {
      Resource  = ["${local.arn_prefix}:targetgroup/k8s-*"]
      Condition = { StringEquals = local.cluster_tag }
    }
    # SetWebAcl has no resource-level permissions (it needs Resource "*") and is ALB-only, so it
    # is removed rather than granted account-wide.
    "elasticloadbalancing:AddListenerCertificates,elasticloadbalancing:ModifyListener,elasticloadbalancing:ModifyRule,elasticloadbalancing:RemoveListenerCertificates,elasticloadbalancing:SetRulePriorities,elasticloadbalancing:SetWebAcl" = {
      Action = [
        "elasticloadbalancing:ModifyListener", "elasticloadbalancing:AddListenerCertificates",
        "elasticloadbalancing:RemoveListenerCertificates", "elasticloadbalancing:ModifyRule",
        "elasticloadbalancing:SetRulePriorities",
      ]
      Resource  = local.nlb_resources
      Condition = { StringEquals = local.cluster_tag }
    }
    # Existing listeners/rules must already be owned. Tag-on-create is a separate grant below:
    # IfExists here would let a direct AddTags claim an existing untagged listener.
    "elasticloadbalancing:AddTags,elasticloadbalancing:RemoveTags" = {
      Resource = ["${local.arn_prefix}:listener/net/k8s-*", "${local.arn_prefix}:listener-rule/net/k8s-*"]
      Condition = {
        StringEquals                   = local.cluster_tag
        Null                           = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "true" }
        "ForAllValues:StringNotEquals" = { "aws:TagKeys" = [local.cluster_tag_key] }
      }
    }
    # ALB feature integrations: keep the reads, drop WAF association and Shield protection changes,
    # which upstream allows on any resource and FinSight's NLB never uses.
    "acm:DescribeCertificate,acm:ListCertificates,cognito-idp:DescribeUserPoolClient,iam:GetServerCertificate,iam:ListServerCertificates,shield:CreateProtection,shield:DeleteProtection,shield:DescribeProtection,shield:GetSubscriptionState,waf-regional:AssociateWebACL,waf-regional:DisassociateWebACL,waf-regional:GetWebACL,waf-regional:GetWebACLForResource,wafv2:AssociateWebACL,wafv2:DisassociateWebACL,wafv2:GetWebACL,wafv2:GetWebACLForResource" = {
      Action = [
        "cognito-idp:DescribeUserPoolClient", "acm:ListCertificates", "acm:DescribeCertificate",
        "iam:ListServerCertificates", "iam:GetServerCertificate", "waf-regional:GetWebACL",
        "waf-regional:GetWebACLForResource", "wafv2:GetWebACL", "wafv2:GetWebACLForResource",
        "shield:GetSubscriptionState", "shield:DescribeProtection",
      ]
    }
  }
  # Key = sorted action list; statements that already have conditions get a "?" suffix so an
  # override can only ever replace an unconditional statement (10 and 11 share an action list).
  statement_keys = [
    for s in local.upstream.Statement : "${join(",", sort(flatten([s.Action])))}${contains(keys(s), "Condition") ? "?" : ""}"
  ]
  overridden = [
    for i, s in local.upstream.Statement : merge(s, lookup(local.overrides, local.statement_keys[i], {}))
  ]
  # Upstream tag conditions only require that a cluster tag exists (Null = "false"), which also
  # matches resources of any other cluster in the account. Require FinSight's value instead.
  cluster_tag_keys = ["aws:ResourceTag/elbv2.k8s.aws/cluster", "aws:RequestTag/elbv2.k8s.aws/cluster"]
  tag_scoped_count = length([
    for s in local.overridden : s if anytrue([
      for k, v in try(s.Condition.Null, {}) : contains(local.cluster_tag_keys, k) && v == "false"
    ])
  ])
  statements = [
    for s in local.overridden : merge(s, {
      # One-element loop only for statements that already have conditions; unconditioned stay as is.
      for _ in(contains(keys(s), "Condition") ? [1] : []) : "Condition" => {
        for op, kv in merge(s.Condition, {
          StringEquals = merge(try(s.Condition.StringEquals, {}), {
            for k, v in try(s.Condition.Null, {}) : k => var.cluster_name if contains(local.cluster_tag_keys, k) && v == "false"
          })
          Null = {
            for k, v in try(s.Condition.Null, {}) : k => v if !(contains(local.cluster_tag_keys, k) && v == "false")
          }
        }) : op => kv if length(kv) > 0
      }
    })
  ]
  # Unconditional upstream statements that the override targets; the drift check needs these.
  override_targets = [
    for k in local.statement_keys : k if contains(keys(local.overrides), k)
  ]
  # Retain upstream statement order/provenance while closing alternate Allow paths.
  # In particular, a tag-only SG Allow must not bypass the VPC condition above.
  scoped_statements = [for i, s in local.statements : merge(s,
    contains([5, 6, 7], i) ? { Resource = local.sg_arn } : {},
    i == 7 ? { Condition = merge(s.Condition, { ArnEquals = { "ec2:Vpc" = local.vpc_arn } }) } : {},
    contains([8, 10], i) ? { Resource = local.lb_tg_resources } : {},
    i == 12 ? { Resource = concat(local.lb_tg_resources, slice(local.nlb_resources, 1, 3)) } : {},
    # RequestTag is not a reliable deletion guard: RemoveTags/DeleteTags send TagKeys.
    contains([6, 10], i) ? { Condition = merge(s.Condition, {
      "ForAllValues:StringNotEquals" = { "aws:TagKeys" = [local.cluster_tag_key] }
    }) } : {},
    # AWS supplies CreateAction only during resource creation, not a direct AddTags call.
    # Cover the additional AddTags authorization on each new listener/rule, which has no
    # ResourceTag yet. Parent ownership is checked separately by statement 9.
    { for k, v in {
      Resource = concat(local.lb_tg_resources, slice(local.nlb_resources, 1, 3))
      Condition = { StringEquals = {
        "elasticloadbalancing:CreateAction"    = ["CreateTargetGroup", "CreateLoadBalancer", "CreateListener", "CreateRule"]
        "aws:RequestTag/elbv2.k8s.aws/cluster" = var.cluster_name
      } }
    } : k => v if i == 13 }
  )]
  policy = jsonencode({ Version = local.upstream.Version, Statement = local.scoped_statements })
}
output "policy" {
  description = "Controller IAM policy: upstream v3.6.0, scoped to this cluster's tag, account, Region, VPC and k8s-* NLB resources."
  value       = local.policy
  precondition {
    condition     = filesha256(local.upstream_file) == local.upstream_sha256
    error_message = "The vendored controller policy does not match the pinned upstream v3.6.0 file. Re-verify before changing the pin."
  }
  precondition {
    condition     = length(local.upstream.Statement) == 16 && length(local.override_targets) == length(local.overrides) && length(distinct(local.override_targets)) == length(local.overrides)
    error_message = "The upstream policy structure changed: every override must match exactly one unconditional statement."
  }
  precondition {
    condition     = local.tag_scoped_count == 7
    error_message = "Expected exactly seven upstream statements with cluster-tag presence checks to scope to this cluster; re-review the upstream policy."
  }
  precondition {
    condition     = length(local.policy) < 10240
    error_message = "The policy must fit IAM's 10,240-character limit for inline role policies."
  }
}
output "source" {
  description = "Provenance of the vendored upstream policy."
  value = {
    controller_version = local.controller_version
    commit             = local.upstream_commit
    path               = "docs/install/iam_policy.json"
    sha256             = local.upstream_sha256
  }
}
