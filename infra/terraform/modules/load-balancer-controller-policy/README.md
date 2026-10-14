# load-balancer-controller-policy

Builds the AWS Load Balancer Controller IAM policy from AWS's published policy, pinned and
scoped to FinSight's cluster, without AWS access. The platform root attaches it to the controller's
Pod Identity role through [pod-role](../pod-role).

Repository-owned module; changes are versioned by Git commit. It has no provider dependency,
so its tests run offline.

## Source

| Item | Value |
|---|---|
| Upstream | `kubernetes-sigs/aws-load-balancer-controller` |
| Release | `v3.6.0` (Helm chart `3.6.0`, image `public.ecr.aws/eks/aws-load-balancer-controller:v3.6.0`) |
| Commit | `267b5458b4c4c3066d47673a36dda275af07a6d6` (tag `v3.6.0`) |
| File | `docs/install/iam_policy.json` (commercial partition) |
| SHA-256 | `16f232c9d9f79366fe949c4550ad517a202380058a9e48d45a4e215044a20a6a` |

[iam_policy-v3.6.0.json](iam_policy-v3.6.0.json) is a byte-for-byte copy. Terraform refuses to
plan if its SHA-256 differs. `.gitattributes` keeps Git from changing its line endings.
Source: [published policy at the pinned commit](https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/267b5458b4c4c3066d47673a36dda275af07a6d6/docs/install/iam_policy.json).

## Narrowing

The upstream policy is designed for any cluster in any account. FinSight shares its account
with another project, so the module scopes it to this cluster. Statements are matched by their
exact action list; an override can only replace an unconditional statement (statements 10 and
11 share an action list). Resource types and condition keys were checked against AWS's
Service Authorization Reference (machine-readable service reference v1.4) on 14 October 2026.

| # | Upstream | FinSight |
|---|---|---|
| 2 | WAF, Shield, ACM, Cognito and server-certificate actions on `*` | Reads kept. `wafv2`/`waf-regional` Associate/Disassociate and `shield` Create/DeleteProtection **removed**: ALB and Ingress features that FinSight's NLB never uses, which upstream allows on any resource |
| 3 | Security-group ingress changes on any group | Group/rule ARNs in this account and Region; `ArnEqualsIfExists ec2:Vpc` = the cluster VPC. The group carries `ec2:Vpc`; the optional `security-group-rule` resource does not. Both resource authorizations must succeed |
| 4 | Create security groups anywhere | New group ARN in this account/Region AND the exact FinSight VPC ARN must be authorized. No creation in another project's VPC |
| 5, 8 | Creation requires a cluster tag of any value | Requires `elbv2.k8s.aws/cluster` = this cluster; group tagging uses this account/Region, LB/TG creation uses `k8s-*` NLB/TG ARNs |
| 6, 7, 10, 12 | Changes require a cluster tag of any value | Requires this cluster and this account/Region. Statement 7 also requires the exact VPC, closing the alternate tag-only Allow. ELB resources use `k8s-*` NLB/TG/listener/rule ARNs. Tag changes forbid the ownership key through `aws:TagKeys`, including deletion |
| 9 | Create/delete listeners and rules on any load balancer | `k8s-*` NLBs, listeners and rules in this account and Region, tagged for this cluster |
| 11 | Tag any listener or rule | Existing `k8s-*` NLB listeners/rules in this account/Region must already carry this cluster's tag. The ownership key cannot be changed or removed |
| 13 | AddTags during LB/TG creation | Also covers listener/rule creation. Requires AWS-supplied `elasticloadbalancing:CreateAction` and this cluster's request tag; scoped to the corresponding `k8s-*` ARNs. A direct AddTags call cannot use this grant |
| 14 | Register/deregister targets in any target group | `k8s-*` target groups in this account and Region, tagged for this cluster |
| 15 | Modify listeners, rules and certificates; `SetWebAcl` on `*` | `k8s-*` NLB listeners and rules, tagged for this cluster. `SetWebAcl` **removed**: it supports no resource-level permissions, so it could only be granted account-wide, and NLBs have no WAF |

Unchanged: 0 (ELB service-linked role, already conditioned) and 1 (read-only describes).
Security-group creation/ingress rights remain within FinSight's VPC; the controller does not
use them with the documented custom-SG settings. They are not rights to another project's VPC.

Requirements this creates, all met by FinSight's settings:

- The controller's Helm `clusterName` must equal `cluster_name`; it writes that value to the
  `elbv2.k8s.aws/cluster` tag on everything it creates.
- The `ListenerRulesTagging` feature gate must stay enabled (the v3.6.0 default), so listeners
  carry the cluster tag.
- Load balancer and target-group names must stay `k8s-*`: do not set `aws-load-balancer-name`
  or a target-group name, and use NLBs only.

Preconditions fail if the vendored file's hash changes, if any override stops matching exactly
one unconditional statement, or if the number of tag-scoped statements is not seven.
The final narrowing pass uses zero-based upstream statement positions protected by that hash.
It preserves all 16 statements. Do not update the hash without reviewing both passes.

Do not replace the existing-listener ownership check with `IfExists`: an untagged existing
listener would then pass. CreateListener/CreateRule authorize the tagged parent; their separate
AddTags checks authorize the new resource using CreateAction, without requiring a resource tag
that does not exist yet. Removal uses TagKeys, not a RequestTag absence check alone.

Tests use synthetic fixtures with a small IAM evaluator (`tests/evaluator`): FinSight's own
create, modify, delete, tag and register requests are allowed; requests against another
cluster's `k8s-*` resources, another project's ALB, another VPC or Region, WAF, Shield and Route
53 are denied; and the unmodified upstream policy is shown to allow those same unrelated
requests. The evaluator models Allow statements, wildcard ARNs and the operators used here only
(TagKeys fixtures contain one key). It does not reproduce AWS multi-resource authorization.
An additional mocked integration test in `pod-role/tests` covers an unknown VPC ID at initial
deployment; it performs no AWS operations.

## Inputs

| Input | Type | Purpose |
|---|---|---|
| `region` | `string` | Region for the narrowed ARNs. |
| `account_id` | `string` | Account for the narrowed ARNs. |
| `vpc_id` | `string` | VPC for the security-group condition. |
| `cluster_name` | `string` | EKS cluster name; the value required on the `elbv2.k8s.aws/cluster` tag. |

## Outputs

| Output | Meaning |
|---|---|
| `policy` | Policy JSON, checked against IAM's 10,240-character inline limit. |
| `source` | Controller version, commit, path and SHA-256 of the vendored file. |

Design and installation values: [load-balancer-controller.md](../../../../docs/infrastructure/load-balancer-controller.md).
Tests: [load-balancer-controller-policy.tftest.hcl](tests/load-balancer-controller-policy.tftest.hcl).
To upgrade, vendor the new release's file, update the version, commit and hash together, and
re-review the overrides.
