# Observability

The Pulse observability stack in-cluster (namespace `pulse-system`), synced by Argo:
Prometheus, Tempo, Loki, the OTel Collector, and Grafana. Each is an Argo `Application`
wrapping the upstream Helm chart; values are vendored from the pulse-pager repo
(`deploy/observability/*/values.yaml`) so the app owns the config and this repo owns the
deployment — keep them in sync on upstream changes.

## Pieces
- `prometheus.yaml` — scrapes pods carrying `prometheus.io/scrape` annotations for
  `/metrics`, holds the recording rules + SLO alerts, receives Tempo's service-graph
  metrics over remote-write. Alertmanager on, node-exporter/kube-state-metrics off.
- `tempo.yaml` — trace store + metrics-generator (service graph → Prometheus).
- `loki.yaml` — single-binary log store (native OTLP ingest).
- `otel-collector.yaml` — OTLP in (`:4317`/`:4318`), tail-sample → Tempo, logs → Loki.
- `grafana.yaml` — provisioned datasources + the `pulse-dashboards` dashboards.
- `dashboards-configmap.yaml` — dashboards as code, generated from the pulse-pager
  dashboard JSON (regenerate with `kubectl create configmap pulse-dashboards -n
  pulse-system --from-file=<pulse-pager>/observability/grafana/dashboards/ --dry-run=client -o yaml`).

Release names are pinned to the Application names (`pulse-prometheus`, `pulse-tempo`,
`pulse-grafana`, …) because the datasource/exporter URLs depend on the resulting service
DNS (`pulse-prometheus-server`, `pulse-tempo`, `pulse-grafana`).

## What the Pulse app must do to be observed
- Pods carry `prometheus.io/scrape: "true"`, `prometheus.io/port: "9080"`,
  `prometheus.io/path: "/metrics"` (set in `cluster/apps/pulse/`).
- Tracing/logs on: `PULSE_TRACING_ENABLED=true` and
  `PULSE_OTLP_ENDPOINT=pulse-otel-collector.pulse-system.svc.cluster.local:4317`
  in `pulse-config`.

## Access
Grafana is ClusterIP (no public exposure):
```
kubectl -n pulse-system port-forward svc/pulse-grafana 3000:80
# http://localhost:3000 — admin password:
kubectl -n pulse-system get secret pulse-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
```
