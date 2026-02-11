#!/bin/bash
# Configure OSMO GPU platform with tolerations via pod templates
# Based on OSMO documentation: https://nvidia.github.io/OSMO/main/deployment_guide/install_backend/resource_pools.html

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

OSMO_URL="${OSMO_URL:-http://localhost:8080}"
OSMO_NAMESPACE="${OSMO_NAMESPACE:-osmo}"

echo ""
echo "========================================"
echo "  OSMO GPU Platform Configuration"
echo "========================================"
echo ""

# Check prerequisites
check_kubectl || exit 1

# -----------------------------------------------------------------------------
# Start port-forward
# -----------------------------------------------------------------------------
log_info "Starting port-forward to OSMO service..."

kubectl port-forward -n "${OSMO_NAMESPACE}" svc/osmo-service 8080:80 &>/dev/null &
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
while ! curl -s -o /dev/null -w "%{http_code}" "${OSMO_URL}/api/version" 2>/dev/null | grep -q "200\|401\|403"; do
    sleep 1
    ((elapsed += 1))
    if [[ $elapsed -ge $max_wait ]]; then
        log_error "Port-forward failed to start within ${max_wait}s"
        exit 1
    fi
done
log_success "Port-forward ready"

# -----------------------------------------------------------------------------
# Step 1: Create GPU pod template
# -----------------------------------------------------------------------------
log_info "Creating gpu_tolerations pod template..."

RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
  "${OSMO_URL}/api/configs/pod_template/gpu_tolerations" \
  -H "Content-Type: application/json" \
  -d @"${SCRIPT_DIR}/gpu_pod_template.json")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
    log_success "Pod template created (HTTP ${HTTP_CODE})"
else
    log_error "Failed to create pod template (HTTP ${HTTP_CODE})"
    echo "Response: ${BODY}"
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 2: Create GPU platform
# -----------------------------------------------------------------------------
log_info "Creating gpu platform in default pool..."

RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
  "${OSMO_URL}/api/configs/pool/default/platform/gpu" \
  -H "Content-Type: application/json" \
  -d @"${SCRIPT_DIR}/gpu_platform_update.json")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
    log_success "GPU platform created (HTTP ${HTTP_CODE})"
else
    log_error "Failed to create GPU platform (HTTP ${HTTP_CODE})"
    echo "Response: ${BODY}"
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 3: Verify configuration
# -----------------------------------------------------------------------------
log_info "Verifying configuration..."

echo ""
echo "Pod templates:"
curl -s "${OSMO_URL}/api/configs/pod_template" | jq 'keys'

echo ""
echo "GPU platform config:"
curl -s "${OSMO_URL}/api/configs/pool/default" | jq '.platforms.gpu'

# -----------------------------------------------------------------------------
# Step 4: Check GPU resources
# -----------------------------------------------------------------------------
log_info "Checking GPU resources..."
sleep 3  # Wait for backend to pick up changes

RESOURCE_COUNT=$(curl -s "${OSMO_URL}/api/resources" | jq '[.resources[] | select(.allocatable_fields.gpu != null)] | length')
echo "GPU nodes visible to OSMO: ${RESOURCE_COUNT}"

if [[ "$RESOURCE_COUNT" -gt 0 ]]; then
    echo ""
    echo "GPU resources:"
    curl -s "${OSMO_URL}/api/resources" | jq '.resources[] | select(.allocatable_fields.gpu != null) | {name: .name, gpu: .allocatable_fields.gpu, cpu: .allocatable_fields.cpu, memory: .allocatable_fields.memory}'
fi

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
log_success "GPU platform configuration complete"
echo ""
echo "To submit a GPU workflow:"
echo "  osmo workflow submit workflows/osmo/gpu_test.yaml -p default"
echo ""
echo "Or test via curl:"
echo "  curl -X POST ${OSMO_URL}/api/workflow -H 'Content-Type: application/yaml' --data-binary @workflows/osmo/gpu_test.yaml"
