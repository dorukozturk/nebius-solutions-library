# =============================================================================
# Default Configuration for Setup Scripts
# =============================================================================

# Namespaces
export GPU_OPERATOR_NAMESPACE="gpu-operator"
export NETWORK_OPERATOR_NAMESPACE="network-operator"
export KAI_SCHEDULER_NAMESPACE="kai-scheduler"
export MONITORING_NAMESPACE="monitoring"
export OSMO_NAMESPACE="osmo"

# Chart versions (leave empty for latest)
export GPU_OPERATOR_VERSION=""
export NETWORK_OPERATOR_VERSION=""
export KAI_SCHEDULER_VERSION="v0.12.4"  # Check https://github.com/NVIDIA/KAI-Scheduler/releases
export PROMETHEUS_VERSION=""
export GRAFANA_VERSION=""
export LOKI_VERSION=""

# GPU Operator settings
export GPU_DRIVER_ENABLED="false"  # Use Nebius driver-full images
export TOOLKIT_ENABLED="true"
export DEVICE_PLUGIN_ENABLED="true"
export MIG_MANAGER_ENABLED="false"

# Driverfull images (Nebius pre-installed NVIDIA drivers, skips GPU Operator driver)
# Recommended for B200/B300 GPUs where the GPU Operator's bundled driver may not support NVSwitch.
export USE_DRIVERFULL_IMAGES="${USE_DRIVERFULL_IMAGES:-}"  # Auto-detected from Terraform; set "true"/"false" to override

# Network Operator (only needed for InfiniBand/GPU clusters without driverfull images)
export ENABLE_NETWORK_OPERATOR="false"  # Set to "true" if using InfiniBand

# Observability settings
export PROMETHEUS_RETENTION_DAYS="15"
export LOKI_RETENTION_DAYS="7"
export GRAFANA_ADMIN_PASSWORD=""  # Auto-generated if empty

# NGINX Ingress Controller (deployed by 03-deploy-nginx-ingress.sh)
# Namespace where the NGINX Ingress Controller is deployed.
export INGRESS_NAMESPACE="${INGRESS_NAMESPACE:-ingress-nginx}"
# Hostname for Ingress rules (e.g. osmo.example.com). Leave empty to use the LoadBalancer IP directly.
export OSMO_INGRESS_HOSTNAME="${OSMO_INGRESS_HOSTNAME:-}"
# Override for the service_base_url used by osmo-ctrl. Auto-detected from the ingress LoadBalancer if empty.
export OSMO_INGRESS_BASE_URL="${OSMO_INGRESS_BASE_URL:-}"

# Keycloak / Authentication
# Set DEPLOY_KEYCLOAK=true to deploy Keycloak and enable OSMO auth with Envoy sidecars.
export DEPLOY_KEYCLOAK="${DEPLOY_KEYCLOAK:-false}"
# Keycloak hostname (e.g. auth.osmo.example.com).
# Auto-derived from OSMO_INGRESS_HOSTNAME if empty: auth.<OSMO_INGRESS_HOSTNAME>.
export KEYCLOAK_HOSTNAME="${KEYCLOAK_HOSTNAME:-}"
# TLS secret name for the Keycloak ingress (separate from the main osmo-tls).
export KEYCLOAK_TLS_SECRET_NAME="${KEYCLOAK_TLS_SECRET_NAME:-osmo-tls-auth}"

# Paths
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export VALUES_DIR="${SCRIPT_DIR}/values"
export LIB_DIR="${SCRIPT_DIR}/lib"
