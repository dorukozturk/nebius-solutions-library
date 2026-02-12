#!/bin/bash
# Configure OSMO GPU platform with tolerations via pod templates
# Based on OSMO documentation: https://nvidia.github.io/OSMO/main/deployment_guide/install_backend/resource_pools.html

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/defaults.sh"

OSMO_NAMESPACE="${OSMO_NAMESPACE:-osmo}"

echo ""
echo "========================================"
echo "  OSMO GPU Platform Configuration"
echo "========================================"
echo ""

# Check prerequisites
check_kubectl || exit 1

# -----------------------------------------------------------------------------
# Start port-forward (auto-detects Envoy and bypasses if needed)
# -----------------------------------------------------------------------------
log_info "Starting port-forward to OSMO service..."
start_osmo_port_forward "${OSMO_NAMESPACE}" 8080
export _OSMO_PORT=8080

cleanup_port_forward() {
    if [[ -n "${PORT_FORWARD_PID:-}" ]]; then
        kill $PORT_FORWARD_PID 2>/dev/null || true
        wait $PORT_FORWARD_PID 2>/dev/null || true
    fi
}
trap cleanup_port_forward EXIT

OSMO_URL="http://localhost:8080"

# Wait for port-forward to be ready (reject 302 — that means Envoy redirect, not direct)
log_info "Waiting for port-forward to be ready..."
max_wait=30
elapsed=0
while true; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${OSMO_URL}/api/version" 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "200" ]]; then
        break
    fi
    sleep 1
    ((elapsed += 1))
    if [[ $elapsed -ge $max_wait ]]; then
        log_error "Port-forward failed to start within ${max_wait}s (last HTTP: ${HTTP_CODE})"
        exit 1
    fi
done
log_success "Port-forward ready"

# Login (no-op when bypassing Envoy)
osmo_login 8080

# -----------------------------------------------------------------------------
# Step 0: Label nodes with OSMO pool/platform
# -----------------------------------------------------------------------------
# OSMO discovers resources via node labels:
#   osmo.nvidia.com/pool=<pool>        — assigns node to a pool
#   osmo.nvidia.com/platform=<platform> — assigns node to a platform within the pool
# GPU nodes get platform=gpu, CPU-only nodes get platform=default.
log_info "Labeling nodes with OSMO pool/platform..."

NODE_COUNT=0
GPU_NODE_COUNT=0
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
    has_gpu=$(kubectl get node "$node" -o jsonpath='{.metadata.labels.nvidia\.com/gpu\.present}' 2>/dev/null)
    gpu_count=$(kubectl get node "$node" -o jsonpath='{.status.allocatable.nvidia\.com/gpu}' 2>/dev/null)

    kubectl label node "$node" osmo.nvidia.com/pool=default --overwrite &>/dev/null

    if [[ "$has_gpu" == "true" ]] || [[ -n "$gpu_count" && "$gpu_count" -gt 0 ]] 2>/dev/null; then
        kubectl label node "$node" osmo.nvidia.com/platform=gpu --overwrite &>/dev/null
        ((GPU_NODE_COUNT++)) || true
    else
        kubectl label node "$node" osmo.nvidia.com/platform=default --overwrite &>/dev/null
    fi
    ((NODE_COUNT++)) || true
done

log_success "Labeled ${NODE_COUNT} nodes (${GPU_NODE_COUNT} GPU, $((NODE_COUNT - GPU_NODE_COUNT)) CPU-only)"

# Give the backend listener time to process node label changes
sleep 5

# -----------------------------------------------------------------------------
# Step 1: Create GPU pod template
# -----------------------------------------------------------------------------
log_info "Creating gpu_tolerations pod template..."

RESPONSE=$(osmo_curl PUT "${OSMO_URL}/api/configs/pod_template/gpu_tolerations" \
  -d @"${SCRIPT_DIR}/gpu_pod_template.json" \
  -w "\n%{http_code}")
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

RESPONSE=$(osmo_curl PUT "${OSMO_URL}/api/configs/pool/default/platform/gpu" \
  -d @"${SCRIPT_DIR}/gpu_platform_update.json" \
  -w "\n%{http_code}")
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
osmo_curl GET "${OSMO_URL}/api/configs/pod_template" | jq 'keys'

echo ""
echo "GPU platform config:"
osmo_curl GET "${OSMO_URL}/api/configs/pool/default" | jq '.platforms.gpu'

# -----------------------------------------------------------------------------
# Step 4: Check GPU resources
# -----------------------------------------------------------------------------
log_info "Checking GPU resources..."
sleep 3  # Wait for backend to pick up changes

RESOURCE_COUNT=$(osmo_curl GET "${OSMO_URL}/api/resources" | jq '[.resources[] | select(.allocatable_fields.gpu != null)] | length')
echo "GPU nodes visible to OSMO: ${RESOURCE_COUNT}"

if [[ "$RESOURCE_COUNT" -gt 0 ]]; then
    echo ""
    echo "GPU resources:"
    osmo_curl GET "${OSMO_URL}/api/resources" | jq '.resources[] | select(.allocatable_fields.gpu != null) | {name: .name, gpu: .allocatable_fields.gpu, cpu: .allocatable_fields.cpu, memory: .allocatable_fields.memory}'
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
echo ""
