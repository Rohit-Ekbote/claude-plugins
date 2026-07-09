{{- define "demo" -}}
{{ fail "BRAND NEW GUARD: set demo.widget.enabled or demo.widget.existingConfigMap." }}
{{ fail "objectStorage.kind=external requires objectStorage.external.host or objectStorage.external.internalHost." }}
{{- end }}
