variable "name" {
  description = "Project/environment resource prefix."
  type        = string
}
variable "region" {
  description = "AWS Region for the S3 gateway endpoint."
  type        = string
}
variable "config" {
  description = "Exactly two AZs and corresponding public/private IPv4 subnet CIDRs."
  type = object({
    vpc_cidr     = string, availability_zones = list(string),
    public_cidrs = list(string), private_cidrs = list(string), log_retention_days = number
  })
  validation {
    condition = (
      length(var.config.availability_zones) == 2 && length(distinct(var.config.availability_zones)) == 2 &&
      length(var.config.public_cidrs) == 2 && length(var.config.private_cidrs) == 2 &&
      alltrue([for cidr in concat([var.config.vpc_cidr], var.config.public_cidrs, var.config.private_cidrs) : can(cidrnetmask(cidr))])
    )
    error_message = "Use two distinct AZs, two public and two private IPv4 subnets."
  }
}
locals {
  zones = { for i, az in var.config.availability_zones : az => i }
  ranges = {
    for cidr in concat([var.config.vpc_cidr], var.config.public_cidrs, var.config.private_cidrs) : cidr => {
      first = sum([for i, octet in split(".", cidrhost(cidr, 0)) : tonumber(octet) * pow(256, 3 - i)])
      last  = sum([for i, octet in split(".", cidrhost(cidr, -1)) : tonumber(octet) * pow(256, 3 - i)])
    }...
  }
  vpc_range = local.ranges[var.config.vpc_cidr][0]
  subnet_ranges = [
    for cidr in concat(var.config.public_cidrs, var.config.private_cidrs) : local.ranges[cidr][0]
  ]
}
resource "aws_vpc" "this" {
  cidr_block           = var.config.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.name }
}
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-unused-default" }
  # No ingress/egress: default group is never attached to workloads.
}
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = var.name }
}
resource "aws_subnet" "public" {
  for_each                = local.zones
  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = var.config.public_cidrs[each.value]
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name}-public-${each.key}", "kubernetes.io/role/elb" = "1" }
}
resource "aws_subnet" "private" {
  for_each                = local.zones
  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = var.config.private_cidrs[each.value]
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name}-private-${each.key}", "kubernetes.io/role/internal-elb" = "1" }
}
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.name}-nat" }
}
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[var.config.availability_zones[0]].id
  tags          = { Name = var.name }
  depends_on    = [aws_internet_gateway.this]
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-public" }
}
resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}
resource "aws_route_table" "private" {
  for_each = local.zones
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "${var.name}-private-${each.key}" }
}
resource "aws_route" "nat" {
  for_each               = aws_route_table.private
  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}
resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for rt in aws_route_table.private : rt.id]
  # Identity/bucket policies authorize data access. ECR layer downloads need regional S3 too.
  tags = { Name = "${var.name}-s3" }
}
resource "aws_cloudwatch_log_group" "flow" {
  #checkov:skip=CKV_AWS_158:CloudWatch default AES-GCM encryption is retained for seven-day assessment logs; no independent key-control requirement. See docs/evidence/day2-terraform-validation.md finding LOGS-KMS.
  name              = "/finsight/${var.name}/vpc-flow"
  retention_in_days = var.config.log_retention_days
}
resource "aws_iam_role" "flow" {
  name = "${var.name}-flow-logs"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{
      Effect    = "Allow", Principal = { Service = "vpc-flow-logs.amazonaws.com" }, Action = "sts:AssumeRole",
      Condition = { ArnLike = { "aws:SourceArn" = "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:vpc-flow-log/*" } }
    }]
  })
}
data "aws_caller_identity" "current" {}
resource "aws_iam_role_policy" "flow" {
  name = "write-flow-logs"
  role = aws_iam_role.flow.id
  policy = jsonencode({
    Version = "2012-10-17", Statement = [
      {
        Effect   = "Allow",
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"],
        Resource = ["${aws_cloudwatch_log_group.flow.arn}:*"]
      },
      {
        Effect    = "Allow", Action = ["logs:DescribeLogGroups"], Resource = "*",
        Condition = { StringEquals = { "aws:RequestedRegion" = var.region } }
      }
    ]
  })
}
resource "aws_flow_log" "this" {
  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow.arn
  log_destination = aws_cloudwatch_log_group.flow.arn
  depends_on      = [aws_iam_role_policy.flow]
}
output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
  precondition {
    condition = alltrue([
      for i, range in local.subnet_ranges :
      range.first >= local.vpc_range.first && range.last <= local.vpc_range.last &&
      alltrue([for j, other in local.subnet_ranges : i == j || range.last < other.first || range.first > other.last])
    ])
    error_message = "All four subnets must be contained within the VPC and must not overlap."
  }
  precondition {
    condition     = alltrue([for az in var.config.availability_zones : can(regex("^${var.region}[a-z]$", az))])
    error_message = "Both AZs must belong to the configured Region."
  }
}
output "private_subnet_ids" {
  description = "Private subnet IDs in configured AZ order."
  value       = [for az in var.config.availability_zones : aws_subnet.private[az].id]
}
output "public_subnet_ids" {
  description = "Public subnet IDs in configured AZ order."
  value       = [for az in var.config.availability_zones : aws_subnet.public[az].id]
}
output "nat_gateway_id" {
  description = "Single NAT ID for teardown verification."
  value       = aws_nat_gateway.this.id
}
