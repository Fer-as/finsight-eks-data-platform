# EKS platform deployment evidence (G02)

Captured 2026-10-16 05:33:11Z from the operator workstation. Account IDs, IP addresses, node names and AWS resource IDs are redacted.

## Terraform apply (saved plan platform-20261015.tfplan, reviewed 68 additions)
```
module.network.aws_nat_gateway.this: Creation complete after 1m54s
module.eks.aws_eks_cluster.this: Creation complete after 8m2s
module.eks.aws_eks_addon.identity_agent: Creation complete after 25s
module.eks.aws_eks_addon.bootstrap["kube-proxy"]: Creation complete after 7s
module.eks.aws_eks_addon.bootstrap["vpc-cni"]: Creation complete after 15s
module.eks.aws_eks_node_group.this: Creation complete after 1m17s
module.eks.aws_eks_addon.workload["coredns"]: Creation complete after 14s
module.eks.aws_eks_addon.workload["aws-ebs-csi-driver"]: Creation complete after 35s
Apply complete! Resources: 68 added, 0 changed, 0 destroyed.
```
Apply ran 2026-10-16 05:18-05:31 UTC.

## Cluster, node group and add-ons (AWS API)
```
authenticationMode: API
endpointPrivate: true
endpointPublic: true
healthIssues: null
name: finsight-dev
platformVersion: eks.15
status: ACTIVE
support: STANDARD
version: '1.36'
amiType: AL2023_x86_64_STANDARD
capacityType: ON_DEMAND
healthIssues: []
instanceTypes:
- m7i-flex.large
nodegroup: finsight-dev-workers
releaseVersion: 1.36.4-20261003
scaling:
  desiredSize: 2
  maxSize: 3
  minSize: 2
status: ACTIVE
addon vpc-cni: ACTIVE / v1.22.4-eksbuild.3 / 0 (status / version / health issues)
addon kube-proxy: ACTIVE / v1.36.0-eksbuild.25 / 0 (status / version / health issues)
addon coredns: ACTIVE / v1.14.7-eksbuild.10 / 0 (status / version / health issues)
addon eks-pod-identity-agent: ACTIVE / v1.3.10-eksbuild.3 / 0 (status / version / health issues)
addon aws-ebs-csi-driver: ACTIVE / v1.66.0-eksbuild.1 / 0 (status / version / health issues)
```

## Kubernetes (kubectl via the finsight-dev-eks-admin access entry)
```
NAME                                        STATUS   ROLES    AGE     VERSION               ZONE         INSTANCE-TYPE    CAPACITYTYPE
ip-<redacted>.eu-west-2.compute.internal   Ready    <none>   3m17s   v1.36.4-eks-3b4a6ca   eu-west-2a   m7i-flex.large   ON_DEMAND
ip-<redacted>.eu-west-2.compute.internal   Ready    <none>   3m18s   v1.36.4-eks-3b4a6ca   eu-west-2b   m7i-flex.large   ON_DEMAND

NAME                                    DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR              AGE
daemonset.apps/aws-node                 2         2         2       2            2           <none>                     4m23s
daemonset.apps/ebs-csi-node             2         2         2       2            2           kubernetes.io/os=linux     2m46s
daemonset.apps/ebs-csi-node-windows     0         0         0       0            0           kubernetes.io/os=windows   2m46s
daemonset.apps/eks-pod-identity-agent   2         2         2       2            2           <none>                     4m49s
daemonset.apps/kube-proxy               2         2         2       2            2           <none>                     4m24s

NAME                                 READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/coredns              2/2     2            2           2m51s
deployment.apps/ebs-csi-controller   2/2     2            2           2m46s

NAME                                  READY   STATUS    RESTARTS   AGE
aws-node-fznhc                        2/2     Running   0          3m19s
aws-node-vmth8                        2/2     Running   0          3m20s
coredns-85c965cdfd-j57lw              1/1     Running   0          2m52s
coredns-85c965cdfd-mksvw              1/1     Running   0          2m52s
ebs-csi-controller-685585c994-77bbj   6/6     Running   0          2m47s
ebs-csi-controller-685585c994-ncrrm   6/6     Running   0          2m47s
ebs-csi-node-cr97p                    3/3     Running   0          2m47s
ebs-csi-node-qj2wx                    3/3     Running   0          2m47s
eks-pod-identity-agent-jv84p          1/1     Running   0          3m20s
eks-pod-identity-agent-tfqkc          1/1     Running   0          3m19s
kube-proxy-hkffj                      1/1     Running   0          3m20s
kube-proxy-jd2m4                      1/1     Running   0          3m19s
```
