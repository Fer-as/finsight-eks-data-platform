variable "name" {
  description = "Unique IAM role name."
  type        = string
}
variable "cluster_arn" {
  description = "Only this EKS cluster can assume the role through Pod Identity."
  type        = string
}
variable "namespace" {
  description = "Allowed Kubernetes namespace."
  type        = string
}
variable "service_account" {
  description = "Allowed Kubernetes service account."
  type        = string
}
variable "policy_arns" {
  description = "Managed policies attached to the role."
  type        = set(string)
  default     = []
}
variable "permissions_boundary" {
  description = "Required FinSight workload permissions boundary ARN, set on every role this module creates."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:policy/.+-workload-boundary$", var.permissions_boundary))
    error_message = "Every FinSight platform role must carry the FinSight workload permissions boundary."
  }
}
variable "inline_policy" {
  description = "Optional JSON identity policy."
  type        = string
  default     = null
}
resource "aws_iam_role" "this" {
  name                 = var.name
  permissions_boundary = var.permissions_boundary
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow", Principal = { Service = "pods.eks.amazonaws.com" },
      Action = ["sts:AssumeRole", "sts:TagSession"],
      Condition = {
        ArnEquals = { "aws:SourceArn" = var.cluster_arn },
        StringEquals = {
          "aws:RequestTag/kubernetes-namespace"       = var.namespace,
          "aws:RequestTag/kubernetes-service-account" = var.service_account
        }
      }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "this" {
  for_each   = var.policy_arns
  role       = aws_iam_role.this.name
  policy_arn = each.value
}
resource "aws_iam_role_policy" "this" {
  count  = var.inline_policy == null ? 0 : 1
  name   = "workload"
  role   = aws_iam_role.this.id
  policy = var.inline_policy
}
output "arn" {
  description = "Pod Identity role ARN; association is owned by the caller or managed add-on."
  value       = aws_iam_role.this.arn
  depends_on  = [aws_iam_role_policy_attachment.this, aws_iam_role_policy.this]
}
