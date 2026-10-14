# Provider-free unit tests. All run blocks use plan and create no resources.
# Synthetic fixtures only: account 111111111111, cluster finsight-test, documentation-style IDs.
variables {
  region       = "eu-west-2"
  account_id   = "111111111111"
  vpc_id       = "vpc-0123456789abcdef0"
  cluster_name = "finsight-test"
  # Requests the FinSight controller must be able to make.
  finsight_requests = {
    create_sg_finsight_vpc_resource = {
      action   = "ec2:CreateSecurityGroup"
      resource = "arn:aws:ec2:eu-west-2:111111111111:vpc/vpc-0123456789abcdef0"
      context  = {}
    }
    create_sg_new_group_resource = {
      action   = "ec2:CreateSecurityGroup"
      resource = "arn:aws:ec2:eu-west-2:111111111111:security-group/sg-0123456789abcdef0"
      context  = {}
    }
    create_listener_on_finsight_nlb = {
      action   = "elasticloadbalancing:CreateListener"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/net/k8s-ingress-nginx-0123456789/50dc6c495c0c9188"
      context  = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "finsight-test" }
    }
    modify_finsight_listener = {
      action   = "elasticloadbalancing:ModifyListener"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:listener/net/k8s-ingress-nginx-0123456789/50dc6c495c0c9188/f2f7dc8efc522ab2"
      context  = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "finsight-test" }
    }
    delete_finsight_listener = {
      action   = "elasticloadbalancing:DeleteListener"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:listener/net/k8s-ingress-nginx-0123456789/50dc6c495c0c9188/f2f7dc8efc522ab2"
      context  = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "finsight-test" }
    }
    register_finsight_targets = {
      action   = "elasticloadbalancing:RegisterTargets"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:targetgroup/k8s-ingress-nginx-0123456789/73e2d6bc24d8a067"
      context  = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "finsight-test" }
    }
    deregister_finsight_targets = {
      action   = "elasticloadbalancing:DeregisterTargets"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:targetgroup/k8s-ingress-nginx-0123456789/73e2d6bc24d8a067"
      context  = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "finsight-test" }
    }
    create_finsight_nlb = {
      action   = "elasticloadbalancing:CreateLoadBalancer"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/net/k8s-ingress-nginx-0123456789/50dc6c495c0c9188"
      context  = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "finsight-test" }
    }
    delete_finsight_nlb = {
      action   = "elasticloadbalancing:DeleteLoadBalancer"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/net/k8s-ingress-nginx-0123456789/50dc6c495c0c9188"
      context  = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "finsight-test" }
    }
    sg_ingress_in_finsight_vpc = {
      action   = "ec2:AuthorizeSecurityGroupIngress"
      resource = "arn:aws:ec2:eu-west-2:111111111111:security-group/sg-0123456789abcdef0"
      context  = { "ec2:Vpc" = "arn:aws:ec2:eu-west-2:111111111111:vpc/vpc-0123456789abcdef0" }
    }
    sg_rule_resource_without_vpc_key = {
      action   = "ec2:AuthorizeSecurityGroupIngress"
      resource = "arn:aws:ec2:eu-west-2:111111111111:security-group-rule/sgr-0123456789abcdef0"
      context  = {}
    }
    delete_finsight_tagged_sg = {
      action   = "ec2:DeleteSecurityGroup"
      resource = "arn:aws:ec2:eu-west-2:111111111111:security-group/sg-0aaaaaaaaaaaaaaa0"
      context  = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "finsight-test", "ec2:Vpc" = "arn:aws:ec2:eu-west-2:111111111111:vpc/vpc-0123456789abcdef0" }
    }
    tag_new_finsight_listener_on_create = {
      action   = "elasticloadbalancing:AddTags"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:listener/net/k8s-ingress-nginx-0123456789/50dc6c495c0c9188/f2f7dc8efc522ab2"
      context  = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "finsight-test", "elasticloadbalancing:CreateAction" = "CreateListener" }
    }
    tag_new_finsight_rule_on_create = {
      action   = "elasticloadbalancing:AddTags"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:listener-rule/net/k8s-ingress-nginx-0123456789/50dc6c495c0c9188/f2f7dc8efc522ab2/0123456789abcdef"
      context  = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "finsight-test", "elasticloadbalancing:CreateAction" = "CreateRule" }
    }
    create_rule_on_finsight_listener = {
      action   = "elasticloadbalancing:CreateRule"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:listener/net/k8s-ingress-nginx-0123456789/50dc6c495c0c9188/f2f7dc8efc522ab2"
      context  = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "finsight-test" }
    }
    remove_nonownership_listener_tag = {
      action   = "elasticloadbalancing:RemoveTags"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:listener/net/k8s-ingress-nginx-0123456789/50dc6c495c0c9188/f2f7dc8efc522ab2"
      context  = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "finsight-test", "aws:TagKeys" = "team" }
    }
    retag_finsight_listener_without_cluster_tag = {
      action   = "elasticloadbalancing:AddTags"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:listener/net/k8s-ingress-nginx-0123456789/50dc6c495c0c9188/f2f7dc8efc522ab2"
      context  = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "finsight-test" }
    }
    tag_finsight_target_group = {
      action   = "elasticloadbalancing:AddTags"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:targetgroup/k8s-ingress-nginx-0123456789/73e2d6bc24d8a067"
      context  = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "finsight-test" }
    }
    describe_load_balancers = {
      action   = "elasticloadbalancing:DescribeLoadBalancers"
      resource = "*"
      context  = {}
    }
  }
  # Requests against resources that are not FinSight's, in the same account.
  unrelated_requests = {
    create_sg_other_vpc_resource = {
      action   = "ec2:CreateSecurityGroup"
      resource = "arn:aws:ec2:eu-west-2:111111111111:vpc/vpc-0fffffffffffffff0"
      context  = {}
    }
    create_sg_other_region_resource = {
      action   = "ec2:CreateSecurityGroup"
      resource = "arn:aws:ec2:eu-west-1:111111111111:security-group/sg-0123456789abcdef0"
      context  = {}
    }
    claim_untagged_existing_listener = {
      action   = "elasticloadbalancing:AddTags"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:listener/net/k8s-other-app-0123456789/0000000000000005/0000000000000006"
      context  = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "finsight-test" }
    }
    mutate_untagged_existing_listener = {
      action   = "elasticloadbalancing:RemoveTags"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:listener/net/k8s-other-app-0123456789/0000000000000005/0000000000000006"
      context  = { "aws:TagKeys" = "team" }
    }
    remove_listener_ownership_tag = {
      action   = "elasticloadbalancing:RemoveTags"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:listener/net/k8s-ingress-nginx-0123456789/50dc6c495c0c9188/f2f7dc8efc522ab2"
      context  = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "finsight-test", "aws:TagKeys" = "elbv2.k8s.aws/cluster" }
    }
    remove_target_group_ownership_tag = {
      action   = "elasticloadbalancing:RemoveTags"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:targetgroup/k8s-ingress-nginx-0123456789/73e2d6bc24d8a067"
      context  = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "finsight-test", "aws:TagKeys" = "elbv2.k8s.aws/cluster" }
    }
    remove_security_group_ownership_tag = {
      action   = "ec2:DeleteTags"
      resource = "arn:aws:ec2:eu-west-2:111111111111:security-group/sg-0123456789abcdef0"
      context  = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "finsight-test", "aws:TagKeys" = "elbv2.k8s.aws/cluster" }
    }
    sg_ingress_tag_bypass_other_vpc = {
      action   = "ec2:AuthorizeSecurityGroupIngress"
      resource = "arn:aws:ec2:eu-west-2:111111111111:security-group/sg-0bbbbbbbbbbbbbbb0"
      context  = { "ec2:Vpc" = "arn:aws:ec2:eu-west-2:111111111111:vpc/vpc-0fffffffffffffff0", "aws:ResourceTag/elbv2.k8s.aws/cluster" = "finsight-test" }
    }
    modify_listener_attributes_other_region = {
      action   = "elasticloadbalancing:ModifyListenerAttributes"
      resource = "arn:aws:elasticloadbalancing:eu-west-1:111111111111:listener/net/k8s-ingress-nginx-0123456789/50dc6c495c0c9188/f2f7dc8efc522ab2"
      context  = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "finsight-test" }
    }
    create_alb_with_finsight_tag = {
      action   = "elasticloadbalancing:CreateLoadBalancer"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/app/k8s-other-app-0123456789/0000000000000003"
      context  = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "finsight-test" }
    }
    register_targets_other_cluster_k8s_tg = {
      action   = "elasticloadbalancing:RegisterTargets"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:targetgroup/k8s-other-app-0123456789/0000000000000001"
      context  = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "other-cluster" }
    }
    register_targets_other_project_tg = {
      action   = "elasticloadbalancing:RegisterTargets"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:targetgroup/other-project-tg/0000000000000002"
      context  = {}
    }
    modify_other_project_alb_listener = {
      action   = "elasticloadbalancing:ModifyListener"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:listener/app/other-project-alb/0000000000000003/0000000000000004"
      context  = {}
    }
    delete_other_cluster_k8s_listener = {
      action   = "elasticloadbalancing:DeleteListener"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:listener/net/k8s-other-app-0123456789/0000000000000005/0000000000000006"
      context  = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "other-cluster" }
    }
    create_listener_other_region = {
      action   = "elasticloadbalancing:CreateListener"
      resource = "arn:aws:elasticloadbalancing:eu-west-1:111111111111:loadbalancer/net/k8s-ingress-nginx-0123456789/0000000000000007"
      context  = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "finsight-test" }
    }
    sg_ingress_other_vpc = {
      action   = "ec2:AuthorizeSecurityGroupIngress"
      resource = "arn:aws:ec2:eu-west-2:111111111111:security-group/sg-0bbbbbbbbbbbbbbb0"
      context  = { "ec2:Vpc" = "arn:aws:ec2:eu-west-2:111111111111:vpc/vpc-0fffffffffffffff0" }
    }
    sg_ingress_other_cluster_tagged_sg = {
      action   = "ec2:RevokeSecurityGroupIngress"
      resource = "arn:aws:ec2:eu-west-2:111111111111:security-group/sg-0ccccccccccccccc0"
      context  = { "ec2:Vpc" = "arn:aws:ec2:eu-west-2:111111111111:vpc/vpc-0fffffffffffffff0", "aws:ResourceTag/elbv2.k8s.aws/cluster" = "other-cluster" }
    }
    delete_other_cluster_nlb = {
      action   = "elasticloadbalancing:DeleteLoadBalancer"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/net/k8s-other-app-0123456789/0000000000000008"
      context  = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "other-cluster" }
    }
    delete_other_cluster_sg = {
      action   = "ec2:DeleteSecurityGroup"
      resource = "arn:aws:ec2:eu-west-2:111111111111:security-group/sg-0ddddddddddddddd0"
      context  = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "other-cluster" }
    }
    create_nlb_tagged_for_other_cluster = {
      action   = "elasticloadbalancing:CreateLoadBalancer"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/net/k8s-other-app-0123456789/0000000000000009"
      context  = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "other-cluster" }
    }
    claim_other_cluster_listener = {
      action   = "elasticloadbalancing:AddTags"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:listener/net/k8s-other-app-0123456789/0000000000000005/0000000000000006"
      context  = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "other-cluster", "aws:RequestTag/elbv2.k8s.aws/cluster" = "finsight-test" }
    }
    tag_other_project_alb_listener = {
      action   = "elasticloadbalancing:AddTags"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:listener/app/other-project-alb/0000000000000003/0000000000000004"
      context  = {}
    }
    move_finsight_listener_to_other_cluster = {
      action   = "elasticloadbalancing:AddTags"
      resource = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:listener/net/k8s-ingress-nginx-0123456789/50dc6c495c0c9188/f2f7dc8efc522ab2"
      context  = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "finsight-test", "aws:RequestTag/elbv2.k8s.aws/cluster" = "other-cluster" }
    }
    associate_waf_with_any_resource = {
      action   = "wafv2:AssociateWebACL"
      resource = "*"
      context  = {}
    }
    remove_shield_protection = {
      action   = "shield:DeleteProtection"
      resource = "*"
      context  = {}
    }
    set_web_acl_anywhere = {
      action   = "elasticloadbalancing:SetWebAcl"
      resource = "*"
      context  = {}
    }
    change_dns_records = {
      action   = "route53:ChangeResourceRecordSets"
      resource = "arn:aws:route53:::hostedzone/Z0123456789TESTZONE"
      context  = {}
    }
  }
}
run "policy" {
  command = plan
  assert {
    condition     = output.source.controller_version == "v3.6.0" && output.source.commit == "267b5458b4c4c3066d47673a36dda275af07a6d6"
    error_message = "Policy must come from the pinned v3.6.0 commit."
  }
  assert {
    condition     = length(jsondecode(output.policy).Statement) == 16 && length(output.policy) < 10240
    error_message = "All 16 upstream statements must be kept and fit the inline policy limit."
  }
  assert {
    condition = alltrue([
      for s in jsondecode(output.policy).Statement :
      contains(keys(s), "Condition") if length(setintersection(toset(flatten([s.Action])), ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress"])) > 0
    ])
    error_message = "Security-group ingress changes must always carry a VPC or cluster-tag condition."
  }
  assert {
    condition = alltrue([
      for s in jsondecode(output.policy).Statement : alltrue([
        for k, v in try(s.Condition.Null, {}) : !(strcontains(k, "elbv2.k8s.aws/cluster") && v == "false")
      ])
    ])
    error_message = "No statement may accept any cluster's tag; presence checks must be replaced by this cluster's value."
  }
  assert {
    condition     = !anytrue([for a in ["SetWebAcl", "route53:", "AssociateWebACL", "DisassociateWebACL", "CreateProtection", "DeleteProtection"] : strcontains(output.policy, a)])
    error_message = "SetWebAcl (Resource * only), WAF association, Shield protection changes and Route 53 must not be granted."
  }
  assert {
    condition = alltrue([
      for a in flatten([for s in jsondecode(output.policy).Statement : flatten([s.Action])]) :
      !startswith(a, "iam:") || contains(["iam:CreateServiceLinkedRole", "iam:ListServerCertificates", "iam:GetServerCertificate"], a)
    ])
    error_message = "The only IAM actions allowed are the ELB service-linked role and server-certificate reads."
  }
}
run "finsight_requests_allowed" {
  command = plan
  module { source = "./tests/evaluator" }
  variables {
    policy   = run.policy.policy
    requests = var.finsight_requests
  }
  assert {
    condition     = alltrue(values(output.decisions))
    error_message = "A request FinSight's controller needs was denied: ${jsonencode([for k, v in output.decisions : k if !v])}"
  }
}
run "unrelated_requests_denied" {
  command = plan
  module { source = "./tests/evaluator" }
  variables {
    policy   = run.policy.policy
    requests = var.unrelated_requests
  }
  assert {
    condition     = !anytrue(values(output.decisions))
    error_message = "A request against another project's resources was allowed: ${jsonencode([for k, v in output.decisions : k if v])}"
  }
}
run "upstream_policy_would_allow_unrelated_requests" {
  command = plan
  module { source = "./tests/evaluator" }
  variables {
    policy   = file("./iam_policy-v3.6.0.json")
    requests = { for k, v in var.unrelated_requests : k => v if !contains(["set_web_acl_anywhere", "change_dns_records", "create_listener_other_region"], k) }
  }
  assert {
    condition     = alltrue(values(output.decisions))
    error_message = "Expected the unmodified upstream policy to allow these requests (otherwise the narrowing tests prove nothing): ${jsonencode([for k, v in output.decisions : k if !v])}"
  }
}
run "reject_bad_vpc_id" {
  command = plan
  variables { vpc_id = "0123456789abcdef0" }
  expect_failures = [var.vpc_id]
}
