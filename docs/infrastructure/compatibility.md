# Compatibility and version decisions

Review date: 13 October 2026. The London (`eu-west-2`) EKS version and add-on results were
obtained manually by the repository owner and reported for this record. The remaining account
checks were run the same day with approved read-only AWS CLI calls; results are summarised
below and in the [deployment readiness record](deployment-readiness.md). No AWS resource was
created or changed, and no live backend was used.

| Component | Decision / evidence |
|---|---|
| Terraform | 1.16.2, official Windows AMD64 package SHA-256 verified; this is a deliberate pin, not a claim of latest |
| AWS provider | 6.59.0, signed provider downloaded and all three roots validated; checksum lock files retained |
| Terraform modules | Repository-owned source; versions follow the reviewed repository commit, with no remote module HEAD references |
| EKS | 1.36, STANDARD policy; public AWS calendar lists release 2 June 2026 and standard support through 2 August 2027. Owner-confirmed in London: STANDARD_SUPPORT, platform `eks.14` |
| VPC CNI | `v1.22.4-eksbuild.3`, owner-confirmed London default for 1.36 |
| CoreDNS | `v1.14.7-eksbuild.10`, owner-confirmed London default for 1.36; matches the public table |
| kube-proxy | `v1.36.0-eksbuild.25`, owner-confirmed London default for 1.36 |
| Pod Identity Agent | `v1.3.10-eksbuild.3`, owner-confirmed London default for 1.36 |
| EBS CSI | `v1.66.0-eksbuild.1`, owner-confirmed London default for 1.36 |
| Nodes | AL2023 x86_64, m7i.large (x86_64, Nitro), Kubernetes version matched. Recommended London AMI release for 1.36 on 13 October 2026: `1.36.4-20261003`, root device `/dev/xvda` |
| F5 NGINX | Planned only; public matrix lists 5.6.3 / Helm 2.7.3 supporting Kubernetes 1.36; recheck before later chart pinning |

Sources: [Terraform release](https://releases.hashicorp.com/terraform/1.16.2/),
[AWS provider v6.59.0](https://github.com/hashicorp/terraform-provider-aws/tree/v6.59.0),
[EKS calendar](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html),
[VPC CNI table](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html),
[CoreDNS table](https://docs.aws.amazon.com/eks/latest/userguide/managing-coredns.html),
[kube-proxy table](https://docs.aws.amazon.com/eks/latest/userguide/managing-kube-proxy.html),
[F5 support matrix](https://docs.nginx.com/nginx-ingress-controller/technical-specifications/).

## Add-on pin recommendation

Pin all five add-ons to the London default build for Kubernetes 1.36. These are the values in
`config/defaults.json` and `config/local.json.example`.

| Add-on | Recommended pin | Previous candidate | Reason |
|---|---|---|---|
| `vpc-cni` | `v1.22.4-eksbuild.3` | `v1.23.1-eksbuild.1` (public table) | The earlier candidate is a newer minor than the regional default and was never confirmed in the London catalog. Pod networking is the highest-impact add-on, so the AWS default is preferred over the newest build. |
| `kube-proxy` | `v1.36.0-eksbuild.25` | `v1.36.0-eksbuild.21` (public table) | Same upstream 1.36.0, matching the control-plane minor. The default is four EKS builds later than the earlier candidate, so it carries AWS's later image rebuilds. |
| `coredns` | `v1.14.7-eksbuild.10` | unchanged | Public table and regional default agree. |
| `eks-pod-identity-agent` | `v1.3.10-eksbuild.3` | unset | Regional default. Required before the CNI and CSI Pod Identity associations work. |
| `aws-ebs-csi-driver` | `v1.66.0-eksbuild.1` | unset | Regional default. Supports the Pod Identity association used for `ebs-csi-controller-sa`. |

Why defaults rather than the newest available builds:

- The default is the build AWS itself installs for a new 1.36 cluster in this Region, so the
  five defaults are the combination most exercised together on platform `eks.14`.
- Newer builds were listed as available, but availability is not a recommendation. Nothing in
  this short-lived assessment environment needs a feature or fix from a newer build.
- Explicit pins keep plans repeatable. AWS moves its defaults over time, so the pins must be
  rechecked if deployment is delayed; no `most_recent` data source is used.

The owner has since confirmed all five pins against the London catalog: compatible with 1.36
and platform `eks.14`, architecture `amd64`, compute type EC2. `eks.compatibility_verified`
stays `false` in the tracked `defaults.json` and `local.json.example`; the operator sets it to
`true` only in the ignored `local.json`, as an attestation that this record has been reviewed.
Public release numbers, container tags and EKS Distro releases do not prove a managed add-on
build is available in a Region.

## Terraform review against the verified results

- `modules/eks` already constrains the cluster to 1.36 with `support_type = "STANDARD"`; no
  change needed. Platform version is AWS-assigned and is not configurable.
- The add-on pin validation accepts all five recommended strings. The create order (Pod
  Identity Agent, then CNI and kube-proxy, then nodes, then CoreDNS and CSI) is unchanged.
- Only the add-on version values changed, in `config/defaults.json` and
  `config/local.json.example`. No module, provider or lock file change is required.
- `ami_type = "AL2023_x86_64_STANDARD"` with `m7i.large` requires every pinned build to list
  `amd64`; confirmed for all five.

## EBS CSI IAM policy decision

Owner-confirmed from the London add-on configuration for `aws-ebs-csi-driver`
`v1.66.0-eksbuild.1` on 1.36: service account `ebs-csi-controller-sa`, recommended managed
policy `arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2`.

Decision: the EBS CSI role in `modules/eks` now attaches `AmazonEBSCSIDriverPolicyV2` in place
of `arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy`.

- It is the policy AWS recommends for the pinned build, so the role tracks the permissions
  that build was released against instead of the superseded policy.
- It is the only policy on the role. Nothing was added, and the older policy is not kept
  alongside it, so the change does not widen access.
- The driver controller runs on the EC2 managed nodes and calls EC2 volume and snapshot APIs;
  the policy choice does not depend on instance architecture, and no node-role change is
  needed. The node role still carries no EBS permissions.
- The policy exists in the account's partition (default version v1, dated 16 April 2026). Its
  statements were not reviewed line by line. Its contents are AWS-managed and can change
  without a Terraform diff.

Role and association, unchanged:

- Trust is limited to `pods.eks.amazonaws.com` for this cluster ARN, namespace `kube-system`
  and service account `ebs-csi-controller-sa`.
- The association is owned by the managed add-on through its `pod_identity_association`
  block. The CNI block applies only to `vpc-cni`/`aws-node`, the CSI block only to
  `aws-ebs-csi-driver`/`ebs-csi-controller-sa`, and CoreDNS and kube-proxy get none.
- The only standalone `aws_eks_pod_identity_association` is the ETL one in namespace
  `finsight`, so no service account has two associations.

Customer-managed KMS keys are not covered by either managed policy. The account's default EBS
key is the AWS-managed `aws/ebs` key, so no KMS statement is needed today; a later
StorageClass that names a customer-managed key would need a separate reviewed statement.
Account default EBS encryption is off, so later StorageClasses must set `encrypted: "true"`.
Dynamic provisioning, attach and delete remain deployment tests.

## Read-only check results

| Section | Status on 13 October 2026 |
|---|---|
| 1. Identity and Region | Passed: intended account, `eu-west-2` |
| 2. EKS platform | Passed (owner): 1.36, STANDARD_SUPPORT, `eks.14` |
| 3. Add-on compatibility | Passed (owner): all five pins, `amd64`, EC2, `eks.14` |
| 4. Add-on IAM | Passed: CNI and EBS CSI service accounts and policies (owner); all five managed policies exist |
| 5. Account IAM prerequisites | GitHub OIDC provider exists. No administrator role exists yet: see the readiness record. EKS, node group and Auto Scaling service-linked roles are absent and will be created on first use |
| 6. Instance and AMI | Passed: x86_64, Nitro; AMI release `1.36.4-20261003` |
| 7. Availability and quotas | Passed: `eu-west-2a`/`eu-west-2b` available; m7i.large offered in all four zones; vCPU quota 16 (need 4 to 6); Elastic IPs 3 of 5 used (need 1); VPCs 2 of 5; NAT quota 5 per AZ; EKS clusters 0 of 100 |
| 8. DNS and bucket names | Passed: one public, correctly delegated hosted zone; suggested bucket names unclaimed |

The quota codes in section 7 were confirmed by their returned names, apart from the vCPU
code, which the owner checked separately.

## Read-only check commands

Kept for re-running after a delay or a version change. They only read AWS APIs and create
nothing. Run them in PowerShell under an approved authenticated session, and redact the
account ID, ARNs and zone ID before saving any output.

### 1. Identity and Region

```powershell
aws sts get-caller-identity
aws configure get region
```

Confirm the account is the intended one and matches `account_id` in the local configuration.

### 2. EKS platform

```powershell
aws eks describe-cluster-versions --region eu-west-2 --cluster-versions 1.36
```

Reconfirm STANDARD_SUPPORT, the default platform version and the end of standard support date.

### 3. Add-on compatibility, architecture and compute type

```powershell
$pins = [ordered]@{
    "vpc-cni"                = "v1.22.4-eksbuild.3"
    "kube-proxy"             = "v1.36.0-eksbuild.25"
    "coredns"                = "v1.14.7-eksbuild.10"
    "eks-pod-identity-agent" = "v1.3.10-eksbuild.3"
    "aws-ebs-csi-driver"     = "v1.66.0-eksbuild.1"
}
foreach ($addon in $pins.Keys) {
    $pin = $pins[$addon]
    aws eks describe-addon-versions --region eu-west-2 --kubernetes-version 1.36 --addon-name $addon `
        --query "addons[0].addonVersions[?addonVersion=='$pin'] | [0].{version:addonVersion,architecture:architecture,computeTypes:computeTypes,compatibilities:compatibilities,requiresIamPermissions:requiresIamPermissions}"
}
```

For each pin require: a non-null result; `compatibilities` containing clusterVersion 1.36 with
`defaultVersion` true and a platform list that covers `eks.14` (or is unrestricted);
`architecture` including `amd64`; `computeTypes` including `ec2`. A null result means the pin
is not in the London catalog and must not be used.

### 4. Add-on IAM and service accounts

```powershell
aws eks describe-addon-configuration --region eu-west-2 --addon-name vpc-cni `
    --addon-version v1.22.4-eksbuild.3 --query podIdentityConfiguration
aws eks describe-addon-configuration --region eu-west-2 --addon-name aws-ebs-csi-driver `
    --addon-version v1.66.0-eksbuild.1 --query podIdentityConfiguration
```

Expect service accounts `aws-node` and `ebs-csi-controller-sa`, and recommended managed
policies matching those attached in `modules/eks`. Then confirm every referenced AWS-managed
policy exists:

```powershell
$policies = @(
    "AmazonEKSClusterPolicy", "AmazonEKS_CNI_Policy", "AmazonEBSCSIDriverPolicyV2",
    "AmazonEKSWorkerNodePolicy", "AmazonEC2ContainerRegistryPullOnly"
)
foreach ($policy in $policies) {
    aws iam get-policy --policy-arn "arn:aws:iam::aws:policy/$policy" `
        --query "Policy.{name:PolicyName,defaultVersion:DefaultVersionId,updated:UpdateDate}"
}
```

### 5. Account IAM prerequisites

```powershell
aws iam list-open-id-connect-providers
aws iam get-role --role-name REPLACE_WITH_ADMIN_ROLE_NAME --query "Role.{arn:Arn,path:Path}"
foreach ($role in @("AWSServiceRoleForAmazonEKS", "AWSServiceRoleForAmazonEKSNodegroup", "AWSServiceRoleForAutoScaling")) {
    aws iam get-role --role-name $role --query "Role.RoleName"
}
```

Use the provider list to decide between `existing_provider_arn` and `create_provider=true`
for `token.actions.githubusercontent.com`. The administrator role must exist and be an IAM
role ARN, not an STS session. A missing service-linked role (NoSuchEntity) is not a failure:
AWS creates it on first use if the deploying identity may call `iam:CreateServiceLinkedRole`;
record which are missing so the deployment role's permissions can be reviewed.

### 6. Instance architecture and compute

```powershell
aws ec2 describe-instance-types --region eu-west-2 --instance-types m7i.large `
    --query "InstanceTypes[0].{type:InstanceType,architectures:ProcessorInfo.SupportedArchitectures,vcpus:VCpuInfo.DefaultVCpus,memoryMiB:MemoryInfo.SizeInMiB,hypervisor:Hypervisor,maxEnis:NetworkInfo.MaximumNetworkInterfaces,ipv4PerEni:NetworkInfo.Ipv4AddressesPerInterface}"
aws ssm get-parameter --region eu-west-2 --query Parameter.Value --output text `
    --name /aws/service/eks/optimized-ami/1.36/amazon-linux-2023/x86_64/standard/recommended/release_version
```

Require `x86_64` and a Nitro hypervisor. The SSM public parameter gives the current AL2023
release for 1.36; record it and decide whether to set `ami_release_version`.

### 7. Node availability and quotas

```powershell
aws ec2 describe-availability-zones --region eu-west-2 `
    --query "AvailabilityZones[].{name:ZoneName,id:ZoneId,state:State,type:ZoneType}"
aws ec2 describe-instance-type-offerings --region eu-west-2 --location-type availability-zone `
    --filters Name=instance-type,Values=m7i.large --query "InstanceTypeOfferings[].Location"
aws service-quotas get-service-quota --region eu-west-2 --service-code ec2 --quota-code L-1216C47A --query "Quota.{name:QuotaName,value:Value}"
aws service-quotas get-service-quota --region eu-west-2 --service-code ec2 --quota-code L-0263D0A3 --query "Quota.{name:QuotaName,value:Value}"
aws service-quotas get-service-quota --region eu-west-2 --service-code vpc --quota-code L-F678F1CE --query "Quota.{name:QuotaName,value:Value}"
aws service-quotas get-service-quota --region eu-west-2 --service-code eks --quota-code L-1194D53C --query "Quota.{name:QuotaName,value:Value}"
aws ec2 describe-addresses --region eu-west-2 --query "length(Addresses)"
aws ec2 describe-vpcs --region eu-west-2 --query "length(Vpcs)"
aws eks list-clusters --region eu-west-2
```

Require `eu-west-2a` and `eu-west-2b` available and both offering m7i.large. The quota codes
are On-Demand Standard vCPUs, Elastic IPs, VPCs per Region and EKS clusters. Needed headroom: 6 vCPUs at the
maximum of three nodes, 1 Elastic IP, 1 VPC and 1 cluster. An offering proves the type is sold
in the AZ, not that capacity exists at launch time.

### 8. DNS and bucket names

```powershell
aws route53 get-hosted-zone --id REPLACE_WITH_ZONE_ID --query "HostedZone.{name:Name,private:Config.PrivateZone}"
foreach ($bucket in @("REPLACE_STATE_BUCKET", "REPLACE_DATA_BUCKET", "REPLACE_ACCESS_LOG_BUCKET")) {
    aws s3api head-bucket --bucket $bucket
}
```

The zone must be public and match `dns.zone_name`. For each bucket, 404 means the name is
free, 403 means another account owns it, and success means it already exists in this account
and needs a state/import decision before bootstrap.

## After the checks

Update the complete `eks.addon_versions` map in local.json if any pin changes and set
`eks.compatibility_verified=true` there only after reviewing every section above. Recheck
after version/Region changes or a long delay: AWS moves default add-on builds and AMI
releases, and these results are dated.

The initial node AMI release is AWS-selected for Kubernetes 1.36 if
`ami_release_version=null`; pin the reviewed release in the local configuration for repeatable
rollouts. The exact add-on pins and provider pin do not pin AWS-managed IAM policy contents.
STANDARD avoids extended-support pricing but allows AWS to upgrade the control plane at
the end of standard support; do not leave this assessment environment running indefinitely.

GitHub OIDC trust requires the **actual subject prefix**. Some repositories use
`repo:OWNER/REPO`; newer immutable-subject formats include owner/repository IDs. Supply the
observed prefix rather than guessing or weakening to a wildcard. This implementation appends
exact protected environment names. See [GitHub's AWS OIDC guidance](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws).

Pod Identity startup, real IAM authorization, AL2023 bootstrap, add-on health and capacity
remain deployment tests. Local Terraform validation cannot prove them.
