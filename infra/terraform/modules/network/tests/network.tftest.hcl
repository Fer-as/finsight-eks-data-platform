mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}
variables {
  name                 = "finsight-test"
  region               = "eu-west-2"
  config               = jsondecode(file("../../config/defaults.json")).network
  permissions_boundary = "arn:aws:iam::111111111111:policy/finsight-test-workload-boundary"
}
run "valid_two_az_network" {
  command = plan
  assert {
    condition     = length(aws_subnet.private) == 2 && length(aws_subnet.public) == 2
    error_message = "Expected two private and two public subnets."
  }
}
run "private_subnets_never_assign_public_ips" {
  command = plan
  assert {
    condition     = alltrue([for s in concat(values(aws_subnet.private), values(aws_subnet.public)) : !s.map_public_ip_on_launch])
    error_message = "No subnet may auto-assign public IPs; nodes stay private and the NLB uses its own addresses."
  }
}
run "public_ingress_only_80_443_from_internet" {
  command = plan
  assert {
    condition     = toset(keys(aws_vpc_security_group_ingress_rule.public_listener)) == toset(["80", "443"])
    error_message = "Only ports 80 and 443 may be open to the internet."
  }
  assert {
    condition = alltrue([
      for r in aws_vpc_security_group_ingress_rule.public_listener :
      r.cidr_ipv4 == "0.0.0.0/0" && r.ip_protocol == "tcp" && r.from_port == r.to_port && r.referenced_security_group_id == null
    ])
    error_message = "Public listener rules must be single TCP ports from IPv4 anywhere and nothing else."
  }
}
run "public_ingress_egress_only_to_private_pod_ports" {
  command = plan
  assert {
    condition     = length(aws_vpc_security_group_egress_rule.to_ingress_pods) == 6
    error_message = "Expected one egress rule per private subnet and target port (2 x 3)."
  }
  assert {
    condition = alltrue([
      for r in aws_vpc_security_group_egress_rule.to_ingress_pods :
      contains(["10.42.16.0/20", "10.42.32.0/20"], r.cidr_ipv4) && contains([80, 443, 8081], r.from_port) && r.from_port == r.to_port && r.ip_protocol == "tcp"
    ])
    error_message = "NLB egress may reach only the private subnets on the ingress traffic and health-check ports."
  }
  assert {
    condition     = !anytrue([for r in aws_vpc_security_group_egress_rule.to_ingress_pods : r.cidr_ipv4 == "0.0.0.0/0"])
    error_message = "The NLB group must not have internet-wide egress."
  }
}
run "reject_public_ssh_listener" {
  command = plan
  variables { public_listener_ports = [22, 443] }
  expect_failures = [var.public_listener_ports]
}
run "reject_admin_port_as_ingress_target" {
  command = plan
  variables { ingress_target_ports = [443, 3389] }
  expect_failures = [var.ingress_target_ports]
}
run "flow_log_role_bounded" {
  command = plan
  assert {
    condition     = aws_iam_role.flow.permissions_boundary == "arn:aws:iam::111111111111:policy/finsight-test-workload-boundary"
    error_message = "The flow-log role must carry the FinSight workload boundary."
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
