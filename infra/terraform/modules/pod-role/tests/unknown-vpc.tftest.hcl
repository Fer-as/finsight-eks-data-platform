mock_provider "aws" {
  alias = "offline"
}

run "controller_role_with_vpc_unknown_until_apply" {
  command   = plan
  providers = { aws = aws.offline }
  module { source = "./tests/unknown-vpc" }
}
