# Offline unit tests with a mocked AWS provider. All run blocks use plan and create no resources.
mock_provider "aws" {}
variables {
  name            = "finsight-test-aws-load-balancer-controller"
  cluster_arn     = "arn:aws:eks:eu-west-2:111111111111:cluster/finsight-test"
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  inline_policy   = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"elasticloadbalancing:DescribeLoadBalancers\",\"Resource\":\"*\"}]}"
}
run "trust_limited_to_pod_identity_for_one_service_account" {
  command = plan
  assert {
    condition     = length(jsondecode(aws_iam_role.this.assume_role_policy).Statement) == 1
    error_message = "The trust policy must have exactly one statement."
  }
  assert {
    condition = (
      jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Effect == "Allow" &&
      jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal == { Service = "pods.eks.amazonaws.com" } &&
      toset(jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Action) == toset(["sts:AssumeRole", "sts:TagSession"])
    )
    error_message = "Only the EKS Pod Identity service may assume the role, with AssumeRole and TagSession."
  }
  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.ArnEquals["aws:SourceArn"] == "arn:aws:eks:eu-west-2:111111111111:cluster/finsight-test"
    error_message = "Trust must be limited to the one cluster."
  }
  assert {
    condition = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringEquals == {
      "aws:RequestTag/kubernetes-namespace"       = "kube-system"
      "aws:RequestTag/kubernetes-service-account" = "aws-load-balancer-controller"
    }
    error_message = "Trust must be limited to the exact namespace and service account."
  }
}
run "inline_policy_only" {
  command = plan
  assert {
    condition     = length(aws_iam_role_policy.this) == 1 && length(aws_iam_role_policy_attachment.this) == 0
    error_message = "A role given only an inline policy must have no managed policy attachments."
  }
}
run "no_policies_when_none_given" {
  command = plan
  variables { inline_policy = null }
  assert {
    condition     = length(aws_iam_role_policy.this) == 0 && length(aws_iam_role_policy_attachment.this) == 0
    error_message = "No permissions may be granted unless supplied."
  }
}
