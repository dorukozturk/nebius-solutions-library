#!/bin/bash
#
# Deploy OSMO Backend Operator
# https://nvidia.github.io/OSMO/main/deployment_guide/install_backend/deploy_backend.html
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/defaults.sh"

echo ""
echo "========================================"
echo "  OSMO Backend Operator Deployment"
echo "========================================"
echo ""

# Check prerequisites
check_kubectl || exit 1
check_helm || exit 1

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
OSMO_OPERATOR_NAMESPACE="osmo-operator"
OSMO_WORKFLOWS_NAMESPACE="osmo-workflows"
OSMO_IMAGE_TAG="${OSMO_IMAGE_TAG:-6.0.0}"
OSMO_CHART_VERSION="${OSMO_CHART_VERSION:-}"
BACKEND_NAME="${OSMO_BACKEND_NAME:-default}"

# Check for OSMO Service URL (in-cluster URL for the backend operator pods)
# IMPORTANT: Backend operators connect via WebSocket to osmo-agent, NOT osmo-service!
# The osmo-service handles REST API, osmo-agent handles WebSocket connections for backends
if [[ -z "${OSMO_SERVICE_URL:-}" ]]; then
    log_info "Auto-detecting in-cluster OSMO Agent URL..."
    
    # Backend operators MUST connect to osmo-agent for WebSocket connections
    # The osmo-service WebSocket routes only exist in dev mode
    OSMO_AGENT=$(kubectl get svc -n osmo osmo-agent -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$OSMO_AGENT" ]]; then
        OSMO_SERVICE_URL="http://osmo-agent.osmo.svc.cluster.local:80"
        log_success "In-cluster Agent URL: ${OSMO_SERVICE_URL}"
    else
        # Fallback: try to detect from any osmo-agent service
        OSMO_AGENT=$(kubectl get svc -n osmo -l app.kubernetes.io/name=agent -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [[ -n "$OSMO_AGENT" ]]; then
            OSMO_SERVICE_URL="http://${OSMO_AGENT}.osmo.svc.cluster.local:80"
            log_success "In-cluster Agent URL: ${OSMO_SERVICE_URL}"
        else
            echo ""
            log_error "Could not detect OSMO Agent service. Deploy OSMO first: ./04-deploy-osmo-control-plane.sh"
            log_error "Note: Backend operators require osmo-agent service for WebSocket connections"
            exit 1
        fi
    fi
fi

# Check for OSMO Service Token
if [[ -z "${OSMO_SERVICE_TOKEN:-}" ]]; then
    # First, ensure namespace exists so we can check for existing secret
    kubectl create namespace "${OSMO_OPERATOR_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
    
    # Check if token secret already exists in cluster
    EXISTING_TOKEN=$(kubectl get secret osmo-operator-token -n "${OSMO_OPERATOR_NAMESPACE}" -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || echo "")
    
    if [[ -n "$EXISTING_TOKEN" ]]; then
        log_info "Using existing token from secret osmo-operator-token"
        OSMO_SERVICE_TOKEN="$EXISTING_TOKEN"
    elif command -v osmo &>/dev/null; then
        # Check if osmo CLI is already logged in (don't try to login with in-cluster URL)
        log_info "Checking if OSMO CLI is already logged in..."
        
        # Try to generate token - this only works if CLI is already logged in
        TOKEN_NAME="backend-token-$(date -u +%Y%m%d%H%M%S)"
        EXPIRY_DATE=$(date -u -d "+1 year" +%F 2>/dev/null || date -u -v+1y +%F 2>/dev/null || echo "2027-01-01")
        
        TOKEN_JSON=$(osmo token set "$TOKEN_NAME" \
            --expires-at "$EXPIRY_DATE" \
            --description "Backend Operator Token" \
            --service --roles osmo-backend -t json 2>/dev/null || echo "")
        
        if [[ -n "$TOKEN_JSON" ]]; then
            OSMO_SERVICE_TOKEN=$(echo "$TOKEN_JSON" | jq -r '.token // empty' 2>/dev/null || echo "")
        fi
        
        if [[ -n "$OSMO_SERVICE_TOKEN" ]]; then
            log_success "Service token generated: $TOKEN_NAME (expires: $EXPIRY_DATE)"
        fi
    fi
    
    # If still no token, automatically create one using port-forward
    if [[ -z "$OSMO_SERVICE_TOKEN" ]]; then
        log_info "No token found - automatically creating service token..."
        
        # Check if osmo CLI is available
        if ! command -v osmo &>/dev/null; then
            log_error "osmo CLI not found. Please install it first."
            exit 1
        fi
        
        # Start port-forward in background
        log_info "Starting port-forward to OSMO service..."
        kubectl port-forward -n osmo svc/osmo-service 8080:80 &>/dev/null &
        PORT_FORWARD_PID=$!
        
        # Cleanup function to kill port-forward on exit
        cleanup_port_forward() {
            if [[ -n "${PORT_FORWARD_PID:-}" ]]; then
                kill $PORT_FORWARD_PID 2>/dev/null || true
                wait $PORT_FORWARD_PID 2>/dev/null || true
            fi
        }
        trap cleanup_port_forward EXIT
        
        # Wait for port-forward to be ready
        log_info "Waiting for port-forward to be ready..."
        max_wait=30
        elapsed=0
        while ! curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/version" 2>/dev/null | grep -q "200\|401\|403"; do
            sleep 1
            ((elapsed += 1))
            if [[ $elapsed -ge $max_wait ]]; then
                log_error "Port-forward failed to start within ${max_wait}s"
                exit 1
            fi
        done
        log_success "Port-forward ready"
        
        # Login with dev method (since auth is disabled)
        log_info "Logging in to OSMO (dev method)..."
        if ! osmo login http://localhost:8080 --method dev --username admin 2>/dev/null; then
            log_error "Failed to login to OSMO"
            exit 1
        fi
        log_success "Logged in successfully"
        
        # Create service token
        TOKEN_NAME="backend-token-$(date -u +%Y%m%d%H%M%S)"
        EXPIRY_DATE=$(date -u -d "+1 year" +%F 2>/dev/null || date -u -v+1y +%F 2>/dev/null || echo "2027-01-01")
        
        log_info "Creating service token: $TOKEN_NAME (expires: $EXPIRY_DATE)..."
        TOKEN_OUTPUT=$(osmo token set "$TOKEN_NAME" \
            --expires-at "$EXPIRY_DATE" \
            --description "Backend Operator Token (auto-generated)" \
            --service --roles osmo-backend 2>&1)
        
        # Extract token from output (format: "Access token: <token>")
        OSMO_SERVICE_TOKEN=$(echo "$TOKEN_OUTPUT" | sed -n 's/.*Access token: //p' | tr -d '\r' | xargs)

        if [[ -z "$OSMO_SERVICE_TOKEN" ]]; then
            log_error "Failed to create service token"
            echo "Output: $TOKEN_OUTPUT"
            exit 1
        fi
        
        log_success "Service token created successfully"
        
        # Stop port-forward (we're done with it)
        cleanup_port_forward
        trap - EXIT
    fi
fi

# -----------------------------------------------------------------------------
# Add OSMO Helm Repository
# -----------------------------------------------------------------------------
log_info "Adding OSMO Helm repository..."
helm repo add osmo https://helm.ngc.nvidia.com/nvidia/osmo --force-update
helm repo update

# -----------------------------------------------------------------------------
# Create Namespaces
# -----------------------------------------------------------------------------
log_info "Creating namespaces..."
kubectl create namespace "${OSMO_OPERATOR_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "${OSMO_WORKFLOWS_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# -----------------------------------------------------------------------------
# Create Secrets
# -----------------------------------------------------------------------------
log_info "Creating operator token secret..."
kubectl create secret generic osmo-operator-token \
    --namespace "${OSMO_OPERATOR_NAMESPACE}" \
    --from-literal=token="${OSMO_SERVICE_TOKEN}" \
    --dry-run=client -o yaml | kubectl apply -f -

# -----------------------------------------------------------------------------
# Create Values File
# -----------------------------------------------------------------------------
log_info "Creating Helm values file..."

# Note: services.backendListener/Worker are at root level, not under global
# See: osmo-helm-charts/backend-operator/values.yaml
cat > /tmp/backend_operator_values.yaml <<EOF
global:
  osmoImageTag: "${OSMO_IMAGE_TAG}"
  serviceUrl: "${OSMO_SERVICE_URL}"
  agentNamespace: "${OSMO_OPERATOR_NAMESPACE}"
  backendNamespace: "${OSMO_WORKFLOWS_NAMESPACE}"
  backendName: "${BACKEND_NAME}"
  accountTokenSecret: osmo-operator-token
  accountTokenSecretKey: token
  loginMethod: token
  
  # Node selector to prefer system/CPU nodes (not GPU nodes)
  nodeSelector:
    kubernetes.io/os: linux
  
  # Logging configuration
  logs:
    logLevel: DEBUG
    k8sLogLevel: WARNING

# Service-specific configurations (at root level, not under global)
services:
  backendListener:
    resources:
      requests:
        cpu: "100m"
        memory: "256Mi"
      limits:
        memory: "1Gi"
  
  backendWorker:
    resources:
      requests:
        cpu: "100m"
        memory: "256Mi"
      limits:
        memory: "1Gi"

# Disable test runner for initial deployment
backendTestRunner:
  enabled: false
EOF

# -----------------------------------------------------------------------------
# Deploy Backend Operator
# -----------------------------------------------------------------------------
log_info "Deploying OSMO Backend Operator..."

HELM_ARGS=(
    --namespace "${OSMO_OPERATOR_NAMESPACE}"
    -f /tmp/backend_operator_values.yaml
    --wait
    --timeout 10m
)

if [[ -n "${OSMO_CHART_VERSION}" ]]; then
    HELM_ARGS+=(--version "${OSMO_CHART_VERSION}")
fi

helm upgrade --install osmo-operator osmo/backend-operator "${HELM_ARGS[@]}"

log_success "OSMO Backend Operator deployed"

# Cleanup temp file
rm -f /tmp/backend_operator_values.yaml

# -----------------------------------------------------------------------------
# Verify Deployment
# -----------------------------------------------------------------------------
echo ""
log_info "Verifying deployment..."

kubectl get pods -n "${OSMO_OPERATOR_NAMESPACE}"
kubectl get pods -n "${OSMO_WORKFLOWS_NAMESPACE}" 2>/dev/null || true

echo ""
echo "========================================"
log_success "OSMO Backend Operator deployment complete!"
echo "========================================"
echo ""
echo "Backend Name: ${BACKEND_NAME}"
echo "Agent URL (WebSocket): ${OSMO_SERVICE_URL}"
echo ""
# Detect Ingress URL for verification instructions
INGRESS_URL=$(detect_service_url 2>/dev/null || true)

echo "To verify the backend registration:"
echo ""
if [[ -n "$INGRESS_URL" ]]; then
    echo "  Check backend status:"
    echo "    osmo config show BACKEND ${BACKEND_NAME}"
    echo ""
    echo "  Or via curl (using NGINX Ingress LoadBalancer):"
    echo "    curl ${INGRESS_URL}/api/configs/backend"
else
    echo "  Terminal 1 - Start port-forward (keep running):"
    echo "    kubectl port-forward -n osmo svc/osmo-service 8080:80"
    echo ""
    echo "  Terminal 2 - Check backend status:"
    echo "    osmo config show BACKEND ${BACKEND_NAME}"
    echo ""
    echo "  Or via curl:"
    echo "    curl http://localhost:8080/api/configs/backend"
fi
echo ""
echo "Next step - Configure Storage:"
echo "  ./06-configure-storage.sh"
echo ""
