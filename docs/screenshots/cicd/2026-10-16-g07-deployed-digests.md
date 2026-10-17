# G07.5/G07.6 evidence: published digests are the ones running on EKS

Captured 2026-10-16 09:49:29Z. Read-only. Registry hostname (contains the account ID) shown as <registry>.

## Pipeline
```
app.yml run 38761479287 attempt 2 (main 6e77c47): build, Trivy, publish to ECR (OIDC images role, dev-images), GitOps PR #46 opened by github-actions, merged 2026-10-15 (merge d8d1efe)
```

## gitops/apps/finsight/image-tags.yaml on main (ff82177)
```
api:
  image:
    tag: "6e77c47fcf6d41ff029361ccf8e15e71ad4b1574"
    digest: "sha256:28c966f0176aaa5844172d8e26ac519b6d5b4e129e01e7542688fa7a4f7b9e85"
frontend:
  image:
    tag: "6e77c47fcf6d41ff029361ccf8e15e71ad4b1574"
    digest: "sha256:8b215c4444b459c06d60bd5b7984c208762cee74f831f390930f33312aba0c4f"
etl:
  image:
    tag: "6e77c47fcf6d41ff029361ccf8e15e71ad4b1574"
    digest: "sha256:1e0a32899595831bf90fde505709f9410341804383e84a81397978f394157e5b"
```

## ECR (immutable repositories)
```
finsight-dev/api tag=6e77c47fcf6d41ff029361ccf8e15e71ad4b1574 digest=sha256:28c966f0176aaa5844172d8e26ac519b6d5b4e129e01e7542688fa7a4f7b9e85 pushed=2026-10-15T19:45:52.145000+01:00 mutability=IMMUTABLE
finsight-dev/frontend tag=6e77c47fcf6d41ff029361ccf8e15e71ad4b1574 digest=sha256:8b215c4444b459c06d60bd5b7984c208762cee74f831f390930f33312aba0c4f pushed=2026-10-15T19:46:39.767000+01:00 mutability=IMMUTABLE
finsight-dev/etl tag=6e77c47fcf6d41ff029361ccf8e15e71ad4b1574 digest=sha256:1e0a32899595831bf90fde505709f9410341804383e84a81397978f394157e5b pushed=2026-10-15T19:46:23.787000+01:00 mutability=IMMUTABLE
```

## Running on EKS (finsight namespace)
```
POD                                  PHASE       IMAGE_ID                                                                                                                                     RESTARTS
finsight-api-669f7f8c7-f5fg8         Running     <registry>/finsight-dev/api@sha256:28c966f0176aaa5844172d8e26ac519b6d5b4e129e01e7542688fa7a4f7b9e85        0
finsight-db-init-954v4               Succeeded   <registry>/finsight-dev/etl@sha256:1e0a32899595831bf90fde505709f9410341804383e84a81397978f394157e5b        0
finsight-frontend-54576c7855-jhzxq   Running     <registry>/finsight-dev/frontend@sha256:8b215c4444b459c06d60bd5b7984c208762cee74f831f390930f33312aba0c4f   0
finsight-postgres-0                  Running     postgres@sha256:b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24                                           0

db-init Job: 1 succeeded, completed 2026-10-16T08:11:48Z

Result: api, frontend and etl digests identical in image-tags.yaml, ECR and the running/completed pods. Deployment is by digest (repository@sha256), never by mutable tag.
https / 200 ready 200 dashboard has_data=True (verified TLS, exit 0)
```
