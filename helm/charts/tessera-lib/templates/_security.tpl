{{/*
securityContext контейнера, приведённый к уровню restricted.
Аргумент: корневой контекст.
*/}}
{{- define "platform.containerSecurityContext" -}}
runAsNonRoot: true
runAsUser: 65532
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
seccompProfile:
  type: RuntimeDefault
{{- end -}}
