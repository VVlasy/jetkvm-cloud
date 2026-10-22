{{/*
Chart name
*/}}
{{- define "jetkvm-cloud.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Base name for component resources: the release name, unless overridden.
(Release "jetkvm" -> jetkvm-cloud-api, jetkvm-cloud-ui, jetkvm-postgres.)
*/}}
{{- define "jetkvm-cloud.fullname" -}}
{{- default .Release.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Component resource names. Overridable so a chart release can take over
resources that were created by hand under plain names.
*/}}
{{- define "jetkvm-cloud.api.name" -}}
{{- default (printf "%s-cloud-api" (include "jetkvm-cloud.fullname" .)) .Values.api.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "jetkvm-cloud.ui.name" -}}
{{- default (printf "%s-cloud-ui" (include "jetkvm-cloud.fullname" .)) .Values.ui.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "jetkvm-cloud.postgres.name" -}}
{{- default (printf "%s-postgres" (include "jetkvm-cloud.fullname" .)) .Values.postgres.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels (metadata only, never used in selectors)
*/}}
{{- define "jetkvm-cloud.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ include "jetkvm-cloud.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: jetkvm-cloud
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels. Deliberately just `app: <component name>` so that selectors
match the hand-rolled manifests this chart replaces (selectors are immutable).
Usage: {{ include "jetkvm-cloud.selectorLabels" (dict "name" "<name>") }}
*/}}
{{- define "jetkvm-cloud.selectorLabels" -}}
app: {{ .name }}
{{- end }}

{{/*
Name of the Secret the API loads with envFrom
*/}}
{{- define "jetkvm-cloud.api.secretName" -}}
{{- default (include "jetkvm-cloud.api.name" .) .Values.api.existingSecret }}
{{- end }}

{{/*
Name of the Secret postgres loads with envFrom
*/}}
{{- define "jetkvm-cloud.postgres.secretName" -}}
{{- default (include "jetkvm-cloud.postgres.name" .) .Values.postgres.existingSecret }}
{{- end }}

{{/*
DATABASE_URL: explicit value, else built from the in-chart postgres settings.
*/}}
{{- define "jetkvm-cloud.api.databaseUrl" -}}
{{- if .Values.api.secret.DATABASE_URL }}
{{- .Values.api.secret.DATABASE_URL }}
{{- else if and .Values.postgres.enabled (not .Values.postgres.existingSecret) }}
{{- printf "postgres://%s:%s@%s:5432/%s?schema=public" (.Values.postgres.auth.username | urlquery) (.Values.postgres.auth.password | urlquery) (include "jetkvm-cloud.postgres.name" .) .Values.postgres.auth.database }}
{{- end }}
{{- end }}

{{/*
API image reference
*/}}
{{- define "jetkvm-cloud.api.image" -}}
{{- printf "%s:%s" .Values.api.image.repository (default .Chart.AppVersion .Values.api.image.tag) }}
{{- end }}
