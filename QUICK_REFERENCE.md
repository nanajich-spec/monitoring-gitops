# Quick Reference - Monitoring Stack

## 🚀 Access URLs
```
Prometheus:   http://172.28.229.33:30090
Grafana:      http://172.28.229.33:30030
Alertmanager: http://172.28.229.33:30093

Grafana Login: admin / admin (CHANGE THIS!)
```

## 📋 Common Commands

### Check Status
```bash
# View all pods
kubectl get pods -n monitoring

# Check ArgoCD application
kubectl get application -n argocd prometheus-stack

# View PVCs
kubectl get pvc -n monitoring

# List alert rules
kubectl get prometheusrule -n monitoring
```

### View Logs
```bash
# Prometheus
kubectl logs -n monitoring prometheus-prometheus-stack-kube-prom-prometheus-0 -c prometheus

# Alertmanager
kubectl logs -n monitoring alertmanager-prometheus-stack-kube-prom-alertmanager-0 -c alertmanager

# Grafana
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -c grafana
```

### Manage Alerts
```bash
# View active alerts in Prometheus
curl http://172.28.229.33:30090/api/v1/alerts | jq

# View Alertmanager alerts
curl http://172.28.229.33:30093/api/v2/alerts | jq

# Silence an alert (5 hours)
curl -XPOST http://172.28.229.33:30093/api/v2/silences -d '{
  "matchers": [{"name": "alertname", "value": "AirflowSchedulerDown", "isRegex": false}],
  "startsAt": "2026-02-25T00:00:00Z",
  "endsAt": "2026-02-25T05:00:00Z",
  "createdBy": "admin",
  "comment": "Maintenance window"
}'
```

### Update Configuration
```bash
# Edit values and commit to Git
cd ~/monitoring-gitops
nano prometheus-stack-application.yaml
git add .
git commit -m "Update configuration"

# ArgoCD will auto-sync within minutes
# Or force sync:
kubectl patch application prometheus-stack -n argocd \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}' --type merge
```

### Apply Airflow Monitoring (when Airflow is deployed)
```bash
# Apply ServiceMonitors
kubectl apply -f ~/monitoring-gitops/configs/airflow-servicemonitor.yaml

# Verify metrics are being scraped
kubectl get servicemonitor -n monitoring
```

## 🎯 PromQL Query Examples

### Airflow Metrics
```promql
# DAG run duration
airflow_dag_run_duration_seconds{dag_id="example_dag"}

# Task failures
rate(airflow_task_failed_total[5m])

# Running tasks
airflow_executor_running_tasks

# Scheduler heartbeat
airflow_scheduler_heartbeat
```

### Kubernetes Metrics
```promql
# Pod CPU usage
rate(container_cpu_usage_seconds_total{namespace="airflow"}[5m])

# Pod memory usage
container_memory_usage_bytes{namespace="airflow"}

# Cluster CPU usage
sum(rate(container_cpu_usage_seconds_total[5m]))

# Available storage
kubelet_volume_stats_available_bytes
```

## 🔧 Troubleshooting

### Pods Not Starting
```bash
# Check events
kubectl get events -n monitoring --sort-by='.lastTimestamp'

# Describe pod
kubectl describe pod <pod-name> -n monitoring

# Check PVC status
kubectl get pvc -n monitoring
kubectl describe pvc <pvc-name> -n monitoring
```

### Alerts Not Firing
```bash
# Check Prometheus targets
curl http://172.28.229.33:30090/api/v1/targets | jq '.data.activeTargets'

# Verify alert rules loaded
kubectl get prometheusrule -n monitoring airflow-alerts -o yaml

# Check Alertmanager config
curl http://172.28.229.33:30093/api/v2/status | jq
```

### Teams Notifications Not Working
```bash
# Test webhook manually
curl -X POST https://myadvantest.webhook.office.com/webhookb2/[...] \
  -H "Content-Type: application/json" \
  -d '{"text":"Test alert from Prometheus"}'

# Check Alertmanager logs
kubectl logs -n monitoring alertmanager-prometheus-stack-kube-prom-alertmanager-0 -c alertmanager | grep -i teams
```

### Grafana Dashboard Not Loading
```bash
# Check datasource
curl http://172.28.229.33:30030/api/datasources | jq

# Verify Prometheus is reachable from Grafana pod
kubectl exec -it -n monitoring prometheus-stack-grafana-<pod> -c grafana -- \
  wget -qO- http://prometheus-stack-kube-prom-prometheus:9090/-/healthy
```

## 📊 Grafana Dashboard IDs

Import these dashboards via Grafana UI (+ → Import):
```
14731 - Airflow Overview
12574 - Airflow Cluster Usage
7249  - Kubernetes Cluster
6417  - Kubernetes Pods
5309  - Kubernetes Capacity
1860  - Node Exporter Full
```

## 🔄 Restart Components
```bash
# Restart Prometheus
kubectl rollout restart statefulset prometheus-prometheus-stack-kube-prom-prometheus -n monitoring

# Restart Alertmanager
kubectl rollout restart statefulset alertmanager-prometheus-stack-kube-prom-alertmanager -n monitoring

# Restart Grafana
kubectl rollout restart deployment prometheus-stack-grafana -n monitoring

# Restart Prometheus Operator
kubectl rollout restart deployment prometheus-stack-kube-prom-operator -n monitoring
```

## 📁 Important Files

```
~/monitoring-gitops/
├── prometheus-stack-application.yaml  # ArgoCD App (main config)
├── configs/
│   ├── airflow-alerts.yaml           # Custom alerts
│   └── airflow-servicemonitor.yaml   # Airflow metrics collection
├── DEPLOYMENT_SUCCESS.md             # Full documentation
└── QUICK_REFERENCE.md                # This file
```

## 🚨 Emergency Actions

### Stop Receiving Alerts Temporarily
```bash
# Silence all alerts for 1 hour
curl -XPOST http://172.28.229.33:30093/api/v2/silences -d '{
  "matchers": [{"name": "alertname", "value": ".*", "isRegex": true}],
  "startsAt": "2026-02-25T00:00:00Z",
  "endsAt": "2026-02-25T01:00:00Z",
  "createdBy": "admin",
  "comment": "Emergency maintenance"
}'
```

### Scale Down Monitoring
```bash
# Scale down Grafana (save resources)
kubectl scale deployment prometheus-stack-grafana -n monitoring --replicas=0

# Scale back up
kubectl scale deployment prometheus-stack-grafana -n monitoring --replicas=1
```

### Remove Everything
```bash
# Delete ArgoCD application (will remove all monitoring components)
kubectl delete application prometheus-stack -n argocd

# Delete namespace (if not using ArgoCD)
kubectl delete namespace monitoring
```

## 📞 Support
- Documentation: `~/monitoring-gitops/DEPLOYMENT_SUCCESS.md`
- Git Repository: `~/monitoring-gitops/`
- ArgoCD UI: (if available via port-forward)
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Access: https://localhost:8080
```

---
**Last Updated:** February 25, 2026  
**Version:** kube-prometheus-stack v82.4.0
