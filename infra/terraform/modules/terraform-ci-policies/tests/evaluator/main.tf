# Test helper: a small synthetic IAM evaluator for single-resource requests against a set of
# identity policies. Models explicit Deny over Allow, wildcard actions and ARNs, and the condition
# operators these policies use. Multi-valued context keys are comma-separated strings. It does not
# model multi-resource authorization, SCPs, session policies, resource-based policies or
# service-specific behaviour, so it is evidence about policy text, not proof of AWS decisions.
# Unknown operators never match: an unknown Allow condition fails closed, an unknown Deny never fires.
variable "policies" {
  description = "Policy JSON documents evaluated together."
  type        = list(string)
}
variable "requests" {
  description = "Synthetic requests: action, one resource ARN and the context keys present."
  type = map(object({
    action   = string
    resource = string
    context  = map(string)
  }))
}
locals {
  statements = flatten([for p in var.policies : jsondecode(p).Statement])
  matches = {
    for name, r in var.requests : name => [
      for s in local.statements : {
        effect = s.Effect
        hit = (
          anytrue([for a in flatten([s.Action]) : can(regex("^${replace(replace(lower(a), "*", ".*"), "?", ".")}$", lower(r.action)))]) &&
          anytrue([for p in flatten([s.Resource]) : can(regex("^${replace(replace(p, ".", "\\."), "*", ".*")}$", r.resource))]) &&
          alltrue([
            for op, kv in try(s.Condition, {}) : alltrue([
              for key, want in kv : (
                contains(["StringEquals", "ArnEquals"], op) ? (contains(keys(r.context), key) && anytrue([for v in split(",", lookup(r.context, key, "")) : contains(flatten([want]), v)])) :
                contains(["StringLike", "ArnLike"], op) ? (contains(keys(r.context), key) && anytrue([for w in flatten([want]) : can(regex("^${replace(replace(w, ".", "\\."), "*", ".*")}$", lookup(r.context, key, "")))])) :
                contains(["StringNotEquals", "ArnNotEquals", "StringNotEqualsIfExists", "ArnNotEqualsIfExists"], op) ? (!contains(keys(r.context), key) || !anytrue([for v in split(",", lookup(r.context, key, "")) : contains(flatten([want]), v)])) :
                contains(["StringEqualsIfExists", "ArnEqualsIfExists"], op) ? (!contains(keys(r.context), key) || contains(flatten([want]), lookup(r.context, key, ""))) :
                op == "Null" ? (tostring(want) == "true" ? !contains(keys(r.context), key) : contains(keys(r.context), key)) :
                op == "ForAnyValue:StringEquals" ? (contains(keys(r.context), key) && anytrue([for v in split(",", lookup(r.context, key, "")) : contains(flatten([want]), v)])) :
                false
              )
            ])
          ])
        )
      }
    ]
  }
  decisions = {
    for name, ms in local.matches : name => (
      !anytrue([for m in ms : m.hit && m.effect == "Deny"]) && anytrue([for m in ms : m.hit && m.effect == "Allow"])
    )
  }
}
output "decisions" {
  description = "true where an Allow matches and no Deny matches."
  value       = local.decisions
}
