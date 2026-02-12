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

# Network Operator (only needed for InfiniBand/GPU clusters)
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

# TLS / SSL Configuration
# Set OSMO_TLS_ENABLED=true after running 03a (certbot) or 03c (cert-manager).
export OSMO_TLS_ENABLED="${OSMO_TLS_ENABLED:-false}"
# Name of the Kubernetes TLS secret used by Ingress (both paths produce this secret).
# NOTE: The OSMO Helm chart generates ingress TLS with secretName "osmo-tls".
export OSMO_TLS_SECRET_NAME="${OSMO_TLS_SECRET_NAME:-osmo-tls}"
# Local directory where certbot stores certificate files (Path A only).
export OSMO_TLS_CERT_DIR="${OSMO_TLS_CERT_DIR:-$HOME/.osmo-certs}"
# Email for Let's Encrypt registration (required for 03a and 03c).
export LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-}"
# cert-manager namespace (Path B / 03c only).
export CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
# Name of the ClusterIssuer created by 03c (Path B only).
export CLUSTER_ISSUER_NAME="${CLUSTER_ISSUER_NAME:-letsencrypt-prod}"
# TLS mode: "certbot" or "cert-manager". Set automatically by 03a/03c.
export OSMO_TLS_MODE="${OSMO_TLS_MODE:-}"

# Keycloak / Authentication
# Set DEPLOY_KEYCLOAK=true to deploy Keycloak and enable OSMO auth with Envoy sidecars.
export DEPLOY_KEYCLOAK="${DEPLOY_KEYCLOAK:-false}"
# Keycloak hostname (e.g. auth-osmo-nebius.csptst.nvidia.com).
# Auto-derived from OSMO_INGRESS_HOSTNAME if empty: auth-<OSMO_INGRESS_HOSTNAME>.
export KEYCLOAK_HOSTNAME="${KEYCLOAK_HOSTNAME:-}"
# TLS secret name for the Keycloak ingress (separate from the main osmo-tls).
# Run 03a with OSMO_TLS_SECRET_NAME=osmo-tls-auth for the auth subdomain.
export KEYCLOAK_TLS_SECRET_NAME="${KEYCLOAK_TLS_SECRET_NAME:-osmo-tls-auth}"

# Paths
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export VALUES_DIR="${SCRIPT_DIR}/values"
export LIB_DIR="${SCRIPT_DIR}/lib"
