# Provider-free tests. Synthetic fixtures only (account 111111111111). The evaluator models policy
# text; it is not proof of real AWS authorization (see tests/evaluator/main.tf).
variables {
  name                 = "finsight-dev"
  account_id           = "111111111111"
  region               = "eu-west-2"
  state_bucket_arn     = "arn:aws:s3:::finsight-test-state"
  platform_state_key   = "dev/platform/terraform.tfstate"
  protected_state_keys = ["bootstrap/terraform.tfstate", "dev/foundation/terraform.tfstate"]
  data_bucket          = "finsight-test-data"
  zone_id              = "Z0123456789TESTZONE"
  admin_role_arns      = ["arn:aws:iam::111111111111:role/finsight-dev-eks-admin"]
}
run "policies" {
  command = plan
  assert {
    condition     = output.boundary_arn == "arn:aws:iam::111111111111:policy/finsight-dev-workload-boundary"
    error_message = "Boundary ARN must be deterministic so the platform can reference it."
  }
  assert {
    condition     = !strcontains(output.boundary_policy, "\"iam:CreateRole\"") && !strcontains(output.boundary_policy, "iam:PassRole") && !strcontains(output.boundary_policy, "sts:")
    error_message = "Bounded workload roles must never be able to manage IAM, pass roles or assume roles."
  }
  assert {
    condition = !anytrue([for p in values(output.apply_policies) : anytrue([
      for s in jsondecode(p).Statement : s.Effect == "Allow" && contains(flatten([s.Action]), "*")
    ])])
    error_message = "No wildcard-all allow."
  }
  assert {
    condition = !anytrue([for p in values(output.apply_policies) : anytrue([
      for s in jsondecode(p).Statement : s.Effect == "Allow" && can(s.Condition.Null)
    ])])
    error_message = "No allow may target untagged resources (adoption of other projects' resources)."
  }
  assert {
    condition = !anytrue([for p in values(output.apply_policies) : anytrue([
      for s in jsondecode(p).Statement : s.Effect == "Allow" && anytrue([for r in flatten([s.Resource]) : strcontains(r, ":role/finsight-dev-*")])
    ])])
    error_message = "IAM role permissions must name the exact platform roles, not the prefix."
  }
}
run "reject_governance_role_as_platform_role" {
  command = plan
  variables {
    platform_roles = ["cluster", "github-infra-apply"]
  }
  expect_failures = [var.platform_roles]
}
run "apply_allows_platform_operations" {
  command = plan
  module { source = "./tests/evaluator" }
  variables {
    policies = values(run.policies.apply_policies)
    requests = {
      create_bounded_role      = { action = "iam:CreateRole", resource = "arn:aws:iam::111111111111:role/finsight-dev-cluster", context = { "iam:PermissionsBoundary" = "arn:aws:iam::111111111111:policy/finsight-dev-workload-boundary", "aws:RequestTag/Project" = "finsight" } }
      tag_role_on_create       = { action = "iam:TagRole", resource = "arn:aws:iam::111111111111:role/finsight-dev-cluster", context = { "aws:RequestTag/Project" = "finsight", "aws:TagKeys" = "Project,Environment" } }
      attach_cluster_policy    = { action = "iam:AttachRolePolicy", resource = "arn:aws:iam::111111111111:role/finsight-dev-cluster", context = { "iam:PermissionsBoundary" = "arn:aws:iam::111111111111:policy/finsight-dev-workload-boundary", "iam:PolicyARN" = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy" } }
      put_pod_role_policy      = { action = "iam:PutRolePolicy", resource = "arn:aws:iam::111111111111:role/finsight-dev-external-dns", context = { "iam:PermissionsBoundary" = "arn:aws:iam::111111111111:policy/finsight-dev-workload-boundary" } }
      update_owned_trust       = { action = "iam:UpdateAssumeRolePolicy", resource = "arn:aws:iam::111111111111:role/finsight-dev-etl", context = { "aws:ResourceTag/Project" = "finsight" } }
      pass_cluster_role_to_eks = { action = "iam:PassRole", resource = "arn:aws:iam::111111111111:role/finsight-dev-cluster", context = { "iam:PassedToService" = "eks.amazonaws.com" } }
      pass_flow_role           = { action = "iam:PassRole", resource = "arn:aws:iam::111111111111:role/finsight-dev-flow-logs", context = { "iam:PassedToService" = "vpc-flow-logs.amazonaws.com" } }
      nodegroup_service_role   = { action = "iam:CreateServiceLinkedRole", resource = "arn:aws:iam::111111111111:role/aws-service-role/eks-nodegroup.amazonaws.com/x", context = { "iam:AWSServiceName" = "eks-nodegroup.amazonaws.com" } }
      create_vpc               = { action = "ec2:CreateVpc", resource = "arn:aws:ec2:eu-west-2:111111111111:vpc/*", context = { "aws:RequestedRegion" = "eu-west-2", "aws:RequestTag/Project" = "finsight" } }
      tag_vpc_on_create        = { action = "ec2:CreateTags", resource = "arn:aws:ec2:eu-west-2:111111111111:vpc/*", context = { "aws:RequestedRegion" = "eu-west-2", "ec2:CreateAction" = "CreateVpc", "aws:RequestTag/Project" = "finsight" } }
      route_in_owned_table     = { action = "ec2:CreateRoute", resource = "arn:aws:ec2:eu-west-2:111111111111:route-table/rtb-0a", context = { "aws:RequestedRegion" = "eu-west-2", "aws:ResourceTag/Project" = "finsight" } }
      delete_owned_nat         = { action = "ec2:DeleteNatGateway", resource = "arn:aws:ec2:eu-west-2:111111111111:natgateway/nat-0a", context = { "aws:RequestedRegion" = "eu-west-2", "aws:ResourceTag/Project" = "finsight" } }
      rule_on_eks_cluster_sg   = { action = "ec2:AuthorizeSecurityGroupIngress", resource = "arn:aws:ec2:eu-west-2:111111111111:security-group/sg-0eks", context = { "aws:RequestedRegion" = "eu-west-2", "aws:ResourceTag/aws:eks:cluster-name" = "finsight-dev" } }
      new_rule_resource        = { action = "ec2:AuthorizeSecurityGroupIngress", resource = "arn:aws:ec2:eu-west-2:111111111111:security-group-rule/sgr-0a", context = { "aws:RequestTag/Project" = "finsight" } }
      tag_new_rule             = { action = "ec2:CreateTags", resource = "arn:aws:ec2:eu-west-2:111111111111:security-group-rule/sgr-0a", context = { "aws:RequestTag/Project" = "finsight" } }
      egress_rule_owned_group  = { action = "ec2:AuthorizeSecurityGroupEgress", resource = "arn:aws:ec2:eu-west-2:111111111111:security-group/sg-0nlb", context = { "aws:RequestedRegion" = "eu-west-2", "aws:ResourceTag/Project" = "finsight" } }
      egress_rule_new          = { action = "ec2:AuthorizeSecurityGroupEgress", resource = "arn:aws:ec2:eu-west-2:111111111111:security-group-rule/sgr-0b", context = { "aws:RequestTag/Project" = "finsight" } }
      revoke_default_egress    = { action = "ec2:RevokeSecurityGroupEgress", resource = "arn:aws:ec2:eu-west-2:111111111111:security-group-rule/sgr-0default", context = {} }
      create_subnet            = { action = "ec2:CreateSubnet", resource = "arn:aws:ec2:eu-west-2:111111111111:subnet/*", context = { "aws:RequestTag/Project" = "finsight" } }
      subnet_in_owned_vpc      = { action = "ec2:CreateSubnet", resource = "arn:aws:ec2:eu-west-2:111111111111:vpc/vpc-0a", context = { "aws:RequestTag/Project" = "finsight", "aws:ResourceTag/Project" = "finsight" } }
      nat_with_owned_eip       = { action = "ec2:CreateNatGateway", resource = "arn:aws:ec2:eu-west-2:111111111111:elastic-ip/eipalloc-0a", context = { "aws:RequestTag/Project" = "finsight", "aws:ResourceTag/Project" = "finsight" } }
      endpoint_owned_routes    = { action = "ec2:CreateVpcEndpoint", resource = "arn:aws:ec2:eu-west-2:111111111111:route-table/rtb-0a", context = { "aws:RequestTag/Project" = "finsight", "aws:ResourceTag/Project" = "finsight" } }
      endpoint_service         = { action = "ec2:CreateVpcEndpoint", resource = "arn:aws:ec2:eu-west-2::vpc-endpoint-service/com.amazonaws.eu-west-2.s3", context = {} }
      launch_template          = { action = "ec2:CreateLaunchTemplate", resource = "arn:aws:ec2:eu-west-2:111111111111:launch-template/*", context = { "aws:RequestTag/Project" = "finsight" } }
      pass_pod_role            = { action = "iam:PassRole", resource = "arn:aws:iam::111111111111:role/finsight-dev-aws-load-balancer-controller", context = { "iam:PassedToService" = "pods.eks.amazonaws.com" } }
      create_cluster           = { action = "eks:CreateCluster", resource = "arn:aws:eks:eu-west-2:111111111111:cluster/finsight-dev", context = {} }
      create_nodegroup         = { action = "eks:CreateNodegroup", resource = "arn:aws:eks:eu-west-2:111111111111:nodegroup/finsight-dev/finsight-dev-workers/abc", context = {} }
      create_addon             = { action = "eks:CreateAddon", resource = "arn:aws:eks:eu-west-2:111111111111:addon/finsight-dev/vpc-cni/abc", context = {} }
      pod_identity_association = { action = "eks:CreatePodIdentityAssociation", resource = "arn:aws:eks:eu-west-2:111111111111:cluster/finsight-dev", context = {} }
      admin_access_entry       = { action = "eks:CreateAccessEntry", resource = "arn:aws:eks:eu-west-2:111111111111:cluster/finsight-dev", context = { "eks:principalArn" = "arn:aws:iam::111111111111:role/finsight-dev-eks-admin" } }
      cluster_log_group        = { action = "logs:CreateLogGroup", resource = "arn:aws:logs:eu-west-2:111111111111:log-group:/aws/eks/finsight-dev/cluster", context = {} }
      flow_log_group           = { action = "logs:PutRetentionPolicy", resource = "arn:aws:logs:eu-west-2:111111111111:log-group:/finsight/finsight-dev/vpc-flow", context = {} }
      platform_state_write     = { action = "s3:PutObject", resource = "arn:aws:s3:::finsight-test-state/dev/platform/terraform.tfstate", context = {} }
      platform_lock_delete     = { action = "s3:DeleteObject", resource = "arn:aws:s3:::finsight-test-state/dev/platform/terraform.tfstate.tflock", context = {} }
      zone_read                = { action = "route53:GetHostedZone", resource = "arn:aws:route53:::hostedzone/Z0123456789TESTZONE", context = {} }
      describe_subnets         = { action = "ec2:DescribeSubnets", resource = "*", context = { "aws:RequestedRegion" = "eu-west-2" } }
    }
  }
  assert {
    condition     = alltrue(values(output.decisions))
    error_message = "A required platform operation was denied: ${jsonencode([for k, v in output.decisions : k if !v])}"
  }
}
run "apply_denies_escalation_and_unrelated_resources" {
  command = plan
  module { source = "./tests/evaluator" }
  variables {
    policies = values(run.policies.apply_policies)
    requests = {
      role_without_boundary    = { action = "iam:CreateRole", resource = "arn:aws:iam::111111111111:role/finsight-dev-x", context = { "aws:RequestTag/Project" = "finsight" } }
      role_with_other_boundary = { action = "iam:CreateRole", resource = "arn:aws:iam::111111111111:role/finsight-dev-x", context = { "iam:PermissionsBoundary" = "arn:aws:iam::111111111111:policy/permissive" } }
      role_outside_prefix      = { action = "iam:CreateRole", resource = "arn:aws:iam::111111111111:role/other-project-admin", context = { "iam:PermissionsBoundary" = "arn:aws:iam::111111111111:policy/finsight-dev-workload-boundary" } }
      remove_boundary          = { action = "iam:DeleteRolePermissionsBoundary", resource = "arn:aws:iam::111111111111:role/finsight-dev-cluster", context = { "aws:ResourceTag/Project" = "finsight" } }
      swap_boundary            = { action = "iam:PutRolePermissionsBoundary", resource = "arn:aws:iam::111111111111:role/finsight-dev-cluster", context = { "iam:PermissionsBoundary" = "arn:aws:iam::111111111111:policy/permissive" } }
      edit_boundary_policy     = { action = "iam:CreatePolicyVersion", resource = "arn:aws:iam::111111111111:policy/finsight-dev-workload-boundary", context = {} }
      attach_admin_policy      = { action = "iam:AttachRolePolicy", resource = "arn:aws:iam::111111111111:role/finsight-dev-cluster", context = { "iam:PermissionsBoundary" = "arn:aws:iam::111111111111:policy/finsight-dev-workload-boundary", "iam:PolicyARN" = "arn:aws:iam::aws:policy/AdministratorAccess" } }
      github_role_trust        = { action = "iam:UpdateAssumeRolePolicy", resource = "arn:aws:iam::111111111111:role/finsight-dev-github-infra-apply", context = { "aws:ResourceTag/Project" = "finsight" } }
      github_role_attach       = { action = "iam:AttachRolePolicy", resource = "arn:aws:iam::111111111111:role/finsight-dev-github-infra-apply", context = { "iam:PermissionsBoundary" = "arn:aws:iam::111111111111:policy/finsight-dev-workload-boundary", "iam:PolicyARN" = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy" } }
      admin_role_inline        = { action = "iam:PutRolePolicy", resource = "arn:aws:iam::111111111111:role/finsight-dev-eks-admin", context = { "iam:PermissionsBoundary" = "arn:aws:iam::111111111111:policy/finsight-dev-workload-boundary" } }
      delete_oidc_provider     = { action = "iam:DeleteOpenIDConnectProvider", resource = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com", context = {} }
      oidc_audience            = { action = "iam:AddClientIDToOpenIDConnectProvider", resource = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com", context = {} }
      pass_role_to_lambda      = { action = "iam:PassRole", resource = "arn:aws:iam::111111111111:role/finsight-dev-cluster", context = { "iam:PassedToService" = "lambda.amazonaws.com" } }
      pass_role_to_ec2         = { action = "iam:PassRole", resource = "arn:aws:iam::111111111111:role/finsight-dev-node", context = { "iam:PassedToService" = "ec2.amazonaws.com" } }
      pass_github_role         = { action = "iam:PassRole", resource = "arn:aws:iam::111111111111:role/finsight-dev-github-infra-apply", context = { "iam:PassedToService" = "eks.amazonaws.com" } }
      pass_foreign_role        = { action = "iam:PassRole", resource = "arn:aws:iam::111111111111:role/other-project-task", context = { "iam:PassedToService" = "eks.amazonaws.com" } }
      assume_bounded_role      = { action = "sts:AssumeRole", resource = "arn:aws:iam::111111111111:role/finsight-dev-cluster", context = {} }
      create_user              = { action = "iam:CreateUser", resource = "arn:aws:iam::111111111111:user/x", context = {} }
      create_access_key        = { action = "iam:CreateAccessKey", resource = "arn:aws:iam::111111111111:user/x", context = {} }
      write_foundation_state   = { action = "s3:PutObject", resource = "arn:aws:s3:::finsight-test-state/dev/foundation/terraform.tfstate", context = {} }
      read_bootstrap_state     = { action = "s3:GetObject", resource = "arn:aws:s3:::finsight-test-state/bootstrap/terraform.tfstate", context = {} }
      other_project_state      = { action = "s3:GetObject", resource = "arn:aws:s3:::other-project-state/ecs-v1/bootstrap/terraform.tfstate", context = {} }
      state_bucket_policy      = { action = "s3:PutBucketPolicy", resource = "arn:aws:s3:::finsight-test-state", context = {} }
      cluster_access_for_ci    = { action = "eks:CreateAccessEntry", resource = "arn:aws:eks:eu-west-2:111111111111:cluster/finsight-dev", context = { "eks:principalArn" = "arn:aws:iam::111111111111:role/finsight-dev-github-infra-apply" } }
      delete_other_project_vpc = { action = "ec2:DeleteVpc", resource = "arn:aws:ec2:eu-west-2:111111111111:vpc/vpc-0other", context = { "aws:RequestedRegion" = "eu-west-2", "aws:ResourceTag/Project" = "other" } }
      delete_untagged_vpc      = { action = "ec2:DeleteVpc", resource = "arn:aws:ec2:eu-west-2:111111111111:vpc/vpc-0default", context = { "aws:RequestedRegion" = "eu-west-2" } }
      create_vpc_wrong_tag     = { action = "ec2:CreateVpc", resource = "arn:aws:ec2:eu-west-2:111111111111:vpc/*", context = { "aws:RequestedRegion" = "eu-west-2", "aws:RequestTag/Project" = "other" } }
      create_vpc_other_region  = { action = "ec2:CreateVpc", resource = "arn:aws:ec2:eu-west-1:111111111111:vpc/*", context = { "aws:RequestedRegion" = "eu-west-1", "aws:RequestTag/Project" = "finsight" } }
      run_instances            = { action = "ec2:RunInstances", resource = "arn:aws:ec2:eu-west-2:111111111111:instance/*", context = { "aws:RequestedRegion" = "eu-west-2", "aws:RequestTag/Project" = "finsight" } }
      rule_on_foreign_sg       = { action = "ec2:AuthorizeSecurityGroupIngress", resource = "arn:aws:ec2:eu-west-2:111111111111:security-group/sg-0foreign", context = { "aws:RequestedRegion" = "eu-west-2" } }
      revoke_on_untagged_sg    = { action = "ec2:RevokeSecurityGroupIngress", resource = "arn:aws:ec2:eu-west-2:111111111111:security-group/sg-0default", context = { "aws:RequestedRegion" = "eu-west-2" } }
      tag_untagged_sg          = { action = "ec2:CreateTags", resource = "arn:aws:ec2:eu-west-2:111111111111:security-group/sg-0foreign", context = { "aws:RequestedRegion" = "eu-west-2", "aws:RequestTag/Project" = "finsight" } }
      tag_untagged_vpc         = { action = "ec2:CreateTags", resource = "arn:aws:ec2:eu-west-2:111111111111:vpc/vpc-0other", context = { "aws:RequestedRegion" = "eu-west-2", "aws:RequestTag/Project" = "finsight" } }
      egress_on_foreign_sg     = { action = "ec2:AuthorizeSecurityGroupEgress", resource = "arn:aws:ec2:eu-west-2:111111111111:security-group/sg-0foreign", context = { "aws:RequestedRegion" = "eu-west-2" } }
      subnet_in_foreign_vpc    = { action = "ec2:CreateSubnet", resource = "arn:aws:ec2:eu-west-2:111111111111:vpc/vpc-0other", context = { "aws:RequestedRegion" = "eu-west-2", "aws:RequestTag/Project" = "finsight", "aws:ResourceTag/Project" = "other" } }
      sg_in_untagged_vpc       = { action = "ec2:CreateSecurityGroup", resource = "arn:aws:ec2:eu-west-2:111111111111:vpc/vpc-0default", context = { "aws:RequestedRegion" = "eu-west-2", "aws:RequestTag/Project" = "finsight" } }
      nat_in_foreign_subnet    = { action = "ec2:CreateNatGateway", resource = "arn:aws:ec2:eu-west-2:111111111111:subnet/subnet-0other", context = { "aws:RequestedRegion" = "eu-west-2", "aws:RequestTag/Project" = "finsight" } }
      endpoint_foreign_routes  = { action = "ec2:CreateVpcEndpoint", resource = "arn:aws:ec2:eu-west-2:111111111111:route-table/rtb-0other", context = { "aws:RequestedRegion" = "eu-west-2", "aws:RequestTag/Project" = "finsight" } }
      flow_log_foreign_vpc     = { action = "ec2:CreateFlowLogs", resource = "arn:aws:ec2:eu-west-2:111111111111:vpc/vpc-0other", context = { "aws:RequestedRegion" = "eu-west-2", "aws:RequestTag/Project" = "finsight" } }
      role_unlisted_name       = { action = "iam:CreateRole", resource = "arn:aws:iam::111111111111:role/finsight-dev-x", context = { "iam:PermissionsBoundary" = "arn:aws:iam::111111111111:policy/finsight-dev-workload-boundary", "aws:RequestTag/Project" = "finsight" } }
      tag_unlisted_role        = { action = "iam:TagRole", resource = "arn:aws:iam::111111111111:role/finsight-dev-legacy", context = { "aws:RequestTag/Project" = "finsight", "aws:TagKeys" = "Project" } }
      trust_unlisted_role      = { action = "iam:UpdateAssumeRolePolicy", resource = "arn:aws:iam::111111111111:role/finsight-dev-legacy", context = { "aws:ResourceTag/Project" = "finsight" } }
      pass_unlisted_role       = { action = "iam:PassRole", resource = "arn:aws:iam::111111111111:role/finsight-dev-legacy", context = { "iam:PassedToService" = "eks.amazonaws.com" } }
      remove_ownership_tag     = { action = "ec2:DeleteTags", resource = "arn:aws:ec2:eu-west-2:111111111111:vpc/vpc-0a", context = { "aws:RequestedRegion" = "eu-west-2", "aws:ResourceTag/Project" = "finsight", "aws:TagKeys" = "Project" } }
      delete_other_cluster     = { action = "eks:DeleteCluster", resource = "arn:aws:eks:eu-west-2:111111111111:cluster/other-cluster", context = {} }
      delete_other_log_group   = { action = "logs:DeleteLogGroup", resource = "arn:aws:logs:eu-west-2:111111111111:log-group:/ecs/other-project", context = {} }
      change_dns_records       = { action = "route53:ChangeResourceRecordSets", resource = "arn:aws:route53:::hostedzone/Z0123456789TESTZONE", context = {} }
    }
  }
  assert {
    condition     = !anytrue(values(output.decisions))
    error_message = "An escalation or unrelated-resource request was allowed: ${jsonencode([for k, v in output.decisions : k if v])}"
  }
}
run "boundary_caps_workload_roles" {
  command = plan
  module { source = "./tests/evaluator" }
  variables {
    policies = [run.policies.boundary_policy]
    requests = {
      ok_pod_identity      = { action = "eks-auth:AssumeRoleForPodIdentity", resource = "arn:aws:eks:eu-west-2:111111111111:cluster/finsight-dev", context = {} }
      ok_image_pull        = { action = "ecr:BatchGetImage", resource = "arn:aws:ecr:eu-west-2:111111111111:repository/finsight-dev/api", context = {} }
      ok_cni_eni           = { action = "ec2:CreateNetworkInterface", resource = "*", context = { "aws:RequestedRegion" = "eu-west-2" } }
      ok_dns_record        = { action = "route53:ChangeResourceRecordSets", resource = "arn:aws:route53:::hostedzone/Z0123456789TESTZONE", context = {} }
      ok_etl_raw           = { action = "s3:PutObject", resource = "arn:aws:s3:::finsight-test-data/raw/a.csv", context = {} }
      ok_flow_logs         = { action = "logs:PutLogEvents", resource = "*", context = { "aws:RequestedRegion" = "eu-west-2" } }
      ok_lb_slr            = { action = "iam:CreateServiceLinkedRole", resource = "*", context = { "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com" } }
      ok_ebs_grant_via_ec2 = { action = "kms:CreateGrant", resource = "*", context = { "kms:ViaService" = "ec2.eu-west-2.amazonaws.com" } }
      no_create_role       = { action = "iam:CreateRole", resource = "*", context = {} }
      no_pass_role         = { action = "iam:PassRole", resource = "*", context = { "iam:PassedToService" = "ec2.amazonaws.com" } }
      no_assume_role       = { action = "sts:AssumeRole", resource = "*", context = {} }
      no_state_read        = { action = "s3:GetObject", resource = "arn:aws:s3:::finsight-test-state/dev/platform/terraform.tfstate", context = {} }
      no_data_other_prefix = { action = "s3:GetObject", resource = "arn:aws:s3:::finsight-test-data/private/x", context = {} }
      no_other_region_ec2  = { action = "ec2:RunInstances", resource = "*", context = { "aws:RequestedRegion" = "us-east-1" } }
      no_other_zone        = { action = "route53:ChangeResourceRecordSets", resource = "arn:aws:route53:::hostedzone/ZOTHERZONE00001", context = {} }
      no_direct_kms_grant  = { action = "kms:CreateGrant", resource = "*", context = {} }
      no_other_slr         = { action = "iam:CreateServiceLinkedRole", resource = "*", context = { "iam:AWSServiceName" = "lambda.amazonaws.com" } }
    }
  }
  assert {
    condition     = alltrue([for k, v in output.decisions : startswith(k, "ok_") ? v : !v])
    error_message = "Boundary decision mismatch: ${jsonencode({ for k, v in output.decisions : k => v if startswith(k, "ok_") != v })}"
  }
}
