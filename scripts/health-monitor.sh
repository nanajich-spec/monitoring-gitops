#!/bin/bash
# Comprehensive Service Health Monitor with Auto-Restart
# Continuously monitors all critical services and auto-fixes issues

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_info() { echo -e "${YELLOW}ℹ${NC} $1"; }

# Function to restart failed pods
restart_failed_pod() {
    local namespace=$1
    local pod=$2
    log_info "Restarting failed pod: $pod in namespace: $namespace"
    microk8s kubectl delete pod "$pod" -n "$namespace" --grace-period=0 --force 2>/dev/null || true
    sleep 2
}

# Function to restart deployment
restart_deployment() {
    local namespace=$1
    local deployment=$2
    log_info "Restarting deployment: $deployment in namespace: $namespace"
    microk8s kubectl rollout restart deployment "$deployment" -n "$namespace" 2>/dev/null || true
    sleep 2
}

# Main monitoring loop
while true; do
    echo ""
    echo "=========================================="
    echo "  MicroK8s Cluster Health Monitor"
    echo "  $(date)"
    echo "=========================================="
    echo ""

    # Check MicroK8s status
    echo "1. MicroK8s Status"
    if microk8s status 2>/dev/null | grep -q "microk8s is running"; then
        log_success "MicroK8s is running"
    else
        log_error "MicroK8s is not running - attempting to start"
        sudo snap start microk8s 2>/dev/null || true
        sleep 30
    fi
    echo ""

    # Check node status
    echo "2. Node Status"
    NODE_STATUS=$(microk8s kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' || echo "Unknown")
    if [ "$NODE_STATUS" = "Ready" ]; then
        log_success "Node is Ready"
    else
        log_error "Node status: $NODE_STATUS"
    fi
    echo ""

    # Check and restart failed pods in all namespaces
    echo "3. Checking All Pods"
    namespaces=$(microk8s kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    for ns in $namespaces; do
        # Check for CrashLoopBackOff, Error, ImagePullBackOff pods
        failed_pods=$(microk8s kubectl get pods -n "$ns" 2>/dev/null | grep -E "CrashLoopBackOff|Error|ImagePullBackOff" | awk '{print $1}' || true)
        
        if [ -n "$failed_pods" ]; then
            log_warning "Found failed pods in namespace: $ns"
            for pod in $failed_pods; do
                log_error "Pod $pod in $ns is failing"
                restart_failed_pod "$ns" "$pod"
            done
        fi
        
        # Check for pods that are not ready for more than 5 minutes
        notready_pods=$(microk8s kubectl get pods -n "$ns" 2>/dev/null | grep "Running" | grep -E "0/[0-9]|[0-9]/[0-9]" | awk '{if ($2 !~ /^[1-9]+\/\1$/) print $1}' || true)
        
        if [ -n "$notready_pods" ]; then
            for pod in $notready_pods; do
                # Get pod age
                age=$(microk8s kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.startTime}' 2>/dev/null)
                if [ -n "$age" ]; then
                    current_time=$(date -u +%s)
                    pod_start_time=$(date -d "$age" +%s 2>/dev/null || echo "$current_time")
                    age_seconds=$((current_time - pod_start_time))
                    
                    # If pod has been not ready for more than 5 minutes, restart it
                    if [ "$age_seconds" -gt 300 ]; then
                        log_warning "Pod $pod in $ns not ready for ${age_seconds}s"
                        restart_failed_pod "$ns" "$pod"
                    fi
                fi
            done
        fi
    done
    
    # Check ArgoCD
    echo ""
    echo "4. ArgoCD Status"
    ARGOCD_PODS=$(microk8s kubectl get pods -n argocd --no-headers 2>/dev/null | wc -l)
    ARGOCD_RUNNING=$(microk8s kubectl get pods -n argocd --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    if [ "$ARGOCD_PODS" -eq "$ARGOCD_RUNNING" ] && [ "$ARGOCD_PODS" -gt 0 ]; then
        log_success "ArgoCD: $ARGOCD_RUNNING/$ARGOCD_PODS pods running"
    else
        log_warning "ArgoCD: $ARGOCD_RUNNING/$ARGOCD_PODS pods running"
    fi

    # Check ArgoCD applications
    microk8s kubectl get applications -n argocd --no-headers 2>/dev/null | while read app sync health rest; do
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
    echo "5. Monitoring Stack"
    PROM_STATUS=$(microk8s kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    ALERT_STATUS=$(microk8s kubectl get pods -n monitoring -l app.kubernetes.io/name=alertmanager --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    GRAFANA_STATUS=$(microk8s kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

    [ "$PROM_STATUS" -gt 0 ] && log_success "Prometheus: Running" || log_warning "Prometheus: Not running"
    [ "$ALERT_STATUS" -gt 0 ] && log_success "Alertmanager: Running" || log_warning "Alertmanager: Not running"
    [ "$GRAFANA_STATUS" -gt 0 ] && log_success "Grafana: Running" || log_warning "Grafana: Not running"

    # Check for failing Grafana pods and fix
    GRAFANA_FAILING=$(microk8s kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null | wc -l)
    if [ "$GRAFANA_FAILING" -gt 0 ]; then
        log_warning "Found $GRAFANA_FAILING failing Grafana pod(s). Auto-fixing..."
        microk8s kubectl delete pods -n monitoring -l app.kubernetes.io/name=grafana --field-selector=status.phase!=Running,status.phase!=Succeeded --ignore-not-found=true
    fi
    echo ""

    # Check Airflow
    echo "6. Airflow Status"
    AIRFLOW_PODS=$(microk8s kubectl get pods -n airflow --no-headers 2>/dev/null | wc -l)
    AIRFLOW_RUNNING=$(microk8s kubectl get pods -n airflow --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    if [ "$AIRFLOW_PODS" -eq "$AIRFLOW_RUNNING" ] && [ "$AIRFLOW_PODS" -gt 0 ]; then
        log_success "Airflow: $AIRFLOW_RUNNING/$AIRFLOW_PODS pods running"
    else
        log_warning "Airflow: $AIRFLOW_RUNNING/$AIRFLOW_PODS pods running"
    fi

    # Check specific components
    for component in webserver scheduler triggerer worker; do
        STATUS=$(microk8s kubectl get pods -n airflow -l component=$component --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        [ "$STATUS" -gt 0 ] && log_success "  $component: Running" || log_warning "  $component: Not running"
    done
    echo ""

    # Check PVC status
    echo "7. Persistent Volume Claims"
    PVC_TOTAL=$(microk8s kubectl get pvc --all-namespaces --no-headers 2>/dev/null | wc -l)
    PVC_BOUND=$(microk8s kubectl get pvc --all-namespaces --field-selector=status.phase=Bound --no-headers 2>/dev/null | wc -l)
    if [ "$PVC_TOTAL" -eq 0 ] || [ "$PVC_TOTAL" -eq "$PVC_BOUND" ]; then
        log_success "All PVCs bound: $PVC_BOUND/$PVC_TOTAL"
    else
        log_warning "PVCs: $PVC_BOUND/$PVC_TOTAL bound"
    fi
    echo ""

    echo "=========================================="
    log_success "Health check completed - monitoring continues"
    echo "=========================================="
    
    # Wait before next check (2 minutes)
    sleep 120
done
