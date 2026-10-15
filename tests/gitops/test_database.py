"""In-cluster PostgreSQL and database initialisation for FinSight (rendered as Argo CD would)."""

from __future__ import annotations

import re

import pytest
from test_argocd import GITOPS, REPO, SAMPLE, build_root, load, load_all, render, run

yaml = pytest.importorskip("yaml")

SECRET = "finsight-database"
SECRET_KEYS = {"PGDATABASE", "PGUSER", "PGPASSWORD"}


@pytest.fixture(scope="module")
def app(tmp_path_factory) -> dict:
    return {a["metadata"]["name"]: a for a in build_root(tmp_path_factory.mktemp("root"))}[
        "finsight"
    ]


@pytest.fixture(scope="module")
def docs(app) -> list[dict]:
    return load_all(render(app))


def one(docs: list[dict], kind: str, name: str) -> dict:
    matches = [d for d in docs if d["kind"] == kind and d["metadata"]["name"] == name]
    assert len(matches) == 1, f"{kind}/{name}"
    return matches[0]


def wave(doc: dict) -> int:
    return int(doc["metadata"].get("annotations", {}).get("argocd.argoproj.io/sync-wave", "0"))


def container(doc: dict) -> dict:
    return doc["spec"]["template"]["spec"]["containers"][0]


def test_storage_class_uses_encrypted_gp3_through_ebs_csi(docs):
    storage = one(docs, "StorageClass", "finsight-gp3")
    assert storage["provisioner"] == "ebs.csi.aws.com"
    assert storage["parameters"] == {"type": "gp3", "encrypted": "true"}
    assert storage["volumeBindingMode"] == "WaitForFirstConsumer"
    claim = one(docs, "StatefulSet", "finsight-postgres")["spec"]["volumeClaimTemplates"][0]
    assert claim["spec"]["storageClassName"] == "finsight-gp3"
    assert claim["spec"]["accessModes"] == ["ReadWriteOnce"]


def test_postgres_is_pinned_and_matches_ci(docs):
    image = container(one(docs, "StatefulSet", "finsight-postgres"))["image"]
    assert re.fullmatch(r"postgres:17-alpine@sha256:[0-9a-f]{64}", image)
    workflow = (REPO / ".github" / "workflows" / "app.yml").read_text(encoding="utf-8")
    assert image in workflow, "same PostgreSQL image as the CI integration tests"


def test_postgres_runs_unprivileged_with_writable_paths_only(docs):
    spec = one(docs, "StatefulSet", "finsight-postgres")["spec"]["template"]["spec"]
    assert spec["securityContext"]["runAsNonRoot"] is True
    assert (
        spec["securityContext"]["runAsUser"] == 10070
        and spec["securityContext"]["fsGroup"] == 10070
    )
    postgres = spec["containers"][0]
    assert postgres["securityContext"]["readOnlyRootFilesystem"] is True
    mounts = {m["mountPath"] for m in postgres["volumeMounts"]}
    assert mounts == {"/var/lib/postgresql/data", "/var/run/postgresql", "/tmp"}
    env = {e["name"]: e for e in postgres["env"]}
    assert env["PGDATA"]["value"] == "/var/lib/postgresql/data/pgdata"
    assert "pg_isready" in " ".join(postgres["readinessProbe"]["exec"]["command"])


def test_database_is_internal_only(docs, app):
    service = one(docs, "Service", "finsight-postgres")
    assert service["spec"]["type"] == "ClusterIP"
    assert [p["port"] for p in service["spec"]["ports"]] == [5432]
    backends = {
        p["backend"]["service"]["name"]
        for d in docs
        if d["kind"] == "Ingress"
        for r in d["spec"]["rules"]
        for p in r["http"]["paths"]
    }
    assert "finsight-postgres" not in backends
    assert not any(
        d["kind"] == "Service" and d["spec"].get("type") in ("LoadBalancer", "NodePort")
        for d in docs
    )


def test_every_secret_reference_uses_the_documented_secret_and_keys(docs):
    keys, names = set(), set()
    for doc in docs:
        if doc["kind"] not in ("Deployment", "StatefulSet", "Job"):
            continue
        for c in doc["spec"]["template"]["spec"]["containers"]:
            for source in c.get("envFrom", []):
                names.add(source["secretRef"]["name"])
            for e in c.get("env", []):
                ref = e.get("valueFrom", {}).get("secretKeyRef")
                if ref:
                    names.add(ref["name"])
                    keys.add(ref["key"])
    assert names == {SECRET}
    assert keys == SECRET_KEYS


def test_init_job_runs_migrations_seed_and_etl_with_the_published_etl_image(docs):
    job = one(docs, "Job", "finsight-db-init")
    annotations = job["metadata"]["annotations"]
    assert annotations["argocd.argoproj.io/hook"] == "Sync"
    assert annotations["argocd.argoproj.io/hook-delete-policy"] == "BeforeHookCreation"
    init = container(job)
    tags = load(GITOPS / "apps" / "finsight" / "image-tags.yaml")
    assert init["image"] == f"{SAMPLE['__ETL_REPOSITORY_URL__']}@{tags['etl']['image']['digest']}"
    script = init["command"][-1]
    steps = ["scripts/migrate.py", "finsight_pipelines.synthetic", "finsight_pipelines.etl"]
    assert [script.index(s) for s in steps] == sorted(script.index(s) for s in steps)
    env = {e["name"]: e["value"] for e in init["env"]}
    assert env == {"PGHOST": "finsight-postgres", "PGPORT": "5432"}
    assert {m["mountPath"] for m in init["volumeMounts"]} == {"/app/data", "/tmp"}
    assert job["spec"]["template"]["spec"]["restartPolicy"] == "Never"


def test_sync_order_database_then_init_then_api(docs):
    postgres = one(docs, "StatefulSet", "finsight-postgres")
    service = one(docs, "Service", "finsight-postgres")
    job = one(docs, "Job", "finsight-db-init")
    api = one(docs, "Deployment", "finsight-api")
    assert wave(one(docs, "StorageClass", "finsight-gp3")) < wave(postgres)
    assert wave(service) == wave(postgres) < wave(job) < wave(api)
    env = {e["name"]: e["value"] for e in container(api)["env"]}
    assert env == {"PGHOST": "finsight-postgres", "PGPORT": "5432"}


def test_database_can_be_disabled(app, tmp_path):
    values = tmp_path / "off.yaml"
    values.write_text("database:\n  enabled: false\n", encoding="utf-8")
    source = app["spec"]["source"]
    args = ["helm", "template", "finsight", str(REPO / source["path"]), "--namespace", "finsight"]
    for value_file in source["helm"]["valueFiles"]:
        args += ["-f", str(REPO / source["path"] / value_file)]
    for parameter in source["helm"]["parameters"]:
        args += ["--set", f"{parameter['name']}={parameter['value']}"]
    rendered = load_all(run(*args, "-f", str(values)))
    kinds = {d["kind"] for d in rendered}
    assert not kinds & {"StatefulSet", "Job", "StorageClass"}
    api = one(rendered, "Deployment", "finsight-api")
    assert "env" not in container(api)
