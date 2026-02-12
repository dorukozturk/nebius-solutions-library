#!/bin/bash
#
# Configure OSMO Service URL
# Required for osmo-ctrl sidecar to communicate with OSMO service
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/defaults.sh"

echo ""
echo "========================================"
echo "  OSMO Service URL Configuration"
echo "========================================"
echo ""

# Check prerequisites
check_kubectl || exit 1

# -----------------------------------------------------------------------------
# Start port-forward
# -----------------------------------------------------------------------------
log_info "Starting port-forward to OSMO service..."

kubectl port-forward -n osmo svc/osmo-service 8080:80 &>/dev/null &
PORT_FORWARD_PID=$!

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

# Login
log_info "Logging in to OSMO..."
if ! osmo login http://localhost:8080 --method dev --username admin 2>/dev/null; then
    log_error "Failed to login to OSMO"
    exit 1
fi
log_success "Logged in successfully"

# -----------------------------------------------------------------------------
# Determine the target service URL
# -----------------------------------------------------------------------------
log_info "Determining target service URL..."

# Priority:
#   1. Explicit OSMO_INGRESS_BASE_URL (user override)
#   2. Auto-detect from NGINX Ingress Controller LoadBalancer
if [[ -n "${OSMO_INGRESS_BASE_URL:-}" ]]; then
    SERVICE_URL="${OSMO_INGRESS_BASE_URL}"
    log_info "Using explicit Ingress base URL: ${SERVICE_URL}"
elif DETECTED_URL=$(detect_service_url 2>/dev/null) && [[ -n "$DETECTED_URL" ]]; then
    SERVICE_URL="${DETECTED_URL}"
    log_info "Auto-detected service URL: ${SERVICE_URL}"
else
    log_error "Could not detect NGINX Ingress Controller URL."
    log_error "Ensure 03-deploy-nginx-ingress.sh was run and the LoadBalancer has an IP."
    log_error "Or set OSMO_INGRESS_BASE_URL manually: export OSMO_INGRESS_BASE_URL=http://<lb-ip>"
    exit 1
fi

# -----------------------------------------------------------------------------
# Check current service_base_url
# -----------------------------------------------------------------------------
log_info "Checking current service_base_url..."

CURRENT_URL=$(curl -s "http://localhost:8080/api/configs/service" 2>/dev/null | jq -r '.service_base_url // ""')
echo "Current service_base_url: '${CURRENT_URL}'"

if [[ -n "$CURRENT_URL" && "$CURRENT_URL" != "null" && "$CURRENT_URL" == "$SERVICE_URL" ]]; then
    log_success "service_base_url is already correctly configured: ${CURRENT_URL}"
    cleanup_port_forward
    trap - EXIT
    exit 0
elif [[ -n "$CURRENT_URL" && "$CURRENT_URL" != "null" ]]; then
    log_warning "service_base_url is set to '${CURRENT_URL}' but should be '${SERVICE_URL}'"
    log_info "Updating service_base_url..."
fi

# -----------------------------------------------------------------------------
# Configure service_base_url
# -----------------------------------------------------------------------------
log_info "Configuring service_base_url to: ${SERVICE_URL}"

cat > /tmp/service_url_fix.json << EOF
{
  "service_base_url": "${SERVICE_URL}"
}
EOF

if osmo config update SERVICE --file /tmp/service_url_fix.json --description "Set service_base_url for osmo-ctrl sidecar" 2>/dev/null; then
    log_success "service_base_url configured"
else
    log_error "Failed to configure service_base_url"
    rm -f /tmp/service_url_fix.json
    exit 1
fi

rm -f /tmp/service_url_fix.json

# -----------------------------------------------------------------------------
# Verify Configuration
# -----------------------------------------------------------------------------
log_info "Verifying configuration..."

NEW_URL=$(curl -s "http://localhost:8080/api/configs/service" 2>/dev/null | jq -r '.service_base_url // ""')

if [[ "$NEW_URL" == "$SERVICE_URL" ]]; then
    log_success "service_base_url verified: ${NEW_URL}"
else
    log_error "Verification failed. Expected: ${SERVICE_URL}, Got: ${NEW_URL}"
    exit 1
fi

# Cleanup
cleanup_port_forward
trap - EXIT

echo ""
echo "========================================"
log_success "OSMO Service URL configuration complete!"
echo "========================================"
echo ""
echo "Service URL: ${SERVICE_URL}"
echo ""
echo "This URL is used by the osmo-ctrl sidecar container to:"
echo "  - Stream workflow logs to the OSMO service"
echo "  - Report task status and completion"
echo "  - Fetch authentication tokens"
echo ""
