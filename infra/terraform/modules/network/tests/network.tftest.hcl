mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}
variables {
  name   = "finsight-test"
  region = "eu-west-2"
  config = jsondecode(file("../../config/defaults.json")).network
}
run "valid_two_az_network" {
  command = plan
  assert {
    condition     = length(aws_subnet.private) == 2 && length(aws_subnet.public) == 2
    error_message = "Expected two private and two public subnets."
  }
}
run "reject_overlap" {
  command = plan
  variables {
    config = merge(jsondecode(file("../../config/defaults.json")).network, {
      private_cidrs = ["10.42.0.0/24", "10.42.32.0/20"]
    })
  }
  expect_failures = [output.vpc_id]
}
run "reject_outside_vpc" {
  command = plan
  variables {
    config = merge(jsondecode(file("../../config/defaults.json")).network, {
      private_cidrs = ["10.43.16.0/20", "10.42.32.0/20"]
    })
  }
  expect_failures = [output.vpc_id]
}
run "reject_duplicate_az" {
  command = plan
  variables {
    config = merge(jsondecode(file("../../config/defaults.json")).network, {
      availability_zones = ["eu-west-2a", "eu-west-2a"]
    })
  }
  expect_failures = [var.config]
}
run "reject_wrong_region_az" {
  command = plan
  variables {
    config = merge(jsondecode(file("../../config/defaults.json")).network, {
      availability_zones = ["eu-west-2a", "eu-west-1b"]
    })
  }
  expect_failures = [output.vpc_id]
}
