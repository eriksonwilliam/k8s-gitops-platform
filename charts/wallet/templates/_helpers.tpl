{{- define "wallet.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "wallet.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "wallet.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "wallet.labels" -}}
helm.sh/chart: {{ include "wallet.chart" . }}
{{ include "wallet.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "wallet.selectorLabels" -}}
app.kubernetes.io/name: {{ include "wallet.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Referência da imagem: por digest OU por tag, nunca as duas. Com digest, o
runtime ignora a tag de qualquer forma, e "repo:tag@digest" só faria a tag
parecer relevante. Os dois definidos ao mesmo tempo é erro de configuração.
*/}}
{{- define "wallet.image" -}}
{{- if and .Values.image.digest .Values.image.tag }}
{{- fail "image.digest e image.tag sao mutuamente exclusivos: defina apenas um" }}
{{- end }}
{{- if .Values.image.digest }}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) }}
{{- end }}
{{- end }}

{{- define "wallet.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "wallet.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
