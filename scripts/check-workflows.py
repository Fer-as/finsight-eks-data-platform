"""Security policy for the GitHub Actions workflows. Offline: reads YAML; no GitHub or AWS calls.

Every workflow:
- grants nothing at the top level (`permissions: {}`), and each job declares its own permissions;
- has no `write-all`/`read-all`, `pull_request_target` or `workflow_run` trigger;
- pins actions to a full commit SHA (or a local ./ action) and container actions to a digest;
- requests an OIDC token (`id-token: write`) only in a job bound to a protected environment;
- checks out without persisting credentials, except the one job allowed to write to the repository.

The deployment gates, which a workflow edit could otherwise weaken unnoticed:
- terraform-apply.yml: started only by workflow_dispatch; plan then apply, each only on main and
  each behind its own approval environment (dev-infrastructure, then dev-infrastructure-apply);
- terraform.yml: the plan job needs the checks, waits for dev-infrastructure and skips forks;
- app.yml: publishing needs every test and scan job, a push to main, the dev-images environment and
  IMAGE_PUBLISHING_ENABLED == 'true'; the GitOps job needs publishing.

Usage: python scripts/check-workflows.py [--self-test]. Exits 1 on any violation.
"""

import copy
import glob
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
SHA = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}$")
FORBIDDEN_TRIGGERS = {"pull_request_target", "workflow_run"}
# (workflow, job) pairs allowed to write repository contents: the GitOps image pull request.
CONTENT_WRITERS = {("app.yml", "gitops")}


def triggers(workflow: dict) -> dict:
    on = workflow.get(True, workflow.get("on"))  # PyYAML reads the key `on` as True
    if isinstance(on, str):
        return {on: None}
    if isinstance(on, list):
        return dict.fromkeys(on)
    return on or {}


def check(name: str, wf: dict) -> list[str]:
    errors = []
    err = errors.append
    if wf.get("permissions") != {}:
        err(f"{name}: top-level permissions must be {{}}")
    for trigger in FORBIDDEN_TRIGGERS & set(triggers(wf)):
        err(f"{name}: trigger {trigger} is not allowed")
    for job_name, job in (wf.get("jobs") or {}).items():
        where = f"{name} job {job_name}"
        perms = job.get("permissions")
        if not isinstance(perms, dict):
            err(f"{where}: must declare a permissions mapping")
            perms = {}
        for scope, level in perms.items():
            if level not in ("read", "write", "none"):
                err(f"{where}: permission {scope}: {level} is not read, write or none")
        if perms.get("id-token") == "write" and not job.get("environment"):
            err(f"{where}: id-token: write needs a protected environment")
        writes_contents = perms.get("contents") == "write"
        if writes_contents and (name, job_name) not in CONTENT_WRITERS:
            err(f"{where}: contents: write is not allowed here")
        for step in job.get("steps") or []:
            uses = str(step.get("uses", ""))
            if not uses or uses.startswith("./"):
                continue
            if uses.startswith("docker://"):
                if "@sha256:" not in uses:
                    err(f"{where}: container action {uses} is not pinned by digest")
            elif not SHA.match(uses):
                err(f"{where}: action {uses} is not pinned to a full commit SHA")
            if uses.startswith("actions/checkout@") and not writes_contents:
                if (step.get("with") or {}).get("persist-credentials") is not False:
                    err(f"{where}: checkout must set persist-credentials: false")
    return errors


def gates(workflows: dict) -> list[str]:
    errors = []
    err = errors.append

    def job(wf_name, job_name):
        return ((workflows.get(wf_name) or {}).get("jobs") or {}).get(job_name) or {}

    main_only = "github.ref == 'refs/heads/main'"
    apply_wf = workflows.get("terraform-apply.yml") or {}
    if set(triggers(apply_wf)) != {"workflow_dispatch"}:
        err("terraform-apply.yml: must be started only by workflow_dispatch")
    plan, apply = job("terraform-apply.yml", "plan"), job("terraform-apply.yml", "apply")
    if plan.get("environment") != "dev-infrastructure" or main_only not in str(plan.get("if", "")):
        err("terraform-apply.yml plan: must run only on main behind dev-infrastructure")
    if (
        apply.get("environment") != "dev-infrastructure-apply"
        or apply.get("needs") not in ("plan", ["plan"])
        or main_only not in str(apply.get("if", ""))
    ):
        err(
            "terraform-apply.yml apply: must need plan and run only on main behind "
            "dev-infrastructure-apply"
        )

    pr_plan = job("terraform.yml", "plan")
    if (
        pr_plan.get("needs") not in ("checks", ["checks"])
        or pr_plan.get("environment") != "dev-infrastructure"
        or "github.event.pull_request.head.repo.full_name == github.repository"
        not in str(pr_plan.get("if", ""))
    ):
        err("terraform.yml plan: must need checks, wait for dev-infrastructure and skip forks")

    publish, gitops = job("app.yml", "publish"), job("app.yml", "gitops")
    condition = str(publish.get("if", ""))
    required = ("github.event_name == 'push'", main_only, "vars.IMAGE_PUBLISHING_ENABLED == 'true'")
    needs = publish.get("needs") or []
    if (
        publish.get("environment") != "dev-images"
        or not all(part in condition for part in required)
        or not {"python", "frontend", "checkov", "images"} <= set(needs)
    ):
        err(
            "app.yml publish: must need all test and scan jobs and run only on a push to main, "
            "behind dev-images, with IMAGE_PUBLISHING_ENABLED == 'true'"
        )
    if gitops.get("needs") not in ("publish", ["publish"]):
        err("app.yml gitops: must need publish")
    return errors


def load() -> dict:
    files = sorted(glob.glob(str(ROOT / ".github" / "workflows" / "*.yml")))
    if not files:
        raise SystemExit("No workflows found")
    return {Path(f).name: yaml.safe_load(Path(f).read_text(encoding="utf-8")) for f in files}


def violations(workflows: dict) -> list[str]:
    errors = []
    for name, wf in workflows.items():
        errors += check(name, wf)
    return errors + gates(workflows)


def self_test(workflows: dict) -> int:
    """Each mutation of the real workflows must produce at least one violation."""

    def set_path(wf, path, value):
        node = wf
        for key in path[:-1]:
            node = node[key]
        node[path[-1]] = value

    def steps(wf, job):
        return wf["jobs"][job]["steps"]

    cases = {
        "top-level write permission": (
            "gitops.yml",
            lambda w: w.update(permissions={"contents": "write"}),
        ),
        "job without permissions": (
            "gitops.yml",
            lambda w: w["jobs"]["validate"].pop("permissions"),
        ),
        "write-all": (
            "gitops.yml",
            lambda w: set_path(w, ["jobs", "validate", "permissions"], {"contents": "write-all"}),
        ),
        "pull_request_target": (
            "gitops.yml",
            lambda w: w.__setitem__(True, {"pull_request_target": None}),
        ),
        "unpinned action": (
            "gitops.yml",
            lambda w: steps(w, "validate")[0].__setitem__("uses", "actions/checkout@v7"),
        ),
        "unpinned container": (
            "gitops.yml",
            lambda w: steps(w, "validate").append({"uses": "docker://alpine:3"}),
        ),
        "persisted credentials": (
            "gitops.yml",
            lambda w: steps(w, "validate")[0]["with"].__setitem__("persist-credentials", True),
        ),
        "OIDC without environment": (
            "terraform.yml",
            lambda w: w["jobs"]["plan"].pop("environment"),
        ),
        "contents write elsewhere": (
            "app.yml",
            lambda w: w["jobs"]["python"]["permissions"].__setitem__("contents", "write"),
        ),
        "apply on push": (
            "terraform-apply.yml",
            lambda w: w.__setitem__(True, {"workflow_dispatch": None, "push": None}),
        ),
        "apply without approval": (
            "terraform-apply.yml",
            lambda w: w["jobs"]["apply"].pop("environment"),
        ),
        "apply not after plan": ("terraform-apply.yml", lambda w: w["jobs"]["apply"].pop("needs")),
        "apply from any branch": (
            "terraform-apply.yml",
            lambda w: set_path(
                w, ["jobs", "apply", "if"], "needs.plan.outputs.has_changes == 'true'"
            ),
        ),
        "PR plan without checks": ("terraform.yml", lambda w: w["jobs"]["plan"].pop("needs")),
        "PR plan for forks": ("terraform.yml", lambda w: w["jobs"]["plan"].pop("if")),
        "publish without the switch": (
            "app.yml",
            lambda w: set_path(
                w,
                ["jobs", "publish", "if"],
                "github.event_name == 'push' && github.ref == 'refs/heads/main'",
            ),
        ),
        "publish before the scans": (
            "app.yml",
            lambda w: set_path(w, ["jobs", "publish", "needs"], ["python"]),
        ),
        "gitops without publish": ("app.yml", lambda w: w["jobs"]["gitops"].pop("needs")),
    }
    if violations(workflows):
        print("self-test: the committed workflows must pass before mutations are tested")
        return 1
    failed = 0
    for label, (name, mutate) in cases.items():
        mutated = copy.deepcopy(workflows)
        mutate(mutated[name])
        found = violations(mutated)
        print(f"{'caught' if found else 'MISSED'}: {label}" + (f" ({found[0]})" if found else ""))
        failed += not found
    print(f"self-test: {len(cases) - failed} of {len(cases)} violations caught")
    return 1 if failed else 0


def main() -> int:
    workflows = load()
    if "--self-test" in sys.argv:
        return self_test(workflows)
    errors = violations(workflows)
    for error in errors:
        print(f"::error::{error}")
    print(f"{len(workflows)} workflows checked; {len(errors)} violation(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
