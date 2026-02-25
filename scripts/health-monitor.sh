#!/bin/bash
# Comprehensive Service Health Monitor
# Checks all critical services and auto-fixes issues

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

echo "=========================================="
echo "  MicroK8s Cluster Health Monitor"
echo "  $(date)"
echo "=========================================="
echo ""

# Check MicroK8s status
echo "1. MicroK8s Status"
if microk8s status | grep -q "microk8s is running"; then
    log_success "MicroK8s is running"
else
    log_error "MicroK8s is not running"
    exit 1
fi
echo ""

# Check node status
echo "2. Node Status"
NODE_STATUS=$(kubectl get nodes --no-headers | awk '{print $2}')
if [ "$NODE_STATUS" = "Ready" ]; then
    log_success "Node is Ready"
else
    log_error "Node status: $NODE_STATUS"
fi
echo ""

# Check ArgoCD
echo "3. ArgoCD Status"
ARGOCD_PODS=$(kubectl get pods -n argocd --no-headers 2>/dev/null | wc -l)
ARGOCD_RUNNING=$(kubectl get pods -n argocd --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [ "$ARGOCD_PODS" -eq "$ARGOCD_RUNNING" ]; then
    log_success "ArgoCD: $ARGOCD_RUNNING/$ARGOCD_PODS pods running"
else
    log_warning "ArgoCD: $ARGOCD_RUNNING/$ARGOCD_PODS pods running"
fi

# Check ArgoCD applications
kubectl get applications -n argocd --no-headers 2>/dev/null | while read app sync health rest; do
    if [ "$health" = "Healthy" ]; then
        log_success "App $app: $health ($sync)"
    elif [ "$health" = "Progressing" ]; then
        log_warning "App $app: $health ($sync)"
    else
        log_error "App $app: $health ($sync)"
    fi
done
echo ""

# Check Monitoring Stack
echo "4. Monitoring Stack"
PROM_STATUS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
ALERT_STATUS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=alertmanager --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
GRAFANA_STATUS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

[ "$PROM_STATUS" -gt 0 ] && log_success "Prometheus: Running" || log_error "Prometheus: Not running"
[ "$ALERT_STATUS" -gt 0 ] && log_success "Alertmanager: Running" || log_error "Alertmanager: Not running"
[ "$GRAFANA_STATUS" -gt 0 ] && log_success "Grafana: Running" || log_error "Grafana: Not running"

# Check for failing Grafana pods and fix
GRAFANA_FAILING=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null | wc -l)
if [ "$GRAFANA_FAILING" -gt 0 ]; then
    log_warning "Found $GRAFANA_FAILING failing Grafana pod(s). Auto-fixing..."
    kubectl delete pods -n monitoring -l app.kubernetes.io/name=grafana --field-selector=status.phase!=Running,status.phase!=Succeeded --ignore-not-found=true
fi
echo ""

# Check Airflow
echo "5. Airflow Status"
AIRFLOW_PODS=$(kubectl get pods -n airflow --no-headers 2>/dev/null | wc -l)
AIRFLOW_RUNNING=$(kubectl get pods -n airflow --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [ "$AIRFLOW_PODS" -eq "$AIRFLOW_RUNNING" ]; then
    log_success "Airflow: $AIRFLOW_RUNNING/$AIRFLOW_PODS pods running"
else
    log_warning "Airflow: $AIRFLOW_RUNNING/$AIRFLOW_PODS pods running"
fi

# Check specific components
for component in webserver scheduler triggerer worker; do
    STATUS=$(kubectl get pods -n airflow -l component=$component --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    [ "$STATUS" -gt 0 ] && log_success "  $component: Running" || log_warning "  $component: Not running"
done
echo ""

# Check for any failing pods across all namespaces
echo "6. Cluster-wide Pod Health"
FAILING_PODS=$(kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null | wc -l)
if [ "$FAILING_PODS" -eq 0 ]; then
    log_success "No failing pods detected"
else
    log_warning "Found $FAILING_PODS failing pod(s):"
    kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null
fi
echo ""

# Check PVC status
echo "7. Persistent Volume Claims"
PVC_TOTAL=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | wc -l)
PVC_BOUND=$(kubectl get pvc --all-namespaces --field-selector=status.phase=Bound --no-headers 2>/dev/null | wc -l)
if [ "$PVC_TOTAL" -eq "$PVC_BOUND" ]; then
    log_success "All PVCs bound: $PVC_BOUND/$PVC_TOTAL"
else
    log_warning "PVCs: $PVC_BOUND/$PVC_TOTAL bound"
fi
echo ""

# Check services
echo "8. Service Endpoints"
echo "  ArgoCD:       http://$(hostname -I | awk '{print $1}'):30080"
echo "  Airflow:      http://$(hostname -I | awk '{print $1}'):30081"
echo "  Grafana:      http://$(hostname -I | awk '{print $1}'):30030"
echo "  Prometheus:   http://$(hostname -I | awk '{print $1}'):30090"
echo "  Alertmanager: http://$(hostname -I | awk '{print $1}'):30093"
echo ""

echo "=========================================="
echo "  Health check completed"
echo "=========================================="
