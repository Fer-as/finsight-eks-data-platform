{{- define "finsight.labels" -}}
app.kubernetes.io/part-of: finsight
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/* Image reference: repository@digest when the digest is known (set by the pipeline's GitOps
     update), otherwise repository:tag. Tags are commit SHAs in immutable ECR repositories. */}}
{{- define "finsight.image" -}}
{{- $repo := required "image.repository is required" .repository -}}
{{- if .digest -}}
{{- if not (regexMatch "^sha256:[0-9a-f]{64}$" .digest) -}}
{{- fail "image.digest must be sha256:<64 hex characters>" -}}
{{- end -}}
{{ $repo }}@{{ .digest }}
{{- else -}}
{{ $repo }}:{{ required "image.tag or image.digest is required" .tag }}
{{- end -}}
{{- end }}

{{/* Called with the component's values (api or frontend) so each has its own high UID. */}}
{{- define "finsight.podSecurity" -}}
securityContext:
  runAsNonRoot: true
  runAsUser: {{ .runAsUser }}
  runAsGroup: {{ .runAsUser }}
  fsGroup: {{ .runAsUser }}
  seccompProfile:
    type: RuntimeDefault
{{- end }}

{{- define "finsight.containerSecurity" -}}
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
{{- end }}
