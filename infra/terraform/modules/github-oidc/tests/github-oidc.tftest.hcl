# Offline unit tests with a mocked AWS provider. All run blocks use plan and create no resources.
# Synthetic fixtures only: account 111111111111 and a made-up immutable repository subject.
mock_provider "aws" {}
variables {
  name       = "finsight-test"
  account_id = "111111111111"
  region     = "eu-west-2"
  config = {
    create_provider       = false
    existing_provider_arn = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
    subject_prefix        = "repo:example-owner@1000/example-repo@2000"
    infra_environment     = "dev-infrastructure"
    images_environment    = "dev-images"
    apply_environment     = "dev-infrastructure-apply"
  }
  state_bucket_arn   = "arn:aws:s3:::finsight-test-state"
  platform_state_key = "dev/platform/terraform.tfstate"
  repository_arns    = ["arn:aws:ecr:eu-west-2:111111111111:repository/finsight-test/api"]
  zone_id            = "Z0123456789TESTZONE"
}
run "shared_provider_reused_not_created" {
  command = plan
  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0
    error_message = "The shared GitHub OIDC provider must be referenced, never created or replaced."
  }
  assert {
    condition     = toset(keys(aws_iam_role.this)) == toset(["infra_plan", "images", "infra_apply"])
    error_message = "Expected exactly the plan, image and apply roles."
  }
}
run "apply_trust_is_exact_protected_environment" {
  command = plan
  assert {
    condition = jsondecode(aws_iam_role.this["infra_apply"].assume_role_policy).Statement == [{
      Effect    = "Allow"
      Principal = { Federated = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = { StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = "repo:example-owner@1000/example-repo@2000:environment:dev-infrastructure-apply"
      } }
    }]
    error_message = "Apply trust must be one exact-match statement for the protected apply environment only."
  }
  assert {
    condition     = aws_iam_role.this["infra_apply"].max_session_duration == 3600
    error_message = "Apply sessions must be limited to one hour."
  }
}
run "no_wildcards_and_distinct_subjects" {
  command = plan
  assert {
    condition     = !anytrue([for r in aws_iam_role.this : strcontains(r.assume_role_policy, "*") || strcontains(r.assume_role_policy, "StringLike")])
    error_message = "No trust policy may use wildcards or StringLike."
  }
  assert {
    condition = length(distinct([
      for r in aws_iam_role.this : jsondecode(r.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]
    ])) == 3
    error_message = "Each role must trust a different environment subject."
  }
}
run "apply_role_limited_to_platform_state" {
  command = plan
  assert {
    condition = alltrue(flatten([
      for s in jsondecode(aws_iam_role_policy.infra_apply_state.policy).Statement : [
        for a in s.Action : contains(["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"], a)
      ]
    ]))
    error_message = "Until permissions for platform resources are approved, the apply role may only use the platform state."
  }
  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.infra_apply_state.policy).Statement :
      contains([
        "arn:aws:s3:::finsight-test-state",
        "arn:aws:s3:::finsight-test-state/dev/platform/terraform.tfstate",
        "arn:aws:s3:::finsight-test-state/dev/platform/terraform.tfstate.tflock"
      ], s.Resource)
    ])
    error_message = "The apply role must never reach bootstrap or foundation state."
  }
  assert {
    condition     = jsondecode(aws_iam_role_policy.infra_apply_state.policy).Statement[2].Action == ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"] && endswith(jsondecode(aws_iam_role_policy.infra_apply_state.policy).Statement[2].Resource, ".tflock")
    error_message = "Delete is only allowed on the platform lock object."
  }
}
run "plan_role_stays_read_only" {
  command = plan
  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.infra_plan.policy).Statement :
      endswith(tostring(s.Resource), ".tflock") if contains(s.Action, "s3:PutObject") || contains(s.Action, "s3:DeleteObject")
    ])
    error_message = "The plan role may write only its lock object."
  }
  assert {
    condition = !anytrue(flatten([
      for s in jsondecode(aws_iam_role_policy.infra_plan.policy).Statement : [
        for a in s.Action : can(regex("^(iam|eks|ec2|elasticloadbalancing|logs|route53):(Create|Delete|Put|Attach|Update|Modify|Pass|Tag|Untag|Run|Terminate)", a))
      ]
    ]))
    error_message = "The plan role must have no mutating AWS actions."
  }
}
run "reject_apply_environment_reused_for_plan" {
  command = plan
  variables {
    config = {
      create_provider       = false
      existing_provider_arn = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
      subject_prefix        = "repo:example-owner@1000/example-repo@2000"
      infra_environment     = "dev-infrastructure"
      images_environment    = "dev-images"
      apply_environment     = "dev-infrastructure"
    }
  }
  expect_failures = [var.config]
}
run "reject_wildcard_apply_environment" {
  command = plan
  variables {
    config = {
      create_provider       = false
      existing_provider_arn = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
      subject_prefix        = "repo:example-owner@1000/example-repo@2000"
      infra_environment     = "dev-infrastructure"
      images_environment    = "dev-images"
      apply_environment     = "dev-*"
    }
  }
  expect_failures = [var.config]
}
