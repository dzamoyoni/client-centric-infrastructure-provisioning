#!/bin/bash
set -euo pipefail

# ============================================================================
# Tempo Health Probe Fix Script
# ============================================================================
# This script automatically fixes the Tempo StatefulSet health probe configuration
# The Tempo Helm chart (v1.23.3) defaults to port 3200, but Tempo serves on 3100
# ============================================================================

# Configuration
NAMESPACE="monitoring"
STATEFULSET_NAME="tempo"
POD_NAME="tempo-0"
CORRECT_PORT="3100"
MAX_RETRIES=3
RETRY_DELAY=5
WAIT_TIMEOUT="300s"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required tools are available
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Test kubectl connection
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Wait for StatefulSet to be ready
wait_for_statefulset() {
    log_info "Waiting for Tempo StatefulSet to be ready..."
    
    if ! kubectl get statefulset "$STATEFULSET_NAME" -n "$NAMESPACE" &>/dev/null; then
        log_error "Tempo StatefulSet '$STATEFULSET_NAME' not found in namespace '$NAMESPACE'"
        return 1
    fi
    
    # Wait for StatefulSet to have ready replicas
    if kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 \
        --timeout=120s statefulset/"$STATEFULSET_NAME" -n "$NAMESPACE" &>/dev/null; then
        log_success "StatefulSet is ready"
        return 0
    else
        log_warn "StatefulSet not ready within timeout, proceeding anyway..."
        return 0
    fi
}

# Get current probe ports
get_probe_ports() {
    local liveness_port readiness_port
    
    liveness_port=$(kubectl get statefulset "$STATEFULSET_NAME" -n "$NAMESPACE" \
        -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet.port}' 2>/dev/null || echo "")
    
    readiness_port=$(kubectl get statefulset "$STATEFULSET_NAME" -n "$NAMESPACE" \
        -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.port}' 2>/dev/null || echo "")
    
    echo "$liveness_port $readiness_port"
}

# Apply probe fix
apply_probe_fix() {
    log_info "Applying health probe fix (setting ports to $CORRECT_PORT)..."
    
    if kubectl patch statefulset "$STATEFULSET_NAME" -n "$NAMESPACE" --type='json' -p="[
        {\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/livenessProbe/httpGet/port\", \"value\": $CORRECT_PORT},
        {\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/readinessProbe/httpGet/port\", \"value\": $CORRECT_PORT}
    ]" &>/dev/null; then
        log_success "Probe fix applied to StatefulSet"
        return 0
    else
        log_error "Failed to apply probe fix"
        return 1
    fi
}

# Restart pod to apply changes
restart_pod() {
    log_info "Restarting Tempo pod to apply new probe configuration..."
    
    if kubectl delete pod "$POD_NAME" -n "$NAMESPACE" --ignore-not-found=true &>/dev/null; then
        log_success "Pod deletion initiated"
    else
        log_warn "Could not delete pod (might not exist)"
    fi
    
    # Wait for pod to be recreated and ready
    log_info "Waiting for pod to be ready (timeout: $WAIT_TIMEOUT)..."
    if kubectl wait --for=condition=ready --timeout="$WAIT_TIMEOUT" pod/"$POD_NAME" -n "$NAMESPACE" &>/dev/null; then
        log_success "Pod is ready with new configuration"
        return 0
    else
        log_warn "Pod not ready within timeout"
        return 1
    fi
}

# Verify the fix
verify_fix() {
    log_info "Verifying probe configuration..."
    
    local ports
    ports=$(get_probe_ports)
    local liveness_port readiness_port
    read -r liveness_port readiness_port <<< "$ports"
    
    if [[ "$liveness_port" == "$CORRECT_PORT" ]] && [[ "$readiness_port" == "$CORRECT_PORT" ]]; then
        log_success "Probe ports correctly configured: Liveness=$liveness_port, Readiness=$readiness_port"
        return 0
    else
        log_error "Probe ports still incorrect: Liveness=$liveness_port, Readiness=$readiness_port"
        return 1
    fi
}

# Main fix function with retry logic
fix_tempo_probes() {
    local retry=0
    
    while [ $retry -lt $MAX_RETRIES ]; do
        log_info "Attempt $((retry + 1)) of $MAX_RETRIES..."
        
        # Get current probe ports
        local ports
        ports=$(get_probe_ports)
        local liveness_port readiness_port
        read -r liveness_port readiness_port <<< "$ports"
        
        if [[ -z "$liveness_port" ]] || [[ -z "$readiness_port" ]]; then
            log_warn "Could not read probe configuration, retrying in ${RETRY_DELAY}s..."
            ((retry++))
            sleep $RETRY_DELAY
            continue
        fi
        
        log_info "Current probe ports - Liveness: $liveness_port, Readiness: $readiness_port"
        
        if [[ "$liveness_port" != "$CORRECT_PORT" ]] || [[ "$readiness_port" != "$CORRECT_PORT" ]]; then
            log_warn "Incorrect probe ports detected, applying fix..."
            
            if apply_probe_fix && restart_pod && verify_fix; then
                log_success "Tempo probe fix completed successfully"
                return 0
            else
                log_warn "Fix attempt failed, retrying in ${RETRY_DELAY}s..."
                ((retry++))
                sleep $RETRY_DELAY
                continue
            fi
        else
            log_success "Probe ports already correct, no fix needed"
            return 0
        fi
    done
    
    log_error "Failed to fix probes after $MAX_RETRIES attempts"
    return 1
}

# Main execution
main() {
    log_info "Starting Tempo health probe fix..."
    log_info "Target: StatefulSet '$STATEFULSET_NAME' in namespace '$NAMESPACE'"
    
    check_prerequisites
    
    if wait_for_statefulset && fix_tempo_probes; then
        log_success "Tempo health probe fix completed successfully!"
        
        # Final status check
        log_info "Final status check..."
        kubectl get pod "$POD_NAME" -n "$NAMESPACE" || log_warn "Could not get pod status"
        
        exit 0
    else
        log_error "Tempo health probe fix failed - manual intervention may be required"
        log_info "Please check the Tempo StatefulSet and pod manually:"
        log_info "  kubectl get statefulset $STATEFULSET_NAME -n $NAMESPACE"
        log_info "  kubectl describe pod $POD_NAME -n $NAMESPACE"
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi