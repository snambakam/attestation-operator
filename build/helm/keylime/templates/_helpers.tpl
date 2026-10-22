{{/*
Expand the name of the chart.
*/}}
{{- define "keylime.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "keylime.fullname" -}}
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

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "keylime.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "keylime.labels" -}}
helm.sh/chart: {{ include "keylime.chart" . }}
{{ include "keylime.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "keylime.selectorLabels" -}}
app.kubernetes.io/name: {{ include "keylime.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "keylime.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "keylime.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Expand to the name of the keylime config map
*/}}
{{- define "keylime.configMap" -}}
{{- printf "%s-%s" .Release.Name "keylime-config" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Expand to the name of the keylime controller config map
*/}}
{{- define "keylime.controllerConfigMap" -}}
{{- printf "%s-%s" .Release.Name "keylime-controller" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Always expands to the name of the secret used for certificates when the init job runs.
*/}}
{{- define "keylime.ca.secret.certs" -}}
{{- printf "%s-%s" .Release.Name "keylime-certs" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Always expands to the name of the secret used for the CA certificate when the init job runs.
*/}}
{{- define "keylime.ca.secret.password" -}}
{{- printf "%s-%s" .Release.Name "keylime-ca-password" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "generate_static_password" -}}
{{- if not (index .Release "tmp_vars") -}}
{{-   $_ := set .Release "tmp_vars" dict -}}
{{- end }}
{{- $key := printf "%s_%s" .Release.Name "password" -}}
{{- if not (index .Release.tmp_vars $key) -}}
{{-   $_ := set .Release.tmp_vars $key (randAlphaNum 32) -}}
{{- end -}}
{{- /* Retrieve previously generated value. */ -}}
{{- index .Release.tmp_vars $key -}}
{{- end -}}

{{/*
Generate a random password if one is not defined
*/}}
{{- define "keylime.ca.secret.passwordcontents" -}}
{{- $capwsecretname := printf "%s" (include "keylime.ca.secret.password" .) }}
{{- $existingSecret := (lookup "v1" "Secret" .Release.Namespace "$capwsecretname") }}
{{- if $existingSecret -}}
{{- index $existingSecret.data "KEYLIME_CA_PASSWORD" -}}
{{- else -}}
{{- default (include "generate_static_password" .) .Values.global.ca.password | b64enc | quote -}}
{{- end -}}
{{- end -}}

{{/*
Need to find a way to override .Values.mysql.auth.existingSecret to include Release.Name
*/}}
{{- define "keylime.mysql.secret.password" -}}
{{- printf "%s-%s" .Release.Name "keylime-mysql-password" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Generate a random password if one is not defined
*/}}
{{- define "keylime.mysql.secret.passwordcontents" -}}
{{- $mysqlpwsecretname := printf "%s" (include "keylime.mysql.secret.password" .) -}}
{{- $existingSecret := (lookup "v1" "Secret" .Release.Namespace "$mysqlpwsecretname") -}}
{{- if $existingSecret -}}
{{- index $existingSecret.data "mysql-root-password" -}}
{{- else -}}
{{- default (include "generate_static_password" .) .Values.global.database.mysql.password | b64enc | quote -}}
{{- end -}}
{{- end -}}

{{/*
True (non-empty) when a PostgreSQL backend is selected for the verifier and registrar.
*/}}
{{- define "keylime.postgres.use" -}}
{{- if .Values.global.database.postgres.external }}true{{- end }}
{{- end }}

{{/*
True (non-empty) when the PostgreSQL connection URLs are read from Azure Key Vault.
*/}}
{{- define "keylime.postgres.keyVault" -}}
{{- if and .Values.global.database.postgres.external .Values.global.database.postgres.keyVault.enabled }}true{{- end }}
{{- end }}

{{/*
Name of the SecretProviderClass that reads the PostgreSQL connection URLs from Azure Key Vault.
*/}}
{{- define "keylime.postgres.secretProviderClass" -}}
{{- printf "%s-%s" .Release.Name "keylime-postgres-kv" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Name of the secret holding KEYLIME_REGISTRAR_DATABASE_URL and KEYLIME_VERIFIER_DATABASE_URL.
With Key Vault this is the Kubernetes secret synced by the CSI driver. Otherwise it is
global.database.postgres.existingSecret when set, or the secret generated by this chart.
*/}}
{{- define "keylime.postgres.secret" -}}
{{- if .Values.global.database.postgres.existingSecret }}
{{- .Values.global.database.postgres.existingSecret }}
{{- else }}
{{- printf "%s-%s" .Release.Name "keylime-postgres-urls" | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Build a SQLAlchemy URL for the external PostgreSQL server. The user name and password are
percent-encoded so that special characters (such as @, / or :) are safe. Expects a dict with the
keys "pg" (the postgres values) and "database" (the database name).
*/}}
{{- define "keylime.postgres.url" -}}
{{- $pg := .pg -}}
{{- printf "postgresql+psycopg2://%s:%s@%s:%v/%s?sslmode=%s" (urlquery $pg.username | replace "+" "%20") (urlquery $pg.password | replace "+" "%20") $pg.host $pg.port .database $pg.sslmode -}}
{{- end }}

{{/*
Always expands to the name of the secret used for the TPM cert store when the init job runs.
*/}}
{{- define "keylime.tpmCertStore.secret" -}}
{{- printf "%s-%s" .Release.Name "keylime-tpm-cert-store" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "keylime.tpmCertStore.extrasecret" -}}
{{- printf "%s-%s" .Release.Name "keylime-tpm-extra-cert-store" | trunc 63 | trimSuffix "-" }}
{{- end }}

