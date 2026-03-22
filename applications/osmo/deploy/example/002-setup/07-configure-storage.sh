#!/bin/bash
#
# Configure OSMO Storage
# https://nvidia.github.io/OSMO/main/deployment_guide/getting_started/configure_data_storage.html
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/defaults.sh"

echo ""
echo "========================================"
echo "  OSMO Storage Configuration"
echo "========================================"
echo ""

# Check prerequisites
check_kubectl || exit 1

# -----------------------------------------------------------------------------
# Get Storage Configuration from Terraform
# -----------------------------------------------------------------------------
log_info "Retrieving storage configuration from Terraform..."

S3_BUCKET=$(get_tf_output "storage_bucket.name" "../001-iac" 2>/dev/null || echo "")
S3_ENDPOINT=$(get_tf_output "storage_bucket.endpoint" "../001-iac" 2>/dev/null || echo "")

# Require NEBIUS_REGION (set by nebius-env-init.sh)
if [[ -z "${NEBIUS_REGION:-}" ]]; then
    log_error "NEBIUS_REGION is not set. Run 'source ../000-prerequisites/nebius-env-init.sh' first."
    exit 1
fi

# Default endpoint if not set
if [[ -z "$S3_ENDPOINT" ]]; then
    S3_ENDPOINT="https://storage.${NEBIUS_REGION}.nebius.cloud"
fi

if [[ -z "$S3_BUCKET" ]]; then
    log_error "Could not retrieve storage bucket name from Terraform"
    echo ""
    echo "Make sure you have run 'terraform apply' in deploy/001-iac"
    echo "and that storage is enabled in your terraform.tfvars"
    exit 1
fi

log_success "Storage bucket: ${S3_BUCKET}"
log_success "Storage endpoint: ${S3_ENDPOINT}"

# -----------------------------------------------------------------------------
# Check/Create osmo-storage secret
# -----------------------------------------------------------------------------
log_info "Checking for osmo-storage secret..."

if ! kubectl get secret osmo-storage -n osmo &>/dev/null; then
    log_warning "osmo-storage secret not found - attempting to create from MysteryBox..."
    
    # Get credentials from Terraform/MysteryBox
    S3_ACCESS_KEY=$(get_tf_output "storage_credentials.access_key_id" "../001-iac" 2>/dev/null || echo "")
    S3_SECRET_REF_ID=$(get_tf_output "storage_secret_reference_id" "../001-iac" 2>/dev/null || echo "")
    S3_SECRET_KEY=""
    
    if [[ -n "$S3_SECRET_REF_ID" ]]; then
        log_info "Retrieving storage secret from MysteryBox..."
        # IAM access key secrets are stored with key "secret" in MysteryBox
        S3_SECRET_KEY=$(get_mysterybox_secret "$S3_SECRET_REF_ID" "secret" 2>/dev/null || echo "")
    fi
    
    if [[ -z "$S3_ACCESS_KEY" || -z "$S3_SECRET_KEY" ]]; then
        log_error "Could not retrieve storage credentials"
        echo ""
        echo "Either re-run 04-deploy-osmo-control-plane.sh or create the secret manually:"
        echo ""
        echo "  kubectl create secret generic osmo-storage \\"
        echo "    --namespace osmo \\"
        echo "    --from-literal=access-key-id=<your-access-key> \\"
        echo "    --from-literal=secret-access-key=<your-secret-key>"
        exit 1
    fi
    
    # Create the secret
    kubectl create secret generic osmo-storage \
        --namespace osmo \
        --from-literal=access-key-id="${S3_ACCESS_KEY}" \
        --from-literal=secret-access-key="${S3_SECRET_KEY}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "osmo-storage secret created"
else
    log_success "osmo-storage secret exists"
fi

# -----------------------------------------------------------------------------
# Start port-forward and configure storage
# -----------------------------------------------------------------------------
log_info "Starting port-forward to OSMO service..."

OSMO_NS="${OSMO_NAMESPACE:-osmo}"

if ! start_osmo_api_session "${OSMO_NS}" 8080 60; then
    log_error "Port-forward failed to start within 60s"
    echo "  Check: kubectl get pods -n ${OSMO_NS} -l app=osmo-service"
    exit 1
fi
OSMO_URL="${OSMO_API_URL}"

# Cleanup function
cleanup_port_forward() {
    stop_port_forward
}
trap cleanup_port_forward EXIT

log_success "Port-forward ready at ${OSMO_URL}"

# Login (no-op when bypassing Envoy -- curl headers handle auth)
osmo_login "${OSMO_API_PORT}" || exit 1

# -----------------------------------------------------------------------------
# Get Storage Credentials
# -----------------------------------------------------------------------------
log_info "Retrieving storage credentials..."

# Get access key from Terraform
S3_ACCESS_KEY=$(get_tf_output "storage_credentials.access_key_id" "../001-iac" 2>/dev/null || echo "")

# Get secret key from osmo-storage secret (already created)
S3_SECRET_KEY=$(kubectl get secret osmo-storage -n osmo -o jsonpath='{.data.secret-access-key}' 2>/dev/null | base64 -d 2>/dev/null || echo "")

if [[ -z "$S3_ACCESS_KEY" || -z "$S3_SECRET_KEY" ]]; then
    log_error "Could not retrieve storage credentials"
    exit 1
fi

# Nebius Object Storage uses an S3-compatible API.
# For OSMO workflow storage, use the S3 credential schema explicitly:
#   endpoint     = s3://<bucket>
#   override_url = https://storage.<region>.nebius.cloud
#   region       = <region>
# This matches the dataset-bucket configuration and avoids the stale
# `tos://...` workflow storage format that led to runtime "Invalid region"
# errors during UploadWorkflowFiles.
BACKEND_URI="s3://${S3_BUCKET}"
OVERRIDE_URL="${S3_ENDPOINT}"
REGION="${NEBIUS_REGION}"

log_success "Storage credentials retrieved"

# -----------------------------------------------------------------------------
# Configure Workflow Log Storage in OSMO
# -----------------------------------------------------------------------------
log_info "Configuring workflow log storage..."

# Create workflow log config JSON
WORKFLOW_LOG_CONFIG=$(cat <<EOF
{
  "workflow_log": {
    "credential": {
      "endpoint": "${BACKEND_URI}",
      "override_url": "${OVERRIDE_URL}",
      "access_key_id": "${S3_ACCESS_KEY}",
      "access_key": "${S3_SECRET_KEY}",
      "region": "${REGION}"
    }
  }
}
EOF
)

# Write to temp file for osmo CLI
echo "$WORKFLOW_LOG_CONFIG" > /tmp/workflow_log_config.json

if osmo_config_update WORKFLOW /tmp/workflow_log_config.json "Configure workflow log storage" "${OSMO_API_PORT}"; then
    log_success "Workflow log storage configured"
else
    log_error "Failed to configure workflow log storage"
    rm -f /tmp/workflow_log_config.json
    exit 1
fi

# -----------------------------------------------------------------------------
# Configure Workflow Data Storage in OSMO
# -----------------------------------------------------------------------------
log_info "Configuring workflow data storage..."

# Create workflow data config JSON
WORKFLOW_DATA_CONFIG=$(cat <<EOF
{
  "workflow_data": {
    "credential": {
      "endpoint": "${BACKEND_URI}",
      "override_url": "${OVERRIDE_URL}",
      "access_key_id": "${S3_ACCESS_KEY}",
      "access_key": "${S3_SECRET_KEY}",
      "region": "${REGION}"
    }
  }
}
EOF
)

# Write to temp file for osmo CLI
echo "$WORKFLOW_DATA_CONFIG" > /tmp/workflow_data_config.json

if osmo_config_update WORKFLOW /tmp/workflow_data_config.json "Configure workflow data storage" "${OSMO_API_PORT}"; then
    log_success "Workflow data storage configured"
else
    log_error "Failed to configure workflow data storage"
    rm -f /tmp/workflow_log_config.json /tmp/workflow_data_config.json
    exit 1
fi

# Cleanup temp files
rm -f /tmp/workflow_log_config.json /tmp/workflow_data_config.json

# -----------------------------------------------------------------------------
# Configure Workflow Limits
# -----------------------------------------------------------------------------
log_info "Configuring workflow limits (max_num_tasks=200)..."

WORKFLOW_LIMITS_CONFIG=$(cat <<EOF
{
  "max_num_tasks": 200
}
EOF
)

echo "$WORKFLOW_LIMITS_CONFIG" > /tmp/workflow_limits_config.json

if osmo_config_update WORKFLOW /tmp/workflow_limits_config.json "Configure workflow limits" "${OSMO_API_PORT}"; then
    log_success "Workflow limits configured (max_num_tasks=200)"
else
    log_warning "Failed to configure workflow limits (may require newer OSMO version)"
fi

rm -f /tmp/workflow_limits_config.json

# -----------------------------------------------------------------------------
# Restart components that cache workflow storage config
# -----------------------------------------------------------------------------
# OSMO worker uploads workflow specs/logs to object storage. Service reads them
# back for UI/API access. After changing WORKFLOW storage config, restart both
# so new submissions do not keep using stale region/endpoint settings.
log_info "Restarting OSMO components to reload workflow storage config..."

for deploy in osmo-worker osmo-service; do
    if kubectl get deployment "$deploy" -n "${OSMO_NS}" >/dev/null 2>&1; then
        if kubectl rollout restart "deployment/${deploy}" -n "${OSMO_NS}" >/dev/null 2>&1; then
            log_info "Waiting for ${deploy} rollout..."
            if kubectl rollout status "deployment/${deploy}" -n "${OSMO_NS}" --timeout=300s >/dev/null 2>&1; then
                log_success "${deploy} restarted"
            else
                log_warning "${deploy} restart did not complete before timeout; verify with: kubectl rollout status deployment/${deploy} -n ${OSMO_NS}"
            fi
        else
            log_warning "Could not restart ${deploy}; verify it manually after storage changes"
        fi
    else
        log_warning "Deployment ${deploy} not found in namespace ${OSMO_NS}"
    fi
done

# -----------------------------------------------------------------------------
# Verify Configuration
# -----------------------------------------------------------------------------
log_info "Verifying storage configuration..."

echo ""
echo "Workflow configuration:"
osmo_curl GET "${OSMO_URL}/api/configs/workflow" 2>/dev/null | jq '.' || \
    log_warning "Could not retrieve workflow config for verification"

# Cleanup
cleanup_port_forward
trap - EXIT

echo ""
echo "========================================"
log_success "OSMO Storage configuration complete!"
echo "========================================"
echo ""
echo "Storage Details:"
echo "  Bucket: ${S3_BUCKET}"
echo "  Endpoint: ${S3_ENDPOINT}"
echo "  Backend URI: ${BACKEND_URI}"
echo "  Override URL: ${OVERRIDE_URL}"
echo "  Region: ${REGION}"
echo ""
echo "Configured:"
echo "  - workflow_log: For storing workflow logs"
echo "  - workflow_data: For storing intermediate task data"
echo ""
echo "OSMO can now store workflow artifacts in Nebius Object Storage."
echo ""
