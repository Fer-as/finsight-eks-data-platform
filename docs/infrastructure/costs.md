# Cost envelope: London assessment environment

Estimate dated 13 October 2026, **USD**, on-demand Linux/shared tenancy. No free-tier credits,
discounts, VAT or currency conversion assumed. Financial application reporting remains GBP;
AWS infrastructure estimates use AWS's quoted USD rates.

| Item | Rate / assumption | Approx. daily cost |
|---|---|---:|
| EKS standard-support control plane | $0.10/hour | $2.40 |
| Two m7i.large workers | 2 x $0.11655/hour | $5.59 |
| One NAT gateway | $0.05/hour | $1.20 |
| NAT processing | 1 GB/day x $0.05 | $0.05 |
| NAT public IPv4 | $0.005/hour | $0.12 |
| Worker root gp3 | 60 GB x $0.0928/GB-month; 730-hour month | $0.18 |
| CloudWatch logs | Illustrative low-volume allowance, not a quoted fixed fee | $0.10 |
| S3 and ECR | Illustrative small-data allowance | $0.05 |
| **Day 2 running baseline** | Before load balancer/application volumes | **$9.70/day** |
| Future NLB | $0.02646/hour | $0.64 |
| Future NLB capacity | Average 1 NLCU x $0.006/hour | $0.14 |
| Future NLB IPv4 | Two addresses x $0.005/hour | $0.24 |
| Future PostgreSQL/Prometheus gp3 | Additional 40 GB | $0.12 |
| **Later full demo baseline** | Low traffic, roughly $0.45/hour | **$10.84/day** |

Seven continuously running days: approximately **$67.88 Day 2** or **$75.87 full demo**.
A 730-hour full-demo month is approximately **$330** before excluded/variable costs.
A third m7i.large with 30 GB root disk adds about **$2.89/day** while running.
A second NAT plus its public IPv4 would add about **$1.32/day**, plus processing.

The **$50 AWS Budget is an alert threshold, not a spending limit**. The full demo baseline
reaches $50 in roughly 4.6 days; other account spend or higher traffic shortens that time.
A 48-72 hour demo window is approximately $22-$33 at this baseline, not a guarantee.
Schedule and approve teardown before starting billable infrastructure. No Budget resource,
billing read, spending enforcement or cost automation was created today.

NAT bytes, cross-AZ traffic (including AZ B through the single AZ A NAT), internet egress,
NLB capacity, logs, retained versions/images, snapshots and temporary upgrade nodes vary.
Service quotas or capacity failures can leave partially created billable resources.
Stopping/scaling nodes alone leaves EKS, NAT, public IP and possible load-balancer charges.
Retained data/images/state still incur small storage/request charges after platform teardown.

Rate sources: [EKS pricing](https://aws.amazon.com/eks/pricing/),
[VPC/NAT/public IPv4 pricing](https://aws.amazon.com/vpc/pricing/),
[London EC2/NAT/EBS public price catalog](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/eu-west-2/index.csv),
[London ELB public price catalog](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSELB/current/eu-west-2/index.json).
Regional catalog rates were read from public, unauthenticated pricing data; no AWS account
billing API was used. Re-estimate at approval time. Follow the [teardown runbook](runbook.md).

## Security review cost delta

The Checkov remediation adds **one retained S3 access-log bucket**, owned by bootstrap,
with no KMS key, replication, CloudTrail data-event trail, SNS/SQS/EventBridge consumer,
CloudWatch vended-log delivery or new compute. Bucket creation has no fixed bucket fee.
Direct S3 server-log delivery has no delivery or delivery-transfer charge; stored bytes
and later log access remain chargeable. See [AWS server-log pricing](https://docs.aws.amazon.com/AmazonS3/latest/userguide/ServerLogs.html).

The public [London S3 catalog](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonS3/current/eu-west-2/index.json)
was read without authentication on 13 October 2026. S3 Standard's first storage tier
(`EUW2-TimedStorage-ByteHrs`, effective 1 October 2026) is **$0.024/GB-month**.
Therefore 1 GB stored costs $0.024/month (about $0.0008/day); 10 GB costs $0.24/month.
These are total stored-byte examples, including versions, not log-volume predictions.
List/GET/analysis and any downloaded log data have additional usage-dependent charges.

Current log objects expire after 90 days by default; their noncurrent versions then age
for another 90 days before deletion. Storage can therefore persist for approximately
180 days plus lifecycle processing delay. No expiry was added to financial data or state.
The log bucket survives platform teardown; include its remaining storage in cost reviews.

At the illustrative **1 GB total stored logs** level, the daily infrastructure estimate is
the earlier baseline plus approximately $0.0008/day; the rounded $9.70/$10.84 daily figures
remain unchanged. The log storage is additional to, rather than silently absorbed into,
the existing $0.05/day general S3/ECR allowance. The $50 alert remains a threshold only.

The retained encryption choices add **no KMS charges**. Creating customer-managed symmetric
KMS keys solely to satisfy scanner preferences would typically add $1/key-month, prorated,
plus applicable request charges (commonly $0.03/10,000 requests); independent keys for each
service multiply the key charge. AWS-managed KMS keys have different key-storage billing,
so a KMS policy finding does not universally imply a $1 fee. Key administration, availability
dependencies and independent decryption authorization must also justify a switch.
No such keys or encryption changes are introduced. [AWS KMS pricing](https://aws.amazon.com/kms/pricing/).

Cross-Region replication was not added: it would add destination storage, replication
requests and applicable inter-Region transfer charges, with no defined recovery requirement
in this temporary single-Region assessment. A future production/DR design needs its own
sizing, restore testing and cost approval.
