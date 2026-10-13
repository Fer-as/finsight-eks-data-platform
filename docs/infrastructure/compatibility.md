# Compatibility and version decisions

Review date: 13 October 2026. Public documentation was read without AWS account access.
No regional EKS catalog, credentials, account resources or live backend was inspected.

| Component | Decision / evidence |
|---|---|
| Terraform | 1.16.2, official Windows AMD64 package SHA-256 verified; this is a deliberate pin, not a claim of latest |
| AWS provider | 6.59.0, signed provider downloaded and all three roots validated; checksum lock files retained |
| Terraform modules | Repository-owned source; versions follow the reviewed repository commit, with no remote module HEAD references |
| EKS | 1.36, STANDARD policy; public AWS calendar lists release 2 June 2026 and standard support through 2 August 2027 |
| VPC CNI | Public managed add-on table lists 1.36 with `v1.23.1-eksbuild.1` |
| CoreDNS | Public managed add-on table lists 1.36 with `v1.14.7-eksbuild.10` |
| kube-proxy | Public managed add-on table lists 1.36 with `v1.36.0-eksbuild.21` |
| Pod Identity Agent | Exact regional managed add-on build not verified; deliberately unset |
| EBS CSI | Exact regional managed add-on build not verified; deliberately unset |
| Nodes | AL2023 x86_64, m7i.large, Kubernetes version matched; optional AMI release pin requires regional verification |
| F5 NGINX | Planned only; public matrix lists 5.6.3 / Helm 2.7.3 supporting Kubernetes 1.36; recheck before later chart pinning |

Sources: [Terraform release](https://releases.hashicorp.com/terraform/1.16.2/),
[AWS provider v6.59.0](https://github.com/hashicorp/terraform-provider-aws/tree/v6.59.0),
[EKS calendar](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html),
[VPC CNI table](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html),
[CoreDNS table](https://docs.aws.amazon.com/eks/latest/userguide/managing-coredns.html),
[kube-proxy table](https://docs.aws.amazon.com/eks/latest/userguide/managing-kube-proxy.html),
[F5 support matrix](https://docs.nginx.com/nginx-ingress-controller/technical-specifications/).

The three public pins are candidates until **all five** versions are confirmed against the
London 1.36 catalog. Public release numbers, container tags and EKS Distro releases do not
prove a managed add-on build is available in a Region. No `most_recent` data source or
unverified guessed CSI/agent build is used.

## Later read-only checks: require approval first

These commands are documentation only and were **not executed**. They read AWS APIs.
Run under an explicitly approved authenticated session, after approving account access:

```powershell
aws eks describe-cluster-versions --region eu-west-2 --cluster-versions 1.36
$addons = @("vpc-cni", "coredns", "kube-proxy", "eks-pod-identity-agent", "aws-ebs-csi-driver")
foreach ($addon in $addons) {
    aws eks describe-addon-versions --region eu-west-2 --kubernetes-version 1.36 --addon-name $addon
}
```

For each chosen pin, check `compatibilities` includes clusterVersion 1.36 and the intended
platform version, architecture includes amd64, and compute type supports EC2. Select an
actual compatible agent/CSI build; do not simply copy the greatest version string.
For CNI and CSI, inspect `describe-addon-configuration --addon-name <name> --addon-version
<exact-pin>` for service accounts and recommended permissions. Verify
`aws-node` / `ebs-csi-controller-sa` and the current IAM policies before approval.

Capture dated, reviewed output in a redacted compatibility evidence record. Update the
complete `eks.addon_versions` map in local.json and, only after review, set
`eks.compatibility_verified=true`. Recheck after version/Region changes or a long delay.
Confirm m7i.large availability in both chosen AZs, EC2 vCPU/EIP quotas, the AL2023 release and
any account service-linked-role prerequisites during the same later review.

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
