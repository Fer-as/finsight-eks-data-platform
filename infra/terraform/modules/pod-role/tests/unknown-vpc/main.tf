# Model the first platform deployment: the VPC ID is unknown until apply.
# terraform_data is built in; the test uses plan only and a mocked AWS provider.
terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}
resource "terraform_data" "vpc" {
  input = "vpc-0123456789abcdef0"
}
module "policy" {
  source       = "../../../load-balancer-controller-policy"
  region       = "eu-west-2"
  account_id   = "111111111111"
  cluster_name = "finsight-test"
  vpc_id       = terraform_data.vpc.output
}
module "role" {
  source               = "../.."
  name                 = "finsight-test-aws-load-balancer-controller"
  cluster_arn          = "arn:aws:eks:eu-west-2:111111111111:cluster/finsight-test"
  namespace            = "kube-system"
  service_account      = "aws-load-balancer-controller"
  inline_policy        = module.policy.policy
  permissions_boundary = "arn:aws:iam::111111111111:policy/finsight-test-workload-boundary"
}
