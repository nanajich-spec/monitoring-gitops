# Teams Notification Status Report

## ✅ Configuration Complete

All components are properly configured for Teams notifications:

### 1. Prometheus Stack - RUNNING ✅
```bash
$ kubectl get pods -n monitoring
NAME                                                     READY   STATUS    RESTARTS   AGE
alertmanager-prometheus-stack-kube-prom-alertmanager-0   2/2     Running   0          15m
prometheus-prometheus-stack-kube-prom-prometheus-0       2/2     Running   0          15m
prometheus-stack-grafana-76879cbcf-c5474                 3/3     Running   6          15m
prometheus-stack-kube-prom-operator-6b9f8c5bbf-8kpp7     1/1     Running   0          15m
prometheus-stack-kube-state-metrics-6859f6c98b-9dmwd     1/1     Running   0          15m
prometheus-msteams-549f9498c4-pnnp6                      1/1     Running   0          5m
```

### 2. Alertmanager Configuration - CORRECT ✅
```yaml
receivers:
- name: teams-notifications
  webhook_configs:
  - url: http://prometheus-msteams:2000/alertmanager
    send_resolved: true
```

### 3. Prometheus-MSTeams Connector - RUNNING ✅
- **Deployment**: prometheus-msteams (Running)
- **Service**: prometheus-msteams:2000 (ClusterIP)
- **Configuration**: /config/config.yaml with Teams webhook URL
- **Card Generation**: Working (logs show MessageCard creation)

### 4. Teams Webhook URL - CONFIGURED ✅
```
https://myadvantest.webhook.office.com/webhookb2/abc559ed-5a14-4890-8f65-e7e8d1f27414@b0de9dff-4833-4d4f-b442-1e0dbfae2ec8/IncomingWebhook/d3a2cd1b62694999982ac8303d9facb2/cc25c079-475a-47ee-bfef-0b06ac15a4ad/V2I_NtY59R7qGhSRQY10oyJKLK7OwXK_g6ieRsfhQ3jmY1
```

## ⚠️ Current Issue

**SSL Connection Error**: The prometheus-msteams connector cannot reach the Teams webhook URL due to SSL/TLS errors:

```
error:0A000126:SSL routines::unexpected eof while reading
```

### Possible Causes:
1. **Corporate Proxy/Firewall**: WSL2 environment may require proxy configuration
2. **SSL Certificate Issues**: Missing/outdated CA certificates in container
3. **Network Policy**: Kubernetes network policies blocking outbound HTTPS
4. **WSL2 Network Limitation**: NAT/bridge configuration preventing external HTTPS

## 🔍 Verification Steps

### 1. Test Teams Webhook from Host
```bash
# From WSL2 host (outside container)
curl -k -H "Content-Type: application/json" -d '{
  "@type": "MessageCard",
  "@context": "https://schema.org/extensions",
  "summary": "Test",
  "title": "Test Alert",
  "text": "Testing Teams webhook"
}' "https://myadvantest.webhook.office.com/webhookb2/[YOUR_WEBHOOK_PATH]"
```

**Expected Response**: `1` (success)

### 2. Check prometheus-msteams Logs
```bash
kubectl logs -n monitoring deployment/prometheus-msteams --tail=50 | grep -i "teams\|error\|POST"
```

### 3. Verify Alert Flow
```bash
# Check Prometheus alerts
curl http://172.28.229.33:30090/api/v1/alerts | jq '.data.alerts[] | {name:.labels.alertname, status:.state}'

# Check Alertmanager alerts
curl http://172.28.229.33:30093/api/v2/alerts | jq '.[] | {name:.labels.alertname, status:.status.state}'

# Check prometheus-msteams received alerts
kubectl logs -n monitoring deployment/prometheus-msteams | grep "card" | tail -1
```

## 🛠️ Solutions to Try

### Option 1: Add Proxy Configuration (if behind corporate proxy)
```yaml
# Edit prometheus-msteams deployment
env:
- name: HTTP_PROXY
  value: "http://proxy.company.com:8080"
- name: HTTPS_PROXY
  value: "http://proxy.company.com:8080"
- name: NO_PROXY
  value: "localhost,127.0.0.1,.svc,.cluster.local"
```

### Option 2: Use Alternative Teams Connector
Deploy Azure Logic App or Power Automate webhook instead of direct Teams connector.

### Option 3: Add CA Certificates to prometheus-msteams
```yaml
volumeMounts:
- name: ca-certs
  mountPath: /etc/ssl/certs
  readOnly: true
volumes:
- name: ca-certs
  hostPath:
    path: /etc/ssl/certs
```

### Option 4: Test with Different Teams Webhook
Create a new incoming webhook in Teams channel settings and update the ConfigMap:
```bash
kubectl edit configmap prometheus-msteams-config -n monitoring
# Update teams_webhook_url
kubectl rollout restart deployment/prometheus-msteams -n monitoring
```

## 📊 Current Alert Flow

```
┌─────────────┐
│ Prometheus  │ ← Scrapes metrics from targets
└──────┬──────┘
       │ Evaluates rules every 30s
       ↓
┌─────────────────┐
│ Alert Rules     │ ← airflow-alerts, k8s alerts
└──────┬──────────┘
       │ Fires when conditions met
       ↓
┌─────────────────┐
│ Alertmanager    │ ← Groups, deduplicates, routes
└──────┬──────────┘
       │ POSTs to webhook
       ↓
┌──────────────────┐
│ prometheus-      │ ← Converts to MessageCard format
│ msteams:2000     │
└──────┬───────────┘
       │ POSTs MessageCard
       ↓
┌──────────────────┐
│ Teams Webhook    │ ⚠️ SSL ERROR HERE
│ (Office 365)     │
└──────────────────┘
       ↓
┌──────────────────┐
│ Teams Channel    │
└──────────────────┘
```

## ✅ What's Working

1. **Prometheus** is scraping metrics and evaluating alert rules
2. **Alert Rules** are loaded (35 PrometheusRule CRDs)
3. **Alertmanager** is receiving alerts from Prometheus
4. **prometheus-msteams** is receiving alerts from Alertmanager
5. **MessageCard format** is being generated correctly
6. **Alert routing** is configured properly

## ❌ What's NOT Working

1. **HTTPS connection** from prometheus-msteams container to Teams webhook URL
2. **SSL/TLS handshake** failing with "unexpected eof"

## 📝 Recommendations

1. **Immediate**: Test Teams webhook from Windows host (outside WSL2):
   ```powershell
   Invoke-WebRequest -Uri "https://myadvantest.webhook.office.com/webhookb2/[PATH]" `
     -Method POST `
     -Body '{"text":"Test from PowerShell"}' `
     -ContentType "application/json"
   ```

2. **Short-term**: If webhook works from Windows but not WSL2, configure WSL2 networking:
   ```bash
   # In /etc/wsl.conf
   [network]
   generateResolvConf = true
   ```

3. **Long-term**: Consider using Azure Monitor or alternative notification methods if Teams webhook consistently fails from Kubernetes.

## 📁 Configuration Files

All configurations are committed to Git:
```
~/monitoring-gitops/
├── configs/
│   ├── prometheus-msteams.yaml         ← Connector deployment
│   ├── airflow-alerts.yaml            ← Custom alert rules
│   └── airflow-servicemonitor.yaml    ← Airflow metrics collection
└── prometheus-stack-application.yaml  ← Main ArgoCD app with Alertmanager config
```

## 🔄 To Restart Components

```bash
# Restart prometheus-msteams
kubectl rollout restart deployment/prometheus-msteams -n monitoring

# Restart Alertmanager
kubectl rollout restart statefulset alertmanager-prometheus-stack-kube-prom-alertmanager -n monitoring

# Check status
kubectl get pods -n monitoring -w
```

---

**Status**: Configuration Complete, Network Issue Preventing Delivery  
**Next Action**: Verify Teams webhook accessibility from WSL2/Kubernetes environment  
**Date**: February 25, 2026
