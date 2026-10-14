# Offline unit tests with a mocked AWS provider. All run blocks use plan and create no resources.
mock_provider "aws" {}
variables {
  name       = "finsight-test"
  subnet_ids = ["subnet-private-a", "subnet-private-b"]
  config = merge(jsondecode(file("../../config/defaults.json")).eks, {
    public_access_cidrs    = ["203.0.113.10/32"]
    admin_role_arns        = ["arn:aws:iam::111111111111:role/test-admin"]
    compatibility_verified = true
  })
}
run "nodes_private_without_ssh" {
  command = plan
  assert {
    condition     = length(aws_eks_node_group.this.remote_access) == 0
    error_message = "Managed nodes must not have SSH remote access."
  }
  assert {
    condition     = aws_launch_template.node.key_name == null && length(aws_launch_template.node.network_interfaces) == 0
    error_message = "The launch template must not set an SSH key or public network interfaces."
  }
  assert {
    condition     = toset(aws_eks_node_group.this.subnet_ids) == toset(["subnet-private-a", "subnet-private-b"])
    error_message = "Nodes must run only in the supplied private subnets."
  }
  assert {
    condition     = aws_launch_template.node.metadata_options[0].http_tokens == "required" && aws_launch_template.node.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "Nodes must require IMDSv2 with a hop limit of 1, so pods cannot use node credentials."
  }
}
run "api_endpoint_restricted" {
  command = plan
  assert {
    condition = (
      aws_eks_cluster.this.vpc_config[0].endpoint_private_access &&
      toset(aws_eks_cluster.this.vpc_config[0].public_access_cidrs) == toset(["203.0.113.10/32"])
    )
    error_message = "The API must be private plus an explicit public allow-list."
  }
  assert {
    condition     = !aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions
    error_message = "The cluster creator must not get implicit admin access."
  }
}
run "reject_open_api_endpoint" {
  command = plan
  variables {
    config = merge(jsondecode(file("../../config/defaults.json")).eks, {
      public_access_cidrs    = ["0.0.0.0/0"]
      admin_role_arns        = ["arn:aws:iam::111111111111:role/test-admin"]
      compatibility_verified = true
    })
  }
  expect_failures = [var.config]
}
