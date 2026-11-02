{{/*
Имя приложения. По умолчанию — имя чарта, переопределяется nameOverride.
*/}}
{{- define "tessera.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Полное имя ресурса: основа для имён всех объектов релиза.
*/}}
{{- define "tessera.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Имя и версия чарта для метки helm.sh/chart.
*/}}
{{- define "tessera.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Полный набор меток: metadata.labels всех объектов.
*/}}
{{- define "tessera.labels" -}}
helm.sh/chart: {{ include "tessera.chart" . }}
{{ include "tessera.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: ticketing
{{- end -}}

{{/*
Селекторные метки: только то, что не меняется между релизами.
*/}}
{{- define "tessera.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tessera.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Имя ServiceAccount: созданный чартом или существующий.
*/}}
{{- define "tessera.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "tessera.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Ссылка на образ: по digest, если задан, иначе по тегу.
*/}}
{{- define "tessera.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end -}}
{{- end -}}

{{/*
Имя секрета: существующий или созданный чартом.
*/}}
{{- define "tessera.secretName" -}}
{{- default (printf "%s-secrets" (include "tessera.fullname" .)) .Values.secrets.existingSecret -}}
{{- end -}}

{{/*
Публичный адрес сервиса для NOTES, конфигурации и тестов.
*/}}
{{- define "tessera.publicHost" -}}
{{- if .Values.publicHost -}}
{{- .Values.publicHost -}}
{{- else if .Values.ingress.enabled -}}
{{- (index .Values.ingress.hosts 0).host -}}
{{- else -}}
{{- include "tessera.fullname" . -}}
{{- end -}}
{{- end -}}
