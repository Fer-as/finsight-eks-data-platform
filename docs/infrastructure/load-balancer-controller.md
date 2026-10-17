# AWS Load Balancer Controller identity

Decision record, 14 October 2026 (issue #34). Terraform defines the controller's IAM role and Pod
Identity association only. The role was applied with the platform root on 16 October 2026, and
the controller runs as an Argo CD Application (wave 1).

## Version

| Item | Pinned value | How it was checked |
|---|---|---|
| Controller | `v3.6.0`, full release of 5 October 2026 (not a pre-release) | GitHub release API |
| Source commit | `267b5458b4c4c3066d47673a36dda275af07a6d6` (annotated tag `v3.6.0`) | Tag object resolved to the commit |
| Helm chart | `aws-load-balancer-controller` `3.6.0`, appVersion `v3.6.0`, from `https://aws.github.io/eks-charts` | `helm/aws-load-balancer-controller/Chart.yaml` at the commit |
| Image | `public.ecr.aws/eks/aws-load-balancer-controller:v3.6.0` | Chart `values.yaml` at the commit |
| IAM policy | `docs/install/iam_policy.json` at the commit, SHA-256 `16f232c9d9f79366fe949c4550ad517a202380058a9e48d45a4e215044a20a6a` | Vendored byte-for-byte; Terraform checks the hash |
| Kubernetes | Upstream states "v2.5.0+ requires Kubernetes 1.22+" with no upper bound; EKS 1.36 is not named | `docs/deploy/installation.md` at the commit; confirm on the cluster |

The v3.6.0 release notes list no IAM policy change.

## Pod Identity

| Setting | Value |
|---|---|
| IAM role | `finsight-dev-aws-load-balancer-controller` (existing `pod-role` module) |
| Trust | `pods.eks.amazonaws.com` only, with `sts:AssumeRole` and `sts:TagSession`; `aws:SourceArn` equals the FinSight cluster; session tags must name namespace `kube-system` and service account `aws-load-balancer-controller` |
| Association | `aws_eks_pod_identity_association.load_balancer_controller` for `kube-system/aws-load-balancer-controller` |
| Permissions | One inline policy, validated below IAM's 10,240-character limit; no managed policies |

Upstream documents Pod Identity as its recommended option. Tests in `modules/pod-role/tests`
check the trust policy, and that a role gets no managed policies unless they are supplied.

## Permissions

The policy is AWS's published v3.6.0 policy, scoped to this cluster; the statement-by-statement
changes are in [the module README](../../infra/terraform/modules/load-balancer-controller-policy/README.md).

| Group | What it allows | Scope |
|---|---|---|
| Discovery (`ec2:Describe*`, `GetSecurityGroupsForVpc`, `elasticloadbalancing:Describe*` and similar) | Read VPC, subnet, security group, instance and load balancer state | `*`. Read-only; most do not support resource-level permissions |
| Service-linked role | `iam:CreateServiceLinkedRole` | `*`, only for `elasticloadbalancing.amazonaws.com` (the role already exists in the account) |
| Feature lookups (ACM, IAM server certificates, Cognito, WAF, Shield) | Reads only | `*`, as upstream. WAF association, Shield protection changes and `SetWebAcl` are removed |
| Security groups | Create; tag, change ingress and delete | Creation authorizes the new group AND the exact cluster VPC. Ingress only in the cluster VPC, including the alternate tag-scoped grant; group/rule ARNs restricted to this account/Region. Tagging/deletion require this cluster's tag; deletion also requires the VPC. Ownership tags cannot be changed or removed |
| Load balancers and target groups | Create, tag, modify and delete | `k8s-*` NLB/TG ARNs in this account/Region; creation must tag for this cluster; changes require this cluster's resource tag; ownership tags cannot be changed or removed |
| Listeners and rules | Create, modify, delete, tag, certificates, priorities | `k8s-*` NLB listeners/rules in this account/Region. Existing resources require this cluster's tag. Create-time tagging uses a separate CreateAction/request-tag grant |
| Targets | Register and deregister | `k8s-*` target groups in this account and Region, tagged for this cluster |

The controller has **no Route 53 permissions**: application records belong to ExternalDNS and
challenge records to cert-manager (see [dns-and-certificates.md](dns-and-certificates.md)).
Tests enforce this, and that the only IAM actions are the ELB service-linked role and
server-certificate reads.

Why scope it: this account also hosts another project's application load balancer and security
groups, and could later host another cluster running this controller. Upstream, four
statements carry no condition and seven accept a cluster tag of any value, so the controller
could have changed the other project's listeners, targets, tags, WAF association or
security-group rules, or another cluster's `k8s-*` resources. Tests built from synthetic
fixtures show the unmodified upstream policy allowing those requests and this policy refusing
them, while FinSight's own create, modify, delete, tag and register requests are still allowed.

### Checked against AWS's authorization reference

AWS's machine-readable service reference (v1.4, read 14 October 2026) gives the resource each
action is authorised on, which decides whether a narrowed statement can still be satisfied:

- `CreateListener` authorises on the **load balancer** (always tagged for the cluster at
  creation). `CreateRule`, `DeleteListener`, `ModifyListener` and listener certificate actions
  authorise on the **listener**; `DeleteRule`, `ModifyRule` and `SetRulePriorities` on the
  **rule**; `RegisterTargets` and `DeregisterTargets` on the **target group**. All of these
  resource types support `aws:ResourceTag`.
- `SetWebAcl` lists no resource types, so it can only be granted on `*`; it is removed.
- `AuthorizeSecurityGroupIngress` authorises on the **security group** (which has `ec2:Vpc`) and,
  when rules are tagged, the **security-group rule** (which does not); hence `ArnEqualsIfExists`.
  The rule-only Allow is not permission for the whole request: the group check must also
  succeed. The separate tag-scoped SG statement now requires the same VPC, so it cannot bypass
  that check. No AWS account calls or IAM simulations were used in this review.
- The v3.6.0 source tags every AWS resource it creates with `elbv2.k8s.aws/cluster` set to the
  configured cluster name, and tags listeners and rules while the `ListenerRulesTagging`
  feature gate is on (default true).

The independent 14 October review found and fixed three gaps in the initial narrowing:

1. Listener/rule tagging used two `IfExists` conditions, allowing direct tagging of an
   existing untagged resource. Existing resources now require ownership; new resources use
   `elasticloadbalancing:CreateAction` plus the exact request tag. The controller sends those
   tags with CreateListener/CreateRule when ListenerRulesTagging is enabled.
2. RequestTag absence did not protect ownership-tag deletion. `aws:TagKeys` now excludes the
   ownership key from existing-resource tag changes, while ordinary tags remain mutable.
3. Alternate Allow statements bypassed the VPC, NLB-only or Region boundaries. The tagged SG
   grant now includes the VPC; ELB write statements consistently use this account/Region's
   `k8s-*` NLB resources and target groups. SG creation now authorizes only the FinSight VPC
   and the new group in this account/Region, rather than allowing creation in other VPCs.

The ten new negative fixtures fail against the preserved initial implementation and pass
against the corrected policy. This demonstrates regression coverage in the local model, not
live AWS behavior. Authoritative references:
[ELB tag-on-create authorization](https://docs.aws.amazon.com/elasticloadbalancing/latest/userguide/tagging-resources-during-creation.html),
[IAM IfExists and set operators](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements_condition_operators.html),
[ELB action/resource definitions](https://servicereference.us-east-1.amazonaws.com/v1/elasticloadbalancing/elasticloadbalancing.json),
[EC2 action/resource definitions](https://servicereference.us-east-1.amazonaws.com/v1/ec2/ec2.json),
[pinned listener implementation](https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/267b5458b4c4c3066d47673a36dda275af07a6d6/pkg/deploy/elbv2/listener_manager.go).

## Fit with the network design (issue #7)

- **Public NLB, IP targets, custom security group.** The NGINX Service names the Terraform-owned
  `finsight-dev-public-ingress` group, so the controller attaches it at creation and creates no
  frontend group of its own.
- **Subnet discovery.** The network module tags public subnets `kubernetes.io/role/elb=1`
  and private subnets `kubernetes.io/role/internal-elb=1`. The internet-facing Service selects
  the public pair; verify the selected subnets at runtime.
- **Backend rules stay in Terraform.** With a custom frontend group, the controller adds no
  backend rules unless told to (`manage-backend-security-group-rules` defaults to false). Set
  `enableBackendSecurityGroup: false` so it creates no shared backend group either. The
  Terraform rule letting the NLB group reach pods on 80, 443 and 8081 is the only path, and the
  role gains no extra permission for it.
- **Health checks on 8081.** Set by Service annotation; the existing rules allow 8081.
- **Admission webhook.** The control plane calls the controller's webhook on TCP 9443. The
  control-plane interfaces and pods share the EKS cluster security group, whose self-rule
  allows it.
- **No instance metadata.** Nodes require IMDSv2 with hop limit 1, so pods cannot read instance
  metadata. Upstream supports supplying the Region and VPC instead; the Helm values below do so.

## Values for the Helm install (#20)

From the platform output `load_balancer_controller`:

```yaml
clusterName: finsight-dev
region: eu-west-2
vpcId: <load_balancer_controller.vpc_id>
image:
  tag: v3.6.0
serviceAccount:
  create: true
  name: aws-load-balancer-controller
  annotations: {}            # no IRSA annotation; the Pod Identity association already exists
replicaCount: 2
enableBackendSecurityGroup: false
createIngressClassResource: false    # no ALB Ingress in FinSight
enableServiceMutatorWebhook: false   # only Services that opt in are handled
```

Install chart `3.6.0` into `kube-system`, pinned, through Argo CD: implemented in G08 as
`gitops/platform/aws-load-balancer-controller` (wave 1, `enableCertManager: true` so the webhook
certificate is stable under Argo CD, with `vpcId` injected by the root Application; see
[argocd.md](argocd.md)). With the mutating webhook
off, the controller handles only Services annotated `aws-load-balancer-type: external`;
anything else stays with the default cloud provider. Upstream's release notes install CRDs from
`?ref=master` for upgrades; pin CRDs to `v3.6.0` instead.

The NGINX Service annotations are in [network-security.md](network-security.md) ("Settings the
later installs must use"). The controller-specific requirements are:
- `aws-load-balancer-type: external` must be present.
- `aws-load-balancer-name` and target-group name annotations must not be set, so names stay
  `k8s-*` and inside the narrowed permissions.

## Local validation evidence (14 October 2026, Codex review)

`scripts/validate-terraform.ps1` completed with exit 0 after the final fixes:

- Formatting passed; all three roots initialized with isolated metadata/backend disabled and
  validated. Deployed backend caches were unchanged. No infrastructure plan was run.
- 32 Terraform test runs passed: config 4, DNS 6, controller policy 5, network 10, EKS 3,
  Pod Identity 4. The last suite includes the unknown-VPC integration test with a mocked
  provider. All test runs use synthetic inputs and provider-free or mocked plan operations.
- IAM fixture decisions: 19 allowed, 27 denied. Running the expanded fixtures against the
  preserved initial policy failed on the ten new negative cases; the final policy passes.
- Checkov 3.3.27: 181 passed, 0 failed, 16 existing documented skips, 0 parsing errors.
  The scan includes the new test fixture; the count increase is not additional runtime evidence.
- Vendored SHA-256 matches a fresh download from the pinned upstream commit. Git whitespace,
  private-file integrity and sensitive-value checks passed; compatibility_verified stayed false.

The original validation script's cached-backend initialization failed with credential sources
disabled. The script now isolates root metadata with TF_DATA_DIR; no remote-state access is
needed for these checks. Earlier intermediate failures are superseded by the final successful run.

## Remaining risks and runtime checks

- **Kubernetes 1.36** is not named upstream. Confirm the controller starts cleanly and
  reconciles the NGINX Service during the deployment window (#30).
- **Scoping is FinSight-specific.** An ALB, a custom load balancer or target group name, a Helm
  `clusterName` other than `finsight-dev`, or turning off `ListenerRulesTagging` would be
  denied listener, target or tag changes. That is intended; change the module first.
- **Not provable before deployment.** The tests use a simplified evaluator (Allow statements,
  wildcard ARNs and the condition operators used here). They do not model AWS's handling of
  multi-resource requests, tag-on-create authorisation or service-specific behaviour. Watch
  the controller logs for `AccessDenied` during the deployment window; any denial is a bug in
  the scoping to fix, not a reason to widen it blindly.
- **Remaining broad permissions:** read-only describes and lookups on `*` expose metadata
  from other projects. SG creation/ingress rights within FinSight's VPC are retained from
  upstream but are not called with the documented settings. Ownership tags are an IAM
  boundary only while other authorized identities cannot falsely assign FinSight's tag.
- **AWS-managed behaviour changes** with future releases. Re-vendor, re-hash and re-review
  before upgrading the chart.
- **Runtime evidence for #30:** the controller pods run with the Pod Identity role (no node
  credentials) and log no `AccessDenied`; the NGINX NLB is `internet-facing`, uses IP targets and
  has only the `finsight-dev-public-ingress` group; its target groups are healthy on 8081; its
  name starts with `k8s-`; it, its listeners and target groups carry
  `elbv2.k8s.aws/cluster=finsight-dev`.

Proposed additions to issue #30 (prepared locally; not posted to GitHub):

- Capture the Pod Identity association, service account and redacted caller-role evidence;
  controller startup/reconciliation must work on EKS 1.36 without IMDS credentials.
- Exercise create, ordinary-tag update, target registration/deregistration and deletion of
  FinSight's NLB/listeners/TGs during the approved window. Capture controller events and logs
  with no AccessDenied, including listener AddTags during creation. Do not test writes against
  another project. Any denial needs a precise action/resource/context review.
- Confirm public subnet IDs, IP targets, the sole Terraform-owned public ingress SG, HTTP
  readiness checks on 8081, ownership tags and healthy targets. Compare SG rules before/after
  reconciliation: no controller-created groups or backend rules, webhook reachable on 9443.
- Remove the FinSight Service before platform teardown and verify its finalizer completes
  and its NLB, listeners and target groups disappear. Keep controller IAM until cleanup ends.
