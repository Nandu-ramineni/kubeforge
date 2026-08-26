{{/*
Shared pod spec, used by both templates/deployment.yaml (worker, frontend -
plain Deployments) and templates/rollout.yaml (api - an Argo Rollout, for
canary). Without this, converting api to a Rollout for canary deployments
would mean maintaining two near-identical ~40-line container specs that
would inevitably drift - this is the same "don't repeat yourself" reasoning
as ranging over .Values.services in deployment.yaml, just one level deeper.

Called as: {{- include "kubeforge.podTemplate" (dict "name" $name "svc" $svc "root" $) | nindent N }}
*/}}
{{- define "kubeforge.podTemplate" -}}
metadata:
  labels:
    app: {{ .name }}
spec:
  serviceAccountName: {{ .name }}
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: ScheduleAnyway
      labelSelector:
        matchLabels:
          app: {{ .name }}
  containers:
    - name: {{ .name }}
      image: "{{ .root.Values.image.registry }}/kubeforge-{{ .name }}:{{ .root.Values.image.tag }}"
      imagePullPolicy: {{ .root.Values.image.pullPolicy }}
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
      ports:
        - name: metrics
          containerPort: {{ .svc.port }}
      env:
        {{- range $key, $value := .svc.extraEnv }}
        - name: {{ $key }}
          value: {{ $value | quote }}
        {{- end }}
      {{- if or .svc.needsConfig .svc.needsSecret }}
      envFrom:
        {{- if .svc.needsConfig }}
        - configMapRef:
            name: kubeforge-config
        {{- end }}
        {{- if .svc.needsSecret }}
        - secretRef:
            name: kubeforge-secrets
        {{- end }}
      {{- end }}
      startupProbe:
        # Generous tolerance for the worst-case dependency-connection retry
        # sequence (services/*/src/db.js: up to 5 attempts x 2s = 10s just
        # for Postgres, on top of Redis and RabbitMQ connecting too).
        # Liveness doesn't start evaluating until this succeeds once, so a
        # slow-but-genuinely-still-starting pod never gets killed
        # prematurely for something that isn't actually a hang.
        httpGet:
          path: /health/live
          port: {{ .svc.port }}
        failureThreshold: 30
        periodSeconds: 2
      readinessProbe:
        httpGet:
          path: /health/ready
          port: {{ .svc.port }}
        periodSeconds: 5
      livenessProbe:
        httpGet:
          path: /health/live
          port: {{ .svc.port }}
        periodSeconds: 10
      resources:
        {{- toYaml .svc.resources | nindent 8 }}
      volumeMounts:
        - name: tmp
          mountPath: /tmp
  volumes:
    - name: tmp
      emptyDir: {}
{{- end -}}
