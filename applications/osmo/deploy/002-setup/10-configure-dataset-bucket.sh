#!/bin/bash
#
# Register the Nebius storage bucket as an OSMO dataset bucket.
# This allows using the bucket for OSMO datasets (e.g. osmo dataset upload/list)
# with a short name (e.g. nebius/my-dataset) instead of full URIs.
#
# Requires: 06-configure-storage.sh (port-forward and workflow storage) and
# OSMO control plane running. Uses the same bucket and credentials as workflow storage.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/defaults.sh"

echo ""
echo "========================================"
echo "  OSMO Dataset Bucket Configuration"
echo "========================================"
echo ""

# Optional: name for the bucket in OSMO (default: nebius)
DATASET_BUCKET_NAME="${DATASET_BUCKET_NAME:-nebius}"

# Check prerequisites
check_kubectl || exit 1

# -----------------------------------------------------------------------------
# Select Nebius Region
# -----------------------------------------------------------------------------
VALID_REGIONS=("eu-north1" "me-west1")

if [[ -n "${NEBIUS_REGION:-}" ]]; then
    REGION="$NEBIUS_REGION"
    matched=false
    for r in "${VALID_REGIONS[@]}"; do
        [[ "$r" == "$REGION" ]] && matched=true && break
    done
    if ! $matched; then
        log_error "Invalid NEBIUS_REGION '${REGION}'. Valid options: ${VALID_REGIONS[*]}"
        exit 1
    fi
    log_info "Using region from NEBIUS_REGION: ${REGION}"
else
    echo "Select the Nebius region for the storage bucket:"
    echo ""
    _idx=1
    for _r in "${VALID_REGIONS[@]}"; do
        echo "  ${_idx}) ${_r}"
        _idx=$((_idx + 1))
    done
    echo ""
    while true; do
        printf "Enter choice [1-${#VALID_REGIONS[@]}]: "
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#VALID_REGIONS[@]} )); then
            REGION="${VALID_REGIONS[$choice]}"
            # bash arrays are 0-based, zsh arrays are 1-based; adjust if needed
            if [[ -z "$REGION" ]]; then
                REGION="${VALID_REGIONS[$((choice - 1))]}"
            fi
            break
        fi
        echo "Invalid selection. Please enter a number between 1 and ${#VALID_REGIONS[@]}."
    done
    log_info "Selected region: ${REGION}"
fi

S3_REGION_FOR_BOTO="${REGION}"

# -----------------------------------------------------------------------------
# Get Storage Configuration from Terraform
# -----------------------------------------------------------------------------
log_info "Retrieving storage configuration from Terraform..."

S3_BUCKET=$(get_tf_output "storage_bucket.name" "../001-iac" 2>/dev/null || echo "")
S3_ENDPOINT=$(get_tf_output "storage_bucket.endpoint" "../001-iac" 2>/dev/null || echo "")

if [[ -z "$S3_ENDPOINT" ]]; then
    S3_ENDPOINT="https://storage.${REGION}.nebius.cloud"
fi

if [[ -z "$S3_BUCKET" ]]; then
    log_error "Could not retrieve storage bucket name from Terraform"
    echo ""
    echo "Run 'terraform apply' in deploy/001-iac and ensure storage is enabled."
    exit 1
fi

# Datasets are stored under the osmo-datasets prefix within the bucket.
# The path uses the standard s3://<bucket>/<prefix> format; the actual endpoint
# is configured separately via AWS_ENDPOINT_URL_S3 in the Helm chart / pod template.
DATASET_PATH="s3://${S3_BUCKET}/osmo-datasets"

# -----------------------------------------------------------------------------
# Get storage credentials (for default_credential on the dataset bucket)
# -----------------------------------------------------------------------------
log_info "Retrieving storage credentials for default_credential..."

S3_ACCESS_KEY=$(get_tf_output "storage_credentials.access_key_id" "../001-iac" 2>/dev/null || echo "")
S3_SECRET_KEY=$(kubectl get secret osmo-storage -n "${OSMO_NAMESPACE:-osmo}" -o jsonpath='{.data.secret-access-key}' 2>/dev/null | base64 -d 2>/dev/null || echo "")

if [[ -z "$S3_ACCESS_KEY" ]]; then
    log_warning "Could not get access key from Terraform; bucket will have no default_credential"
fi
if [[ -z "$S3_SECRET_KEY" ]]; then
    S3_SECRET_REF_ID=$(get_tf_output "storage_secret_reference_id" "../001-iac" 2>/dev/null || echo "")
    if [[ -n "$S3_SECRET_REF_ID" ]]; then
        S3_SECRET_KEY=$(get_mysterybox_secret "$S3_SECRET_REF_ID" "secret" 2>/dev/null || echo "")
    fi
fi

if [[ -n "$S3_ACCESS_KEY" && -n "$S3_SECRET_KEY" ]]; then
    log_success "Storage credentials retrieved (default_credential will be set)"
else
    log_warning "Missing credentials; registering bucket without default_credential (users must supply credentials)"
fi

log_success "Bucket: ${S3_BUCKET}"
log_success "Dataset path: ${DATASET_PATH}"
log_success "Region: ${REGION}"
log_success "S3 endpoint: ${S3_ENDPOINT}"
log_success "OSMO bucket name: ${DATASET_BUCKET_NAME}"

# -----------------------------------------------------------------------------
# Start port-forward and configure dataset bucket
# -----------------------------------------------------------------------------
log_info "Starting port-forward to OSMO service..."

OSMO_NS="${OSMO_NAMESPACE:-osmo}"
start_osmo_port_forward "${OSMO_NS}" 8080

cleanup_port_forward() {
    if [[ -n "${PORT_FORWARD_PID:-}" ]]; then
        kill $PORT_FORWARD_PID 2>/dev/null || true
        wait $PORT_FORWARD_PID 2>/dev/null || true
    fi
}
trap cleanup_port_forward EXIT

log_info "Waiting for port-forward..."
max_wait=30
elapsed=0
while ! curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/version" 2>/dev/null | grep -q "200\|401\|403"; do
    sleep 1
    elapsed=$((elapsed + 1))
    if [[ $elapsed -ge $max_wait ]]; then
        log_error "Port-forward failed to start within ${max_wait}s"
        exit 1
    fi
done
log_success "Port-forward ready"

osmo_login 8080 || exit 1

# -----------------------------------------------------------------------------
# Build dataset config: add/update Nebius bucket and set as default bucket
# See: https://nvidia.github.io/OSMO/main/deployment_guide/advanced_config/dataset_buckets.html
# -----------------------------------------------------------------------------
log_info "Building DATASET config (bucket + default_bucket)..."

# Build bucket config object (with optional default_credential)
# PATCH API accepts only access_key_id and access_key in default_credential;
# endpoint/region are taken from the bucket at runtime.
BUCKET_JSON="/tmp/osmo_dataset_bucket_obj.json"
if [[ -n "$S3_ACCESS_KEY" && -n "$S3_SECRET_KEY" ]]; then
    jq -n \
       --arg path "$DATASET_PATH" \
       --arg region "$S3_REGION_FOR_BOTO" \
       --arg akid "$S3_ACCESS_KEY" \
       --arg ak "$S3_SECRET_KEY" \
       '{
         dataset_path: $path,
         region: $region,
         description: "Nebius Object Storage bucket",
         mode: "read-write",
         default_credential: {
           access_key_id: $akid,
           access_key: $ak
         }
       }' > "${BUCKET_JSON}"
else
    jq -n \
       --arg path "$DATASET_PATH" \
       --arg region "$S3_REGION_FOR_BOTO" \
       '{
         dataset_path: $path,
         region: $region,
         description: "Nebius Object Storage bucket",
         mode: "read-write"
       }' > "${BUCKET_JSON}"
fi

# Fetch current dataset config so we can merge (preserve other buckets if any)
CURRENT_DATASET="/tmp/osmo_dataset_current.json"
if osmo_curl GET "http://localhost:8080/api/configs/dataset" 2>/dev/null | jq -r '.configs_dict // . | if type == "object" then . else empty end' > "${CURRENT_DATASET}" 2>/dev/null && [[ -s "${CURRENT_DATASET}" ]]; then
    # Merge: add/overwrite our bucket and set default_bucket (users can omit bucket prefix)
    UPDATED_DATASET="/tmp/osmo_dataset_updated.json"
    jq --arg name "$DATASET_BUCKET_NAME" \
       --slurpfile bucket "${BUCKET_JSON}" \
       '.buckets[$name] = $bucket[0] | .default_bucket = $name' \
       "${CURRENT_DATASET}" > "${UPDATED_DATASET}"
else
    # No existing config: create new with single bucket and set as default_bucket
    UPDATED_DATASET="/tmp/osmo_dataset_updated.json"
    jq -n --arg name "$DATASET_BUCKET_NAME" \
       --slurpfile bucket "${BUCKET_JSON}" \
       '{ buckets: { ($name): $bucket[0] }, default_bucket: $name }' \
       > "${UPDATED_DATASET}"
fi

if osmo_config_update DATASET "${UPDATED_DATASET}" "Register Nebius bucket and set as default dataset bucket"; then
    log_success "Dataset bucket configured and set as default"
else
    log_error "Failed to configure dataset bucket"
    rm -f "${BUCKET_JSON}" "${CURRENT_DATASET}" "${UPDATED_DATASET}"
    exit 1
fi

rm -f "${BUCKET_JSON}" "${CURRENT_DATASET}" "${UPDATED_DATASET}"

# -----------------------------------------------------------------------------
# Verify
# -----------------------------------------------------------------------------
log_info "Verifying..."
echo ""
osmo_curl GET "http://localhost:8080/api/configs/dataset" 2>/dev/null | jq '.configs_dict // .' || true

cleanup_port_forward
trap - EXIT

echo ""
echo "========================================"
log_success "OSMO dataset bucket configuration complete!"
echo "========================================"
echo ""
echo "Bucket '${DATASET_BUCKET_NAME}' is registered and set as the default bucket."
echo "  dataset_path: ${DATASET_PATH}"
echo "  default_bucket: ${DATASET_BUCKET_NAME}"
echo ""
echo "With default_bucket set, you can reference datasets without the bucket prefix:"
echo "  my-dataset:latest   (instead of ${DATASET_BUCKET_NAME}/my-dataset:latest)"
echo ""
echo "Usage:"
echo "  osmo profile set bucket ${DATASET_BUCKET_NAME}"
echo "  osmo bucket list"
echo "  osmo dataset upload my-dataset:latest ./data"
echo ""
