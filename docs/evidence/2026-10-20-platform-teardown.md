# Platform teardown (R9.5, R9.6, R12), 20 October 2026

I removed the FinSight platform in eu-west-2 on 20 October 2026, following
[runbook section 6](../infrastructure/runbook.md#6-precise-teardown-sequence) and the
[pre-teardown inventory](2026-10-20-pre-teardown-inventory.md). Each destructive step was approved
individually. IDs, the account and the hosted zone ID are omitted here; the raw records are kept
privately.

## Preconditions

- The account and Region matched the inventory, and the `kubectl` context was `finsight-dev`.
- Platform Terraform state was unchanged since the inventory, checked again immediately before the
  apply.
- The saved plan `platform-destroy-20261020.tfplan` was made from `main` at `065c928`: 0 to add,
  0 to change, 68 to destroy, all in the platform root. Bootstrap and foundation were not in it.
- No GitHub Actions run was in progress, queued or waiting for approval.

## Database backup

- Before deletion, PVC `data-finsight-postgres-0` was Bound on StorageClass `finsight-gp3`
  (EBS CSI driver, `encrypted: true`, gp3) to an encrypted 5 GiB gp3 volume, according to the
  pre-teardown inventory. The credentials came from Secret `finsight-database`.
- `pg_dump` in custom format, written inside the pod and copied with `kubectl cp`: 177,796 bytes.
  The SHA-256 matched on both ends.
- Restored into a separate, temporary database on the same server. Row counts matched the live
  database for all six tables (3 departments, 288 entries, 36 budgets, 10,000 transactions, 3 ETL
  runs, 1 migration), and the revenue total matched. The temporary database was then dropped.
- The dump is kept privately, outside Git. The data is synthetic and is also reproducible from the
  generator ([KPI check](2026-10-20-kpi-sql-check.md)).

## Sequence and results (UTC, 20 October 2026)

| Step | Action | Result |
|---|---|---|
| 1 | Deleted the root Application `finsight-root`, which had no finalizer | All 7 child Applications kept running; reconciliation from the root stopped |
| 2 | Cascade-deleted `finsight` (Argo CD resources finalizer, then delete) | Namespace empty, Ingress gone. The StatefulSet's `whenDeleted: Delete` policy removed the PVC, and the `Delete` reclaim policy removed the 5 GiB EBS volume |
| 3 | Cascade-deleted `nginx-ingress` while the AWS Load Balancer Controller was running | Within about 30 seconds the controller removed the NLB, its 2 listeners, its 2 target groups and its 2 network interfaces |
| 4 | Cascade-deleted `external-dns`, then deleted 4 Route 53 records in one change batch | The `eks` A and AAAA aliases and the `a-eks` and `aaaa-eks` TXT records were compared with the inventory, found identical, and deleted; change INSYNC. The zone keeps only its NS and SOA records |
| 5 | Cascade-deleted `cluster-issuers`, `cert-manager`, `monitoring`, then `aws-load-balancer-controller`; deleted the `argocd` namespace | The load balancer controller was removed only after AWS showed 0 load balancers, 0 target groups and 0 controller security groups. No Applications remained |
| 6 | Applied the saved plan | `Apply complete! Resources: 0 added, 0 changed, 68 destroyed.` The cluster took 3 minutes 6 seconds and the NAT gateway 1 minute |
| 7 | Read-only verification | Below |

Nothing was force-deleted, no finalizer was removed by hand, and no state lock was forced.

## Post-teardown verification (08:53 UTC)

Each count was 0:
- **Terraform:** platform state entries.
- **Compute:** EKS clusters, EC2 instances (other than terminated), launch templates.
- **Network:** NAT gateways, Elastic IPs, non-default VPCs, network interfaces outside the default
  VPC, security groups tagged for FinSight or EKS, flow logs.
- **Load balancing:** load balancers, target groups.
- **Storage:** EBS volumes, EBS snapshots.
- **Logs:** log groups under `/aws/eks/finsight-dev` and `/finsight/`.
- **IAM:** the 9 platform roles.
- **DNS:** the `eks`, `a-eks` and `aaaa-eks` records.

## Retained (verified present after teardown)

| Resource | State |
|---|---|
| State bucket | Present, versioned; bootstrap (1 version), foundation (3) and platform (23) state objects kept |
| Access-log bucket and data bucket | Present, versioned |
| Bootstrap and foundation state | 15 and 29 resources, unchanged |
| ECR `finsight-dev/api`, `etl`, `frontend` | Present, one image each |
| Foundation IAM | GitHub plan, apply and image roles; workload boundary; 4 apply policies |
| Outside Terraform | `finsight-dev-eks-admin` role, GitHub OIDC provider, hosted zone (NS and SOA) |

The retained buckets and ECR repositories keep `prevent_destroy = true`, with `force_destroy` and
`force_delete` set to false. None of these was changed, and no retained resource was in the destroy
plan.

## Cost

| | Per day |
|---|---|
| Estimate for the deployed configuration ([costs](../infrastructure/costs.md)) | about USD 10.56 |
| Actual usage, 17–18 October 2026 (Cost Explorer, before credits) | USD 10.19 |
| Expected after teardown | well under USD 0.10: S3 and ECR storage, plus the existing hosted zone at USD 0.50 a month |

Month-to-date usage to 20 October 2026 was USD 78.28, fully offset by credits. The actual cost of the
deployment window, and confirmation that charges have stopped, need Cost Explorer data 24–48 hours
after teardown. R12.4 stays open until then.
