{{- define "demo" -}}
{{ fail "BRAND NEW GUARD: set demo.widget.enabled or demo.widget.existingConfigMap." }}
{{ fail "objectStorage.kind=external requires objectStorage.external.host or objectStorage.external.internalHost." }}
{{ fail "Zoo.enabled=true requires zoo.tamer to be set." }}
{{ fail "_underscoreOption must be one of: a, b." }}
{{ fail "99-lives.enabled requires ninePercent >= 0." }}
{{ fail "Api_Key.enabled=true but Api_Key.secret is empty." }}
{{- end }}
