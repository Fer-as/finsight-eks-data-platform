# Bootstrap, deployment and teardown runbook

**Nothing in the AWS sections below is authorized to execute yet.** This is the future
operating procedure, not a record of commands run. No apply, destroy, backend connection,
AWS CLI or Kubernetes command was executed during Day 2.

## 1. Local preparation and review

1. Read the infrastructure README, compatibility record and cost estimate.
2. Copy `infra/terraform/config/local.json.example` to `local.json` in the same directory.
   Supply intended account, three distinct unique state/data/access-log bucket names, administrator role ARN(s), explicit
   public API /32 CIDRs, existing public zone ID/name and hostname. Never add credentials.
3. Resolve GitHub OIDC ownership. Reuse an existing account provider by ARN; create one only
   if separately confirmed absent. For creation set `create_provider=true` and
   `existing_provider_arn=""`. Configure the exact repository subject prefix and protected
   `dev-infrastructure` / `dev-images` environment names.
4. Check all subnet ranges are non-overlapping, contained in the VPC, and do not overlap
   networks that must connect later. Both chosen AZs must belong to London.
5. Run the local validation script and review Git changes. It does not need local overrides.
6. Generate ignored backend configuration locally:
   `powershell -NoProfile -File .\scripts\new-terraform-backend-config.ps1`.
   Compare all generated values against the central config. The three state keys must differ.

## 2. Explicit approval gates

Obtain approval for **read-only AWS account access first**: verify intended identity/account,
zone ownership, AZ capacity, quotas, existing GitHub provider, EKS/add-on compatibility and
AMI release. These checks are prohibited in the current local-only task. Record the results,
supply all exact add-on pins and then set `compatibility_verified=true`.

Obtain a separate provisioning approval covering account, Region, reviewed resource inventory,
IAM/admin/OIDC trust, cost/window, retention policy and intended teardown date. The $50 alert
does not enforce that date or cap charges. Plan requires live AWS reads and, once remote state
is enabled, writes/deletes its lock object: it is not part of offline validation.

Use a human deployment role with the reviewed bootstrap/foundation/platform permissions.
The created GitHub infrastructure role cannot apply. Do not add administrator access to it
to bypass a denial. A later CI apply role needs its own reviewed permissions boundary.

## 3. Bootstrap: local state first, then S3 migration

After the gates above, use Terraform 1.16.2 and an approved authenticated session. Set these
PowerShell variables from the repository root:

```powershell
$tf = (Resolve-Path .\.cache\terraform\terraform.exe).Path # or approved Terraform on PATH
$bootstrap = "infra/terraform/bootstrap"
$foundation = "infra/terraform/environments/dev/foundation"
$platform = "infra/terraform/environments/dev/platform"
```

Ensure `bootstrap/backend.tf` does **not** exist on the first bootstrap. The root then uses
local state; no S3 backend is configured yet. If resources already exist, stop and reconcile
their state/import ownership under a separate review instead of creating duplicates.

```powershell
& $tf "-chdir=$bootstrap" init -input=false
& $tf "-chdir=$bootstrap" plan -out=bootstrap.tfplan
& $tf "-chdir=$bootstrap" show bootstrap.tfplan
# Only after approval of this saved plan:
& $tf "-chdir=$bootstrap" apply bootstrap.tfplan
```

Check native process exit codes after each command and stop on failure. Review bucket
encryption, versioning, ownership, public block and TLS policy. Securely back up the generated
local state before migration; state contains infrastructure identifiers and can contain secrets.
Keep the backup out of Git, with access limited to the operator.

Bootstrap now creates the retained access-log destination and its exact source-account/bucket
delivery policy before enabling state-bucket logging. Foundation subsequently enables
data-bucket logging to the same destination. Verify state/ and data/ prefixes after source
requests and allow for delayed, best-effort delivery. Test that unrelated source buckets
cannot deliver logs and that unauthorised principals cannot read them. Do not enable
logging on the destination, or use it for state/data objects.

Then enable the S3 backend and migrate the existing state:

```powershell
Copy-Item "$bootstrap/backend.tf.example" "$bootstrap/backend.tf"
& $tf "-chdir=$bootstrap" init -migrate-state -backend-config=backend.hcl
& $tf "-chdir=$bootstrap" state list
& $tf "-chdir=$bootstrap" plan
```

Read and accept the migration prompt only after confirming destination bucket/key/account.
Do not use `-force-copy`, discard the local backup, or initialize a fresh empty replacement
state. Verify migrated resources and a no-change plan before proceeding. Backend migration
does not recreate the state bucket.

S3 native locking is configured with `use_lockfile=true`; no DynamoDB table is needed.
For each deployment identity grant bucket ListBucket with needed prefix, GetObject/PutObject
on its own state key and GetObject/PutObject/DeleteObject on that key's `.tflock` object.
State object DeleteObject is unnecessary. The plan-only CI role has state GetObject only;
it can manage only the platform lock file. Do not grant it foundation/bootstrap state access.
See [HashiCorp's S3 backend requirements](https://developer.hashicorp.com/terraform/language/backend/s3).

If migration fails, preserve both copies and compare state lineage/serial before recovery.
Never force-unlock until the lock owner/run is confirmed stopped and recovery is approved.

## 4. Foundation, then platform

Foundation owns retained objects and is not included in routine cost teardown:

```powershell
& $tf "-chdir=$foundation" init -backend-config=backend.hcl -input=false
& $tf "-chdir=$foundation" plan -out=foundation.tfplan
& $tf "-chdir=$foundation" show foundation.tfplan
# Only after approval of this saved plan:
& $tf "-chdir=$foundation" apply foundation.tfplan
```

Verify retained S3/ECR security settings and GitHub trust, then plan the expensive platform:

```powershell
& $tf "-chdir=$platform" init -backend-config=backend.hcl -input=false
& $tf "-chdir=$platform" plan -out=platform.tfplan
& $tf "-chdir=$platform" show platform.tfplan
# Only after approval of this saved plan and the running-cost window:
& $tf "-chdir=$platform" apply platform.tfplan
```

Dependency order inside platform: VPC/subnets/routes/NAT/endpoint/logging, EKS IAM/control
plane/access entries, Pod Identity Agent, CNI/kube-proxy, private managed workers, CoreDNS/CSI,
ETL identity association. Controller and worker resource failures may leave billable partial
resources; inspect the state and approved inventory before retrying or tearing down.
Never blindly re-run apply with a different account/config.

## 5. Deployment verification (not yet run)

With the approved admin role and an allowed API source address:

```powershell
$cluster = & $tf "-chdir=$platform" output -raw cluster_name
$nodeGroup = & $tf "-chdir=$platform" output -raw node_group_name
aws eks describe-cluster --region eu-west-2 --name $cluster
aws eks describe-nodegroup --region eu-west-2 --cluster-name $cluster --nodegroup-name $nodeGroup
aws eks list-addons --region eu-west-2 --cluster-name $cluster
foreach ($addon in @("vpc-cni","kube-proxy","coredns","eks-pod-identity-agent","aws-ebs-csi-driver")) {
    aws eks describe-addon --region eu-west-2 --cluster-name $cluster --addon-name $addon
}
aws eks update-kubeconfig --region eu-west-2 --name $cluster
kubectl get nodes -o wide
kubectl get nodes -L topology.kubernetes.io/zone,node.kubernetes.io/instance-type
kubectl get pods -n kube-system -o wide
```

Require cluster/node group ACTIVE, all five add-ons ACTIVE with no health issues, two Ready
m7i.large workers and healthy system pods. Count actual nodes per AZ; two subnet IDs in a
node group are not placement evidence. If uneven, document reality and investigate capacity/
ASG balancing before making resilience claims; do not arbitrarily terminate nodes.
Verify worker ENIs have no public IP, root volumes are encrypted, IMDSv2 is required,
API public CIDRs match the intended allowlist and STANDARD support is configured.
Verify outbound ECR/EKS Auth and S3 paths and test workload identity using a later authorized
test pod. Do not open API access to 0.0.0.0/0 to make a runner work.

Capture redacted plan/resource/health evidence. Later, separately approved work installs the
AWS Load Balancer Controller, F5 NGINX (subject to assessor acceptance), CertManager,
ExternalDNS, monitoring, ArgoCD and application charts. Provisioning EKS alone does not
complete the HTTPS application or assessment.

## 6. Precise teardown sequence

**Requires separate explicit teardown approval.** Routine teardown affects platform only;
retain foundation, bootstrap, existing zone, data, tagged images and Terraform state.

1. Inventory resources from the platform state and later Kubernetes controllers. Save the
   cluster name, VPC ID, node group, NAT, EIP allocation IDs, NLB/target groups, ENIs,
   PVC/PV-to-EBS mappings, snapshots and owned DNS/TXT records to an ignored secure file.
   Pause CI and ArgoCD reconciliation so deletion will not be undone.
2. If only Day 2 infrastructure exists, there are no application PVCs or load balancers:
   skip steps 3-5. Otherwise stop ETL/scheduled writers and application traffic. Back up
   PostgreSQL to retained storage and verify restore/readability. Decide explicitly which
   EBS volumes/snapshots survive; foundation retention does **not** protect cluster PVCs.
3. While ExternalDNS is still healthy, remove desired DNS sources through the approved
   manifests so it removes records it owns (including its TXT registry). Verify the exact
   hostname/challenge records are gone. With upsert-only policy, approve and remove only
   the inventoried owned records separately. Never delete the hosted zone or unrelated records.
4. Remove the F5 LoadBalancer Service while AWS Load Balancer Controller is still running.
   Wait for its finalizers, NLB, listeners/target groups and controller-owned security groups/
   ENIs to disappear in AWS. Keep the controller and cluster until cleanup succeeds.
   Do not manually strip finalizers as the first response to a stuck deletion.
5. Remove remaining applications, PVCs only where deletion was approved, then platform
   controllers/ArgoCD. Confirm intended EBS retention/reclaim behavior and record retained
   volume/snapshot IDs and costs. No later-release names are invented here: use the actual
   names and inventory from the approved manifests.
6. Review a destroy plan for the **platform root only**:

```powershell
& $tf "-chdir=$platform" plan -destroy -out=platform-destroy.tfplan
& $tf "-chdir=$platform" show platform-destroy.tfplan
# After approval of this exact saved destroy plan:
& $tf "-chdir=$platform" apply platform-destroy.tfplan
```

7. Verify platform state is empty and the inventoried cluster, managed group/EC2, root
   disks, NAT gateway, EIP, VPC/endpoints and platform log groups are gone. Independently
   inspect remaining NLBs, target groups, ENIs, unattached EBS and snapshots by recorded IDs/
   project tags; controller-created objects are not all tracked in Terraform state.
   Wait for NAT/EKS deletion to finish. Explicitly account for every retained charge.
8. Confirm foundation data bucket, ECR images, state bucket, access-log bucket and all state versions still
   exist. Recheck billing after its reporting delay; budget alerts are not proof of cleanup.

Never run foundation/bootstrap destroy for daily cost control. Retiring retained resources
requires a distinct data-loss approval, backup/restore verification and reviewed removal of
`prevent_destroy`; retire the state bucket only after all states are safely moved or archived.
Keep its logging destination until source logging is disabled, delayed deliveries have been
allowed for and the audit retention/archive decision is approved. Do not enable
`force_destroy`/`force_delete` to sidestep retention protections.
