"""Offline checks for the monitoring stack and the FinSight/NGINX metrics wiring (G05).

Run with scripts/validate-gitops.ps1 (adds promtool to the G08 toolset). Uses the same rendering
as Argo CD: each Application's chart, value files and injected parameters.
"""

from __future__ import annotations

import json
import re
import shutil
from pathlib import Path

import pytest
from test_argocd import (
    CACHE,
    DIGEST,
    GITOPS,
    KUBERNETES_VERSION,
    REPO,
    build_root,
    chart_dir,
    load,
    load_all,
    render,
    run,
)

yaml = pytest.importorskip("yaml")
if shutil.which("promtool") is None:
    pytest.skip("promtool is not on PATH; use scripts/validate-gitops.ps1", allow_module_level=True)

NODES = 2
# m7i-flex.large: 2 vCPU, 8 GiB. EKS reserves about 70m CPU and 674Mi (kube-reserved for 29 pods
# plus eviction threshold), and the VPC CNI allows 29 pods per node without prefix delegation.
NODE_CPU, NODE_MEMORY, NODE_PODS = 1.93, 7.3 * 2**30, 29
# EKS add-ons outside GitOps: aws-node, kube-proxy and EBS CSI node per node; CoreDNS and the EBS
# CSI controller twice. Estimated from their default requests.
ADDONS_CPU, ADDONS_MEMORY, ADDONS_PODS = 0.6, 0.75 * 2**30, 12
# Verified in nginx/kubernetes-ingress v5.6.3 (internal/metrics/collectors/latency.go,
# cmd/nginx-ingress/main.go) and the NGINX OSS stub_status collector.
NGINX_METRICS = {
    "nginx_ingress_controller_upstream_server_response_latency_ms_bucket",
    "nginx_ingress_controller_upstream_server_response_latency_ms_count",
    "nginx_ingress_nginx_http_requests_total",
}
CADVISOR_METRICS = {"container_cpu_usage_seconds_total", "container_memory_working_set_bytes", "up"}
DOWN_DESCRIPTION = "No finsight-api target in namespace finsight has been up for 2 minutes."
ERROR_DESCRIPTION = "10% of API requests returned 5xx over the last 5 minutes."
REQUESTS_SERIES = (
    'finsight_api_requests_total{{namespace="finsight", route="/api/x", status="{status}"}}'
)


@pytest.fixture(scope="module")
def apps(tmp_path_factory) -> dict[str, dict]:
    return {a["metadata"]["name"]: a for a in build_root(tmp_path_factory.mktemp("root"))}


@pytest.fixture(scope="module")
def monitoring(apps) -> list[dict]:
    return load_all(render(apps["monitoring"]))


@pytest.fixture(scope="module")
def finsight(apps, tmp_path_factory) -> list[dict]:
    tags = load(GITOPS / "apps" / "finsight" / "image-tags.yaml")
    for component in ("api", "frontend"):
        tags[component]["image"] = {"tag": "0" * 40, "digest": DIGEST}
    override = tmp_path_factory.mktemp("tags") / "image-tags.yaml"
    override.write_text(yaml.safe_dump(tags), encoding="utf-8")
    return load_all(render(apps["finsight"], {"image-tags.yaml": override}))


def find(docs: list[dict], kind: str, name: str | None = None) -> list[dict]:
    return [
        d for d in docs if d["kind"] == kind and (name is None or d["metadata"]["name"] == name)
    ]


def pod_specs(docs: list[dict]):
    for doc in docs:
        if doc["kind"] in ("Deployment", "StatefulSet"):
            yield doc, doc["spec"]["template"]["spec"], doc["spec"].get("replicas", 1)
        elif doc["kind"] == "DaemonSet":
            yield doc, doc["spec"]["template"]["spec"], NODES


def quantity(value: str | int | float, memory: bool) -> float:
    text = str(value)
    units = {"Ki": 2**10, "Mi": 2**20, "Gi": 2**30, "K": 1e3, "M": 1e6, "G": 1e9}
    if not memory:
        return float(text[:-1]) / 1000 if text.endswith("m") else float(text)
    for suffix, factor in units.items():
        if text.endswith(suffix):
            return float(text[: -len(suffix)]) * factor
    return float(text)


def rules_file(tmp_path: Path, rule: dict, name: str) -> Path:
    path = tmp_path / f"{name}.yaml"
    path.write_text(yaml.safe_dump({"groups": rule["spec"]["groups"]}), encoding="utf-8")
    return path


def test_monitoring_application_is_pinned_and_ordered(apps):
    app = apps["monitoring"]
    source = app["spec"]["sources"][0]
    assert (source["chart"], source["targetRevision"]) == ("kube-prometheus-stack", "91.8.2")
    assert app["spec"]["destination"]["namespace"] == "monitoring"
    assert "ServerSideApply=true" in app["spec"]["syncPolicy"]["syncOptions"]
    assert "CreateNamespace=true" in app["spec"]["syncPolicy"]["syncOptions"]


def test_stack_components_are_present_and_internal(monitoring):
    names = {(d["kind"], d["metadata"]["name"]) for d in monitoring}
    assert ("Deployment", "monitoring-grafana") in names
    assert ("Deployment", "monitoring-kube-state-metrics") in names
    assert ("DaemonSet", "monitoring-prometheus-node-exporter") in names
    assert ("Deployment", "monitoring-kube-prometheus-operator") in names
    assert len(find(monitoring, "Prometheus")) == 1
    assert not find(monitoring, "Alertmanager") and not find(monitoring, "Ingress")
    assert all(
        s["spec"].get("type", "ClusterIP") == "ClusterIP" for s in find(monitoring, "Service")
    )
    # Webhook certificates from cert-manager, not install-time hook Jobs.
    assert find(monitoring, "Certificate") and not find(monitoring, "Job")


def test_prometheus_selects_all_monitors_with_bounded_storage(monitoring):
    spec = find(monitoring, "Prometheus")[0]["spec"]
    for selector in ("serviceMonitorSelector", "podMonitorSelector", "ruleSelector"):
        assert spec[selector] == {}, f"{selector} must select monitors from every release"
    assert spec["retention"] == "2d" and spec["retentionSize"] == "3GB"
    assert spec["storage"]["emptyDir"]["sizeLimit"] == "4Gi"
    assert spec["resources"]["requests"] == {"cpu": "200m", "memory": "768Mi"}


def test_eks_control_plane_targets_and_rules_are_disabled(monitoring):
    jobs = {m["metadata"]["name"] for m in find(monitoring, "ServiceMonitor")}
    for unwanted in ("kube-etcd", "kube-scheduler", "kube-controller-manager", "kube-proxy"):
        assert not any(unwanted in j for j in jobs), unwanted
    for wanted in ("kubelet", "kube-state-metrics", "prometheus-node-exporter", "apiserver"):
        assert any(wanted in j for j in jobs), wanted
    alerts = {
        r.get("alert")
        for p in find(monitoring, "PrometheusRule")
        for g in p["spec"]["groups"]
        for r in g["rules"]
    }
    assert not alerts & {
        "KubeSchedulerDown",
        "KubeControllerManagerDown",
        "KubeProxyDown",
        "etcdMembersDown",
    }


def test_grafana_credentials_come_from_an_existing_secret(monitoring):
    grafana = find(monitoring, "Deployment", "monitoring-grafana")[0]["spec"]["template"]["spec"]
    container = next(c for c in grafana["containers"] if c["name"] == "grafana")
    env = {e["name"]: e for e in container["env"]}
    for name, key in (
        ("GF_SECURITY_ADMIN_USER", "admin-user"),
        ("GF_SECURITY_ADMIN_PASSWORD", "admin-password"),
    ):
        assert env[name]["valueFrom"]["secretKeyRef"] == {"name": "grafana-admin", "key": key}
    assert container["image"].endswith(":13.2.4")
    rendered = yaml.safe_dump_all(monitoring)
    assert "prom-operator" not in rendered, (
        "the chart's default admin password must not be rendered"
    )
    assert not any(
        s["metadata"]["name"] == "monitoring-grafana" for s in find(monitoring, "Secret")
    )
    ini = find(monitoring, "ConfigMap", "monitoring-grafana")[0]["data"]["grafana.ini"]
    assert re.search(r"\[auth\.anonymous\]\s*enabled = false", ini)
    assert re.search(r"allow_sign_up = false", ini)


def test_grafana_loads_cluster_and_finsight_dashboards(monitoring, finsight):
    grafana = find(monitoring, "Deployment", "monitoring-grafana")[0]["spec"]["template"]["spec"]
    sidecar = next(c for c in grafana["containers"] if c["name"] == "grafana-sc-dashboard")
    env = {e["name"]: e.get("value") for e in sidecar["env"]}
    assert env["LABEL"] == "grafana_dashboard" and env["NAMESPACE"] == "ALL"
    dashboards = {
        d["metadata"]["name"]
        for d in find(monitoring, "ConfigMap")
        if "grafana_dashboard" in d["metadata"].get("labels", {})
    }
    for wanted in (
        "k8s-resources-cluster",
        "k8s-resources-namespace",
        "k8s-resources-pod",
        "k8s-resources-node",
        "nodes",
        "namespace-by-pod",
    ):
        assert any(name.endswith(wanted) for name in dashboards), wanted
    configmap = find(finsight, "ConfigMap", "finsight-dashboard")[0]
    assert configmap["metadata"]["labels"]["grafana_dashboard"] == "1"
    assert json.loads(configmap["data"]["finsight.json"])["uid"] == "finsight-overview"


def test_finsight_api_is_scraped_on_its_service(finsight):
    monitor = find(finsight, "ServiceMonitor", "finsight-api")[0]
    service = find(finsight, "Service", "finsight-api")[0]
    labels = monitor["spec"]["selector"]["matchLabels"]
    assert labels.items() <= service["metadata"]["labels"].items()
    port_names = {p["name"] for p in service["spec"]["ports"]}
    assert [(e["port"], e["path"]) for e in monitor["spec"]["endpoints"]] == [("http", "/metrics")]
    assert "http" in port_names
    ingress = find(finsight, "Ingress")[0]
    paths = {p["path"] for r in ingress["spec"]["rules"] for p in r["http"]["paths"]}
    assert "/metrics" not in paths, "/metrics stays cluster-internal"


def test_nginx_exports_latency_metrics_to_a_service_monitor(apps):
    docs = load_all(render(apps["nginx-ingress"]))
    controller = find(docs, "Deployment")[0]["spec"]["template"]["spec"]["containers"][0]
    args = controller["args"]
    assert "-enable-prometheus-metrics=true" in args and "-enable-latency-metrics=true" in args
    assert "-prometheus-metrics-listen-port=9113" in args
    monitor = find(docs, "ServiceMonitor")[0]
    services = {s["metadata"]["name"]: s for s in find(docs, "Service")}
    metrics = [
        s
        for s in services.values()
        if monitor["spec"]["selector"]["matchLabels"].items()
        <= s["metadata"].get("labels", {}).items()
    ]
    assert len(metrics) == 1 and metrics[0]["spec"].get("type", "ClusterIP") == "ClusterIP"
    assert {p["port"] for p in metrics[0]["spec"]["ports"]} == {9113}
    public = [s for s in services.values() if s["spec"].get("type") == "LoadBalancer"]
    assert public and all(9113 not in {p["port"] for p in s["spec"]["ports"]} for s in public)


def test_rules_are_valid_promql(monitoring, finsight, tmp_path):
    files = [
        rules_file(tmp_path, r, f"rule-{i}")
        for i, r in enumerate(find(monitoring, "PrometheusRule") + find(finsight, "PrometheusRule"))
    ]
    assert len(files) > 10
    run("promtool", "check", "rules", *map(str, files))


def test_finsight_alerts_fire_in_promtool_unit_tests(finsight, tmp_path):
    rules = rules_file(tmp_path, find(finsight, "PrometheusRule", "finsight-api")[0], "finsight")
    tests = {
        "rule_files": [str(rules)],
        "evaluation_interval": "1m",
        "tests": [
            {
                "interval": "1m",
                "input_series": [
                    {
                        "series": 'up{job="finsight-api", namespace="finsight", instance="a"}',
                        "values": "0x10",
                    }
                ],
                "alert_rule_test": [
                    {"eval_time": "1m", "alertname": "FinSightApiDown", "exp_alerts": []},
                    {
                        "eval_time": "5m",
                        "alertname": "FinSightApiDown",
                        "exp_alerts": [
                            {
                                "exp_labels": {"severity": "critical"},
                                "exp_annotations": {
                                    "summary": "FinSight API is not being scraped successfully",
                                    "description": DOWN_DESCRIPTION,
                                },
                            }
                        ],
                    },
                ],
            },
            {
                "interval": "1m",
                "input_series": [
                    {
                        "series": 'up{job="finsight-api", namespace="finsight", instance="a"}',
                        "values": "1x10",
                    }
                ],
                "alert_rule_test": [
                    {"eval_time": "10m", "alertname": "FinSightApiDown", "exp_alerts": []}
                ],
            },
            {
                "interval": "1m",
                "input_series": [
                    {
                        "series": REQUESTS_SERIES.format(status=503),
                        "values": "0+60x20",
                    },
                    {
                        "series": REQUESTS_SERIES.format(status=200),
                        "values": "0+540x20",
                    },
                ],
                "alert_rule_test": [
                    {
                        "eval_time": "15m",
                        "alertname": "FinSightApiHighErrorRate",
                        "exp_alerts": [
                            {
                                "exp_labels": {"severity": "warning"},
                                "exp_annotations": {
                                    "summary": "More than 5% of FinSight API requests fail",
                                    "description": ERROR_DESCRIPTION,
                                },
                            }
                        ],
                    }
                ],
            },
        ],
    }
    test_file = tmp_path / "finsight-alerts.test.yaml"
    test_file.write_text(yaml.safe_dump(tests), encoding="utf-8")
    run("promtool", "test", "rules", str(test_file))


def test_dashboard_queries_parse_and_use_real_metrics(tmp_path):
    dashboard = json.loads(
        (GITOPS / "apps" / "finsight" / "dashboards" / "finsight.json").read_text(encoding="utf-8")
    )
    api_source = (REPO / "apps" / "api" / "src" / "finsight_api" / "main.py").read_text(
        encoding="utf-8"
    )
    ids = [p["id"] for p in dashboard["panels"]]
    assert len(ids) == len(set(ids)) >= 6
    rules, metric_names = [], set()
    for panel in dashboard["panels"]:
        assert panel["datasource"] == {"type": "prometheus", "uid": "${datasource}"}
        for target in panel["targets"]:
            expr = target["expr"].replace("$__rate_interval", "5m")
            rules.append(
                {"record": f"dashboard:panel_{panel['id']}_{target['refId'].lower()}", "expr": expr}
            )
            metric_names |= {m for m in re.findall(r"\b([a-z_:][a-z0-9_:]*)(?=[{\[])", expr)}
    for name in metric_names:
        if name.startswith("finsight_api_"):
            base = re.sub(r"_(bucket|count|sum)$", "", name)
            assert f'"{base}"' in api_source, f"{name} is not produced by the API"
        else:
            assert name in NGINX_METRICS | CADVISOR_METRICS, f"{name} is not a verified metric"
    path = tmp_path / "dashboard-rules.yaml"
    path.write_text(
        yaml.safe_dump({"groups": [{"name": "dashboard", "rules": rules}]}), encoding="utf-8"
    )
    run("promtool", "check", "rules", str(path))


def test_whole_cluster_requests_fit_two_workers(apps, finsight, monitoring):
    """Every GitOps workload plus Argo CD, against two m7i-flex.large workers (G05.1 sizing)."""
    argocd = chart_dir(
        {
            "chart": "argo-cd",
            "targetRevision": "10.9.7",
            "repoURL": "https://argoproj.github.io/argo-helm",
        }
    )
    renders = {
        "argocd": load_all(
            run(
                "helm",
                "template",
                "argocd",
                str(argocd),
                "--namespace",
                "argocd",
                "--kube-version",
                KUBERNETES_VERSION,
                "-f",
                str(GITOPS / "argocd" / "values.yaml"),
            )
        ),
        "finsight": finsight,
        "monitoring": monitoring,
    }
    for name in (
        "cert-manager",
        "aws-load-balancer-controller",
        "cluster-issuers",
        "nginx-ingress",
        "external-dns",
    ):
        renders[name] = load_all(render(apps[name]))
    totals = {}
    for name, docs in renders.items():
        cpu = memory = pods = 0.0
        for doc, spec, replicas in pod_specs(docs):
            requests = [c.get("resources", {}).get("requests", {}) for c in spec["containers"]]
            if name == "monitoring":
                assert all(requests), f"{doc['metadata']['name']} has a container without requests"
            cpu += replicas * sum(quantity(r.get("cpu", 0), False) for r in requests)
            memory += replicas * sum(quantity(r.get("memory", 0), True) for r in requests)
            pods += replicas
        for prometheus in find(docs, "Prometheus"):
            requests = prometheus["spec"]["resources"]["requests"]
            # Prometheus container plus the operator's config-reloader sidecar defaults.
            cpu += quantity(requests["cpu"], False) + 0.01
            memory += quantity(requests["memory"], True) + 50 * 2**20
            pods += 1
        totals[name] = (cpu, memory, pods)
    cpu, memory, pods = (sum(t[i] for t in totals.values()) for i in range(3))
    (CACHE / "sizing.json").write_text(
        json.dumps(
            {
                k: {"cpu": round(v[0], 3), "memory_mib": round(v[1] / 2**20), "pods": v[2]}
                for k, v in totals.items()
            },
            indent=1,
        ),
        encoding="utf-8",
    )
    assert cpu + ADDONS_CPU <= NODES * NODE_CPU * 0.85, f"CPU requests {cpu:.2f} cores"
    assert memory + ADDONS_MEMORY <= NODES * NODE_MEMORY * 0.85, (
        f"memory requests {memory / 2**30:.2f} GiB"
    )
    assert pods + ADDONS_PODS <= NODES * NODE_PODS * 0.85, f"{pods:.0f} pods"
