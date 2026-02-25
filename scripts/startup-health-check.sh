#!/bin/bash
# MicroK8s Auto-Start and Health Check Script
# This script ensures MicroK8s starts properly and all services are healthy

set -e

echo "=== MicroK8s Startup and Health Check ==="
echo "Started at: $(date)"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Wait for MicroK8s to be ready
log "Waiting for MicroK8s to be ready..."
microk8s status --wait-ready --timeout 300

# Check if MicroK8s is running
if ! microk8s status | grep -q "microk8s is running"; then
    log "ERROR: MicroK8s is not running. Starting..."
    microk8s start
    microk8s status --wait-ready --timeout 300
fi

log "MicroK8s is ready!"

# Wait for core system pods
log "Waiting for core system pods..."
sleep 30

# Check critical namespaces exist
for ns in kube-system argocd monitoring airflow; do
    if ! kubectl get namespace $ns &>/dev/null; then
        log "WARNING: Namespace $ns does not exist!"
    else
        log "✓ Namespace $ns exists"
    fi
done

# Wait for ArgoCD to be ready
log "Checking ArgoCD status..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s || log "WARNING: ArgoCD not ready yet"

# Wait for monitoring stack
log "Checking Prometheus stack..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=300s || log "WARNING: Prometheus not ready yet"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=alertmanager -n monitoring --timeout=300s || log "WARNING: Alertmanager not ready yet"

# Check and fix Grafana
log "Checking Grafana status..."
GRAFANA_READY=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

if [ "$GRAFANA_READY" -eq 0 ]; then
    log "Grafana not ready. Checking for issues..."
    
    # Apply Grafana fix
    if [ -f ~/monitoring-gitops/configs/grafana-sidecar-fix.yaml ]; then
        log "Applying Grafana fix..."
        kubectl patch deployment prometheus-stack-grafana -n monitoring --patch-file ~/monitoring-gitops/configs/grafana-sidecar-fix.yaml || true
    fi
    
    # Delete failing pods
    kubectl delete pods -n monitoring -l app.kubernetes.io/name=grafana --field-selector=status.phase!=Running,status.phase!=Succeeded --ignore-not-found=true
    
    # Wait for Grafana
    sleep 10
fi

# Wait for Airflow
log "Checking Airflow status..."
kubectl wait --for=condition=ready pod -l component=webserver -n airflow --timeout=300s || log "WARNING: Airflow webserver not ready yet"
kubectl wait --for=condition=ready pod -l component=scheduler -n airflow --timeout=300s || log "WARNING: Airflow scheduler not ready yet"

# Display summary
log "=== Status Summary ==="
echo ""
echo "ArgoCD Applications:"
kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status

echo ""
echo "Pod Status by Namespace:"
for ns in argocd monitoring airflow; do
    echo ""
    echo "=== $ns ==="
    kubectl get pods -n $ns -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[*].ready,STATUS:.status.phase,RESTARTS:.status.containerStatuses[*].restartCount
done

echo ""
log "=== Startup health check completed ==="
log "All services should be starting up. Monitor for a few minutes."

echo ""
echo "Access URLs:"
echo "  ArgoCD:       http://$(hostname -I | awk '{print $1}'):30080"
echo "  Airflow:      http://$(hostname -I | awk '{print $1}'):30081"
echo "  Grafana:      http://$(hostname -I | awk '{print $1}'):30030"
echo "  Prometheus:   http://$(hostname -I | awk '{print $1}'):30090"
echo "  Alertmanager: http://$(hostname -I | awk '{print $1}'):30093"
