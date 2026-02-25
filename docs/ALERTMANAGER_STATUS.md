# Alertmanager Status and Access

## Current Status: ✅ WORKING

Alertmanager IS receiving and processing alerts correctly. The confusion was about WHERE to view them.

### Alert Summary
- **Active Alerts**: 12
- **Pending Alerts**: 6 (in Prometheus)
- **Alertmanager Status**: Running and receiving alerts
- **Teams Notifications**: Configured and active

### Where to View Alerts

#### 1. Alertmanager Web UI (PRIMARY)
**URL**: http://172.28.229.33:30093/#/alerts

This is the correct place to view Prometheus/Alertmanager alerts.

**Current Active Alerts**:
- `Watchdog` - Always firing (health check)
- `KubeSchedulerDown` - Kubernetes scheduler not discovered
- `KubeControllerManagerDown` - Kubernetes controller manager not discovered  
- `KubeProxyDown` - Kube-proxy not discovered
- `KubePodCrashLooping` - Pod in CrashLoopBackOff (ArgoCD applicationset)
- `HighMemoryUsage` - Multiple pods with high memory (3 instances)
- `CriticalMemoryUsage` - Critical memory usage (1 instance)
- `PodCrashLooping` - Custom alert for crashing pods
- `AirflowPodDown` - Airflow pod monitoring (2 instances)

#### 2. Prometheus Alerts Tab
**URL**: http://172.28.229.33:30090/alerts

Shows alerts in Prometheus before they're sent to Alertmanager.

#### 3. Grafana Alerting Tab
**URL**: http://172.28.229.33:30030/alerting

**Note**: This tab is for Grafana-native alerts only, NOT Prometheus/Alertmanager alerts.
- Grafana has its own alerting system separate from Prometheus
- The "disabled" status you see is for Grafana's built-in alerting
- Prometheus alerts go through Alertmanager, not Grafana alerting

### Verification Commands

```bash
# Check Alertmanager API
curl -s http://172.28.229.33:30093/api/v2/alerts | python3 -m json.tool

# Check using amtool
microk8s kubectl exec -n monitoring alertmanager-prometheus-stack-kube-prom-alertmanager-0 -c alertmanager -- \
  amtool alert --alertmanager.url=http://localhost:9093

# Check Prometheus alerts
curl -s http://172.28.229.33:30090/api/v1/alerts | python3 -m json.tool
```

### Alertmanager Configuration

**Receivers**:
- `teams-notifications` - Sends to Microsoft Teams webhook
- `null` - Suppresses specific alerts (InfoInhibitor, Watchdog)

**Routing**:
- Alerts grouped by: alertname, cluster, service, namespace
- Group wait: 30s
- Group interval: 5m
- Repeat interval: 4h

**Inhibition Rules**:
- Critical alerts suppress warning/info alerts
- Warning alerts suppress info alerts

### Why "Disabled" Status Appears

The "disabled" cluster status in Alertmanager API (`/api/v2/status`) refers to:
- Alertmanager clustering/HA mode is disabled (single instance)
- This is NORMAL for single-instance deployments
- It does NOT mean alerting is disabled

### Integration Status

✅ Prometheus → Alertmanager: **WORKING**
- Prometheus sending alerts to: `http://10.1.40.36:9093/api/v2/alerts`
- 12 active alerts successfully delivered

✅ Alertmanager → Teams: **CONFIGURED**
- Webhook URL configured in receivers
- Alerts matching `severity=~"warning|critical"` sent to Teams

✅ Alertmanager Web UI: **ACCESSIBLE**
- NodePort 30093 exposed
- UI showing all active alerts

❌ Grafana Alerting: **NOT APPLICABLE**
- Grafana's native alerting is separate system
- Use Alertmanager UI for Prometheus alerts

### Files
- `configs/alertmanager-datasource.yaml` - Alertmanager datasource (created but may need Grafana plugin)
- Alert rules in PrometheusRule CRDs (36 rule groups)

### Next Steps (Optional)

If you want to see Alertmanager alerts in Grafana:

1. **Install Alertmanager plugin** in Grafana (if not already installed)
2. **Use Explore tab** with Prometheus datasource to query alert metrics
3. **Create dashboard panels** with alert queries like:
   ```promql
   ALERTS{alertstate="firing"}
   ALERTS{alertstate="pending"}
   ```

### Troubleshooting

If alerts stop appearing:

1. Check Alertmanager pod status:
   ```bash
   microk8s kubectl get pods -n monitoring -l app.kubernetes.io/name=alertmanager
   ```

2. Check Prometheus targets include Alertmanager:
   ```bash
   curl -s http://172.28.229.33:30090/api/v1/alertmanagers
   ```

3. Check Alertmanager logs:
   ```bash
   microk8s kubectl logs -n monitoring alertmanager-prometheus-stack-kube-prom-alertmanager-0 -c alertmanager
   ```

## Summary

**Alertmanager is working correctly**. Access it at:
**http://172.28.229.33:30093/#/alerts**

The "disabled" status and empty alerts you saw were likely in Grafana's Alerting tab, which is a different system.
