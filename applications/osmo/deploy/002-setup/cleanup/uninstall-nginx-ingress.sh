#!/bin/bash
# Uninstall NGINX Ingress Controller (deployed by 03-deploy-nginx-ingress.sh)
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
INGRESS_NAMESPACE="${INGRESS_NAMESPACE:-ingress-nginx}"
INGRESS_RELEASE_NAME="${INGRESS_RELEASE_NAME:-ingress-nginx}"
log_info "Uninstalling NGINX Ingress Controller..."
helm uninstall "${INGRESS_RELEASE_NAME}" -n "${INGRESS_NAMESPACE}" 2>/dev/null || true
kubectl delete namespace "${INGRESS_NAMESPACE}" --ignore-not-found --timeout=60s 2>/dev/null || true
log_success "NGINX Ingress Controller uninstalled"
