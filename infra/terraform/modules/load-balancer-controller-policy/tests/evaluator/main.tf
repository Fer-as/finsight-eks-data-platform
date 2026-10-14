# Test helper: a deliberately small IAM evaluator for synthetic requests against one policy.
# Models Allow statements, exact action names, wildcard resource ARNs and the condition
# operators this policy uses (StringEquals, ArnEquals, the IfExists forms, Null and a
# single-value ForAllValues:StringNotEquals fixture for aws:TagKeys). It does not model
# explicit denies, multi-resource requests, SCPs, permission boundaries or session policies.
# Unknown operators never match, so unsupported conditions fail closed.
variable "policy" {
  description = "Policy JSON to evaluate."
  type        = string
}
variable "requests" {
  description = "Synthetic requests: action, one resource ARN and the request context keys present."
  type = map(object({
    action   = string
    resource = string
    context  = map(string)
  }))
}
locals {
  statements = jsondecode(var.policy).Statement
  decisions = {
    for name, r in var.requests : name => anytrue([
      for s in local.statements : (
        s.Effect == "Allow" &&
        contains(flatten([s.Action]), r.action) &&
        anytrue([
          for p in flatten([s.Resource]) :
          can(regex("^${replace(replace(p, ".", "\\."), "*", ".*")}$", r.resource))
        ]) &&
        alltrue([
          for op, kv in try(s.Condition, {}) : alltrue([
            for key, want in kv : (
              contains(["StringEquals", "ArnEquals"], op) ? contains(flatten([want]), lookup(r.context, key, "<absent>")) :
              contains(["ArnEqualsIfExists", "StringEqualsIfExists"], op) ? (!contains(keys(r.context), key) || contains(flatten([want]), lookup(r.context, key, ""))) :
              op == "Null" ? (tostring(want) == "true" ? !contains(keys(r.context), key) : contains(keys(r.context), key)) :
              op == "ForAllValues:StringNotEquals" ? (!contains(keys(r.context), key) || !contains(flatten([want]), lookup(r.context, key, ""))) :
              false
            )
          ])
        ])
      )
    ])
  }
}
output "decisions" {
  description = "true where some Allow statement matches the request."
  value       = local.decisions
}
