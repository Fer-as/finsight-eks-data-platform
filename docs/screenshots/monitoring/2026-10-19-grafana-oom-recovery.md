# Grafana OOM recovery (G05), 19 October 2026

## Problem

Grafana in the `monitoring` namespace was restarting with **OOMKilled (exit code 137)**. Its container
had a memory request of 160Mi and a limit of 320Mi. Metrics Server is not installed, so `kubectl top`
usage figures were not available.

Live node allocation before the fix:

| Node | Memory requests | Memory limits |
|---|---|---|
| Node 1 (running Grafana) | 2358Mi (33%) | 5962Mi (83%) |
| Node 2 | 2358Mi (33%) | 5706Mi (80%) |

## Change

[PR #57](https://github.com/Fer-as/finsight-eks-data-platform/pull/57) changed only
`gitops/platform/monitoring/values.yaml` and was merged on 19 October 2026 at 07:14 UTC:

| Setting | Before | After |
|---|---|---|
| `grafana.resources.requests.memory` | 160Mi | 256Mi |
| `grafana.resources.limits.memory` | 320Mi | 768Mi |

`scripts/validate-gitops.ps1` passed before the merge: the renderer checks passed, and `tests/gitops`
reported 50 passed, 0 failed.

## Rollout, observed by the operator after the merge

- Argo CD reconciled the change from Git; the `monitoring` Application was Synced and Healthy.
- The new Grafana pod was 3/3 Running with **0 restarts** 21 minutes after it started.
- Grafana showed live CPU, memory, API latency and ingress traffic graphs; see the four
  `g05-*-2026-10-19.png` screenshots in this folder.

## Limitations

- Some panels on *FinSight / Service overview* show "No data", or are empty: *API 5xx ratio* and
  *Ingress p95 upstream latency by Service*. These screenshots therefore do not demonstrate error
  rates or complete upstream latency coverage.
- The zero-restart observation covers 21 minutes after the rollout; it is not a long-term stability
  measurement.
