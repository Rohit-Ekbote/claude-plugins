{{- define "runwhen.objectStorage.validate" -}}{{- end }}
{{- define "runwhen.postgresql.validate" -}}{{- end }}
{{- define "runwhen.workspaceBootstrap.validate" -}}{{ fail "needs staffUser.email" }}{{- end }}
