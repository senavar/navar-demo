{{- define "birthdayapp.fullname" -}}
{{- printf "%s" .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "birthdayapp.namespace" -}}
{{- if .Values.global.namespace }}{{ .Values.global.namespace }}{{ else }}birthdayapp{{ end }}
{{- end -}}

{{- /*
birthdayapp.image
Usage:
	{{ include "birthdayapp.image" (list . .Values.image.frontend) }}
	{{ include "birthdayapp.image" (list . .Values.image.backend) }}

We pass a list containing the root context and the component image map to avoid losing root scope.
*/ -}}
{{- define "birthdayapp.image" -}}
{{- $root := index . 0 -}}
{{- $img := index . 1 -}}
{{- $globalRegistry := (default "" $root.Values.global.registry) -}}
{{- $repo := $img.repository -}}
{{- $digest := $img.digest | default "" -}}
{{- $tag := $img.tag | default "dev" -}}
{{- if $digest -}}
	{{- if $globalRegistry -}}{{ printf "%s/%s@%s" $globalRegistry $repo $digest }}{{- else -}}{{ printf "%s@%s" $repo $digest }}{{- end -}}
{{- else -}}
	{{- if $globalRegistry -}}{{ printf "%s/%s:%s" $globalRegistry $repo $tag }}{{- else -}}{{ printf "%s:%s" $repo $tag }}{{- end -}}
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
