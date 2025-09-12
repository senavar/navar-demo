{{- define "birthdayapp.fullname" -}}
{{- printf "%s" .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "birthdayapp.namespace" -}}
{{- if .Values.global.namespace }}{{ .Values.global.namespace }}{{ else }}birthdayapp{{ end }}
{{- end -}}

{{- define "birthdayapp.image" -}}
{{- $globalRegistry := .Values.global.registry -}}
{{- $repo := .repository -}}
{{- $digest := .digest | default "" -}}
{{- $tag := .tag | default "dev" -}}
{{- if $digest }}
{{- if $globalRegistry }}{{ printf "%s/%s@%s" $globalRegistry $repo $digest }}{{ else }}{{ printf "%s@%s" $repo $digest }}{{ end }}
{{- else -}}
{{- if $globalRegistry }}{{ printf "%s/%s:%s" $globalRegistry $repo $tag }}{{ else }}{{ printf "%s:%s" $repo $tag }}{{ end }}
{{- end -}}
{{- end -}}

{{- define "birthdayapp.annotations" -}}
{{- if .Values.annotations }}
{{- toYaml .Values.annotations }}
{{- end -}}
{{- end -}}

{{- define "birthdayapp.version" -}}
{{- if .Values.appVersionOverride }}{{ .Values.appVersionOverride }}{{ else }}{{ .Chart.AppVersion }}{{ end }}
{{- end -}}
