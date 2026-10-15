"""Offline checks for the Argo CD GitOps layout (G08).

Run with scripts/validate-gitops.ps1, which provides helm, kustomize (the version Argo CD v3.5.4
bundles), kubeconform and PyYAML in a pinned container. Chart pulls and schema downloads need the
network; nothing touches a cluster or AWS.
"""

from __future__ import annotations

import base64
import copy
import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

yaml = pytest.importorskip("yaml")
for _tool in ("helm", "kustomize", "kubeconform"):
    if shutil.which(_tool) is None:
        pytest.skip(
            f"{_tool} is not on PATH; use scripts/validate-gitops.ps1", allow_module_level=True
        )

REPO = Path(__file__).resolve().parents[2]
GITOPS = REPO / "gitops"
REPO_URL = "https://github.com/Fer-as/finsight-eks-data-platform.git"
IN_CLUSTER = "https://kubernetes.default.svc"
KUBERNETES_VERSION = "1.36.0"
CACHE = Path(os.environ.get("GITOPS_CACHE", REPO / ".cache" / "gitops-validation"))
CRD_SCHEMAS = (
    "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/"
    "{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
)
SAMPLE_REGISTRY = "000000000000.dkr.ecr.eu-west-2.amazonaws.com"
SAMPLE = {
    "__VPC_ID__": "vpc-0123456789abcdef0",
    "__HOSTED_ZONE_ID__": "Z0SAMPLEZONE0000",
    "__PUBLIC_INGRESS_SECURITY_GROUP_ID__": "sg-0123456789abcdef0",
    "__API_REPOSITORY_URL__": f"{SAMPLE_REGISTRY}/finsight-dev/api",
    "__FRONTEND_REPOSITORY_URL__": f"{SAMPLE_REGISTRY}/finsight-dev/frontend",
    "__ETL_REPOSITORY_URL__": f"{SAMPLE_REGISTRY}/finsight-dev/etl",
}
DIGEST = "sha256:" + "a" * 64
# Must be applied (and Healthy) before: the key's Application.
DEPENDS_ON = {
    "aws-load-balancer-controller": ["cert-manager"],
    "cluster-issuers": ["cert-manager"],
    # Webhook certificate from cert-manager; its CRDs back the NGINX and FinSight monitors.
    "monitoring": ["cert-manager"],
    "nginx-ingress": ["aws-load-balancer-controller", "monitoring"],
    "external-dns": ["nginx-ingress"],
    "finsight": [
        "cert-manager",
        "aws-load-balancer-controller",
        "cluster-issuers",
        "nginx-ingress",
        "external-dns",
        "monitoring",
    ],
}


def load(path: Path):
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def load_all(text: str) -> list[dict]:
    return [doc for doc in yaml.safe_load_all(text) if doc]


def run(*args: str, cwd: Path | None = None) -> str:
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        raise AssertionError(f"{' '.join(args[:3])} failed:\n{result.stderr}{result.stdout}")
    return result.stdout


def kubeconform(manifests: str, tmp_path: Path) -> None:
    target = tmp_path / "manifests.yaml"
    target.write_text(manifests, encoding="utf-8")
    (CACHE / "schemas").mkdir(parents=True, exist_ok=True)
    run(
        "kubeconform",
        "-strict",
        "-summary",
        "-kubernetes-version",
        KUBERNETES_VERSION,
        "-cache",
        str(CACHE / "schemas"),
        "-schema-location",
        "default",
        "-schema-location",
        CRD_SCHEMAS,
        "-skip",
        "CustomResourceDefinition",
        str(target),
    )


def child_files() -> list[Path]:
    return [GITOPS / entry for entry in load(GITOPS / "kustomization.yaml")["resources"]]


def children() -> dict[str, dict]:
    return {app["metadata"]["name"]: app for app in map(load, child_files())}


def root_application() -> dict:
    rendered = os.environ.get("ROOT_RENDERED")
    if rendered:
        return load(Path(rendered))
    text = (GITOPS / "argocd" / "root-application.yaml").read_text(encoding="utf-8")
    for token, value in SAMPLE.items():
        text = text.replace(token, value)
    return yaml.safe_load(text)


def wave(app: dict) -> int:
    return int(app["metadata"]["annotations"]["argocd.argoproj.io/sync-wave"])


def sources(app: dict) -> list[dict]:
    return app["spec"].get("sources") or [app["spec"]["source"]]


def build_root(tmp_path: Path, gitops: Path = GITOPS) -> list[dict]:
    """kustomize build of gitops/ with the root Application's patches, as Argo CD runs it."""
    workdir = tmp_path / "gitops"
    shutil.copytree(gitops, workdir)
    kustomization = load(workdir / "kustomization.yaml")
    kustomization["patches"] = copy.deepcopy(
        root_application()["spec"]["source"]["kustomize"]["patches"]
    )
    (workdir / "kustomization.yaml").write_text(yaml.safe_dump(kustomization), encoding="utf-8")
    return load_all(run("kustomize", "build", str(workdir)))


def chart_dir(source: dict) -> Path:
    name, version = source["chart"], source["targetRevision"]
    target = CACHE / "charts" / f"{name}-{version}"
    if not (target / name / "Chart.yaml").exists():
        target.mkdir(parents=True, exist_ok=True)
        repo = source["repoURL"]
        if "://" not in repo:  # Helm OCI repository (declared with enableOCI in Argo CD)
            run(
                "helm",
                "pull",
                f"oci://{repo}/{name}",
                "--version",
                version,
                "--untar",
                "--untardir",
                str(target),
            )
        else:
            run(
                "helm",
                "pull",
                name,
                "--repo",
                repo,
                "--version",
                version,
                "--untar",
                "--untardir",
                str(target),
            )
    return target / name


def render(app: dict, values_override: dict[str, Path] | None = None) -> str:
    """helm template an Application the way Argo CD's repo-server does."""
    srcs = sources(app)
    helm_source = next(s for s in srcs if "helm" in s)
    if "chart" in helm_source:
        chart = chart_dir(helm_source)
        refs = {f"${s['ref']}": REPO for s in srcs if "ref" in s}
        files = []
        for value_file in helm_source["helm"].get("valueFiles", []):
            ref, _, rest = value_file.partition("/")
            files.append(refs[ref] / rest)
    else:
        chart = REPO / helm_source["path"]
        files = [chart / f for f in helm_source["helm"].get("valueFiles", [])]
    if values_override:
        files = [values_override.get(f.name, f) for f in files]
    args = [
        "helm",
        "template",
        helm_source["helm"].get("releaseName", app["metadata"]["name"]),
        str(chart),
        "--namespace",
        app["spec"]["destination"]["namespace"],
        "--kube-version",
        KUBERNETES_VERSION,
    ]
    for value_file in files:
        args += ["-f", str(value_file)]
    for parameter in helm_source["helm"].get("parameters", []):
        flag = "--set-string" if parameter.get("forceString") else "--set"
        args += [flag, f"{parameter['name']}={parameter['value']}"]
    return run(*args)


@pytest.fixture(scope="module")
def built(tmp_path_factory) -> dict[str, dict]:
    return {a["metadata"]["name"]: a for a in build_root(tmp_path_factory.mktemp("root"))}


def test_kustomization_lists_every_application_manifest():
    on_disk = sorted(p.relative_to(GITOPS).as_posix() for p in GITOPS.rglob("application.yaml"))
    listed = sorted(p.relative_to(GITOPS).as_posix() for p in child_files())
    assert listed == on_disk
    assert set(children()) == set(DEPENDS_ON) | {"cert-manager"}


@pytest.mark.parametrize("path", child_files(), ids=lambda p: p.parent.name)
def test_child_application_definition(path: Path):
    app = load(path)
    assert app["apiVersion"] == "argoproj.io/v1alpha1" and app["kind"] == "Application"
    assert app["metadata"]["namespace"] == "argocd"
    assert "finalizers" not in app["metadata"], "deletion of a child must not cascade by default"
    spec = app["spec"]
    assert spec["project"] == "default"
    assert spec["destination"]["server"] == IN_CLUSTER
    automated = spec["syncPolicy"]["automated"]
    assert automated["prune"] is True and automated["selfHeal"] is True
    assert isinstance(wave(app), int)
    for source in sources(app):
        if "chart" in source:
            assert re.fullmatch(r"v?\d+\.\d+\.\d+", source["targetRevision"]), (
                "chart must be pinned"
            )
            for value_file in source["helm"].get("valueFiles", []):
                assert value_file.startswith("$values/")
                assert (REPO / value_file.removeprefix("$values/")).is_file(), value_file
            if source["helm"].get("valueFiles"):
                assert any(s.get("ref") == "values" for s in sources(app))
        else:
            assert source["repoURL"] == REPO_URL and source["targetRevision"] == "main"
            if "path" in source:
                assert (REPO / source["path"] / "Chart.yaml").is_file()
                for value_file in source.get("helm", {}).get("valueFiles", []):
                    assert (REPO / source["path"] / value_file).is_file(), value_file


@pytest.mark.parametrize("chart", ["apps/finsight", "platform/cluster-issuers"])
def test_repository_charts_lint(chart):
    values = {
        "apps/finsight": [
            "--set",
            "api.image.repository=r/api",
            "--set",
            "api.image.tag=t",
            "--set",
            "frontend.image.repository=r/frontend",
            "--set",
            "frontend.image.tag=t",
        ],
        "platform/cluster-issuers": ["--set", "route53.hostedZoneID=Z0SAMPLEZONE0000"],
    }[chart]
    run(
        "helm",
        "lint",
        "--strict",
        str(GITOPS / chart),
        "--kube-version",
        KUBERNETES_VERSION,
        *values,
    )


def test_sync_waves_respect_dependencies():
    apps = children()
    for name, prerequisites in DEPENDS_ON.items():
        for prerequisite in prerequisites:
            assert wave(apps[prerequisite]) < wave(apps[name]), f"{prerequisite} before {name}"


def test_argocd_waits_for_child_health_between_waves():
    values = load(GITOPS / "argocd" / "values.yaml")
    assert "resource.customizations.health.argoproj.io_Application" in values["configs"]["cm"]


def test_root_application_definition():
    root = load(GITOPS / "argocd" / "root-application.yaml")
    spec = root["spec"]
    assert root["metadata"]["namespace"] == "argocd"
    assert spec["source"]["repoURL"] == REPO_URL and spec["source"]["targetRevision"] == "main"
    assert spec["source"]["path"] == "gitops"
    assert spec["syncPolicy"]["automated"] == {"prune": True, "selfHeal": True}
    targets = {p["target"]["name"] for p in spec["source"]["kustomize"]["patches"]}
    assert targets <= set(children())
    text = (GITOPS / "argocd" / "root-application.yaml").read_text(encoding="utf-8")
    assert set(re.findall(r"__[A-Z_]+__", text)) == set(SAMPLE)


def test_root_build_injects_every_value(built):
    assert set(built) == set(children())
    text = yaml.safe_dump(list(built.values()))
    assert "REPLACE_WITH" not in text and not re.search(r"__[A-Z_]+__", text)
    params = {
        name: {
            p["name"]: p["value"]
            for p in next(s for s in sources(app) if "helm" in s)["helm"].get("parameters", [])
        }
        for name, app in built.items()
    }
    assert params["aws-load-balancer-controller"]["vpcId"] == SAMPLE["__VPC_ID__"]
    assert params["cluster-issuers"]["route53.hostedZoneID"] == SAMPLE["__HOSTED_ZONE_ID__"]
    assert params["external-dns"]["extraArgs.zone-id-filter"] == SAMPLE["__HOSTED_ZONE_ID__"]
    prefix = r"controller.service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-"
    sg = params["nginx-ingress"][prefix + "security-groups"]
    assert sg == SAMPLE["__PUBLIC_INGRESS_SECURITY_GROUP_ID__"]
    assert params["finsight"] == {
        "api.image.repository": SAMPLE["__API_REPOSITORY_URL__"],
        "frontend.image.repository": SAMPLE["__FRONTEND_REPOSITORY_URL__"],
        "etl.image.repository": SAMPLE["__ETL_REPOSITORY_URL__"],
    }


def test_root_build_changes_only_parameter_values(built):
    for name, original in children().items():
        strip = lambda app: [  # noqa: E731
            {k: v for k, v in s.get("helm", {}).items() if k != "parameters"}
            | {"_": {k: v for k, v in s.items() if k != "helm"}}
            for s in sources(app)
        ]
        assert strip(built[name]) == strip(original)
        assert built[name]["metadata"] == original["metadata"]
        assert built[name]["spec"]["syncPolicy"] == original["spec"]["syncPolicy"]


def test_root_patch_refuses_a_changed_child(tmp_path):
    changed = tmp_path / "changed"
    shutil.copytree(GITOPS, changed)
    finsight = changed / "apps" / "finsight" / "application.yaml"
    app = load(finsight)
    app["spec"]["source"]["helm"]["parameters"].reverse()
    finsight.write_text(yaml.safe_dump(app), encoding="utf-8")
    with pytest.raises(AssertionError, match="testing value /spec/source/helm/parameters failed"):
        build_root(tmp_path / "build", changed)


def test_root_and_children_match_kubernetes_and_argocd_schemas(built, tmp_path):
    root = root_application()
    manifests = yaml.safe_dump_all([root, *built.values()])
    kubeconform(manifests, tmp_path)


@pytest.mark.parametrize("name", sorted(DEPENDS_ON) + ["cert-manager"])
def test_each_application_renders_with_its_values(name, built, tmp_path):
    app = built[name]
    override = {}
    if name == "finsight":
        tags = load(GITOPS / "apps" / "finsight" / "image-tags.yaml")
        for component in ("api", "frontend"):
            tags[component]["image"] = {"tag": "0" * 40, "digest": DIGEST}
        override["image-tags.yaml"] = tmp_path / "image-tags.yaml"
        override["image-tags.yaml"].write_text(yaml.safe_dump(tags), encoding="utf-8")
    manifests = render(app, override)
    kubeconform(manifests, tmp_path)
    assert "REPLACE_WITH" not in manifests


def test_finsight_consumes_image_tags_after_values(built, tmp_path):
    app = built["finsight"]
    assert app["spec"]["source"]["helm"]["valueFiles"] == ["values.yaml", "image-tags.yaml"]
    assert app["spec"]["destination"]["namespace"] == "finsight"
    tags = load(GITOPS / "apps" / "finsight" / "image-tags.yaml")
    tags["api"]["image"] = {"tag": "1" * 40, "digest": DIGEST}
    tags["frontend"]["image"] = {"tag": "2" * 40, "digest": ""}
    override = tmp_path / "image-tags.yaml"
    override.write_text(yaml.safe_dump(tags), encoding="utf-8")
    deployments = {
        d["metadata"]["name"]: d
        for d in load_all(render(app, {"image-tags.yaml": override}))
        if d["kind"] == "Deployment"
    }
    image = lambda n: deployments[n]["spec"]["template"]["spec"]["containers"][0]["image"]  # noqa: E731
    assert image("finsight-api") == f"{SAMPLE['__API_REPOSITORY_URL__']}@{DIGEST}"
    assert image("finsight-frontend") == f"{SAMPLE['__FRONTEND_REPOSITORY_URL__']}:{'2' * 40}"
    assert all(d["metadata"]["namespace"] == "finsight" for d in deployments.values())


def test_finsight_does_not_render_without_published_images(built, tmp_path):
    # Before the pipeline's first image pull request, image-tags.yaml has no tags or digests.
    tags = load(GITOPS / "apps" / "finsight" / "image-tags.yaml")
    for component in tags.values():
        component["image"] = {"tag": "", "digest": ""}
    empty = tmp_path / "image-tags.yaml"
    empty.write_text(yaml.safe_dump(tags), encoding="utf-8")
    with pytest.raises(AssertionError, match="image.tag or image.digest is required"):
        render(built["finsight"], {"image-tags.yaml": empty})


def test_committed_image_tags_are_published_digests(built):
    tags = load(GITOPS / "apps" / "finsight" / "image-tags.yaml")
    for component in ("api", "frontend", "etl"):
        image = tags[component]["image"]
        assert re.fullmatch(r"[0-9a-f]{40}", image["tag"]), component
        assert re.fullmatch(r"sha256:[0-9a-f]{64}", image["digest"]), component
    images = {
        c["image"]
        for d in load_all(render(built["finsight"]))
        if d["kind"] in ("Deployment", "Job")
        for c in d["spec"]["template"]["spec"]["containers"]
    }
    for component in ("api", "frontend", "etl"):
        repository = SAMPLE[f"__{component.upper()}_REPOSITORY_URL__"]
        assert f"{repository}@{tags[component]['image']['digest']}" in images, component


def test_pipeline_writes_the_file_argocd_reads_and_never_deploys():
    workflow = (REPO / ".github" / "workflows" / "app.yml").read_text(encoding="utf-8")
    assert "gitops/apps/finsight/image-tags.yaml" in workflow
    assert "kubectl" not in workflow
    for trigger in ("pull_request", "push"):
        paths = load(REPO / ".github" / "workflows" / "app.yml")[True][trigger]["paths"]
        assert not any(
            p.startswith("gitops/apps/finsight/image-tags") or p in ("gitops/**", "gitops/apps/**")
            for p in paths
        )


def test_argocd_install_renders(tmp_path):
    values = GITOPS / "argocd" / "values.yaml"
    chart = chart_dir(
        {
            "chart": "argo-cd",
            "targetRevision": "10.9.7",
            "repoURL": "https://argoproj.github.io/argo-helm",
        }
    )
    assert load(chart / "Chart.yaml")["appVersion"] == "v3.5.4"
    manifests = run(
        "helm",
        "template",
        "argocd",
        str(chart),
        "--namespace",
        "argocd",
        "--kube-version",
        KUBERNETES_VERSION,
        "-f",
        str(values),
    )
    kubeconform(manifests, tmp_path)
    docs = load_all(manifests)
    kinds = {(d["kind"], d["metadata"]["name"]) for d in docs}
    assert not any("dex" in n or "notifications" in n for _, n in kinds)
    assert not any(k == "Ingress" for k, _ in kinds)
    server = next(
        d for d in docs if d["kind"] == "Service" and d["metadata"]["name"] == "argocd-server"
    )
    assert server["spec"]["type"] == "ClusterIP"
    cm = next(d for d in docs if d["kind"] == "ConfigMap" and d["metadata"]["name"] == "argocd-cm")
    assert "argoproj.io_Application" in "".join(cm["data"])
    repository = next(
        d for d in docs if d["kind"] == "Secret" and d["metadata"]["name"].endswith("nginx-charts")
    )
    fields = {k: base64.b64decode(v).decode() for k, v in repository["data"].items()}
    assert fields == {
        "enableOCI": "true",
        "name": "nginx-charts",
        "type": "helm",
        "url": "ghcr.io/nginx/charts",
    }
    assert repository["metadata"]["labels"]["argocd.argoproj.io/secret-type"] == "repository"
    for workload in (d for d in docs if d["kind"] in ("Deployment", "StatefulSet")):
        spec = workload["spec"]["template"]["spec"]
        assert workload["spec"].get("replicas", 1) == 1, workload["metadata"]["name"]
        for container in spec["containers"] + spec.get("initContainers", []):
            assert container["resources"].get("requests"), (
                f"{workload['metadata']['name']}/{container['name']}"
            )
            if container["image"].startswith("quay.io/argoproj/argocd"):
                assert container["image"].endswith(":v3.5.4")


def test_load_balancer_controller_uses_cert_manager_certificates(built):
    docs = load_all(render(built["aws-load-balancer-controller"]))
    kinds = {d["kind"] for d in docs}
    assert {"Certificate", "Issuer"} <= kinds and "IngressClass" not in kinds
    for webhook in (d for d in docs if d["kind"].endswith("WebhookConfiguration")):
        assert all("caBundle" not in w["clientConfig"] for w in webhook["webhooks"])
    args = next(d for d in docs if d["kind"] == "Deployment")["spec"]["template"]["spec"][
        "containers"
    ][0]["args"]
    assert "--cluster-name=finsight-dev" in args
    assert f"--aws-vpc-id={SAMPLE['__VPC_ID__']}" in args and "--aws-region=eu-west-2" in args
    # enableServiceMutatorWebhook: false removes the Service webhook, so only Services that opt in
    # (aws-load-balancer-type: external, as the NGINX Service does) are handled.
    webhooks = [
        w["name"]
        for d in docs
        if d["kind"] == "MutatingWebhookConfiguration"
        for w in d["webhooks"]
    ]
    assert webhooks and not any(name.startswith("mservice.") for name in webhooks)
