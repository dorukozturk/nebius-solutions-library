#!/bin/bash
#
# Enable TLS/HTTPS for OSMO using cert-manager + Let's Encrypt
#
# Prerequisites:
#   1. OSMO is deployed and accessible over HTTP (scripts 01-05)
#   2. A DNS record points your domain to the LoadBalancer IP
#      (check with: kubectl get svc -n ingress-nginx ingress-nginx-controller)
#
# Usage:
#   ./09-enable-tls.sh <hostname>
#
# Example:
#   ./09-enable-tls.sh vl51.eu-north1.osmo.nebius.cloud
#
# Optional environment variables:
#   OSMO_TLS_EMAIL        - Email for Let's Encrypt expiry notices (default: noreply@<domain>)
#   OSMO_TLS_SECRET_NAME  - K8s Secret name for certificate (default: osmo-tls)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/defaults.sh"

HOSTNAME="${1:-${OSMO_INGRESS_HOSTNAME:-}}"
TLS_SECRET="${OSMO_TLS_SECRET_NAME:-osmo-tls}"
OSMO_NS="${OSMO_NAMESPACE:-osmo}"
INGRESS_NS="${INGRESS_NAMESPACE:-ingress-nginx}"

echo ""
echo "========================================"
echo "  Enable TLS/HTTPS for OSMO"
echo "========================================"
echo ""

# -----------------------------------------------------------------------------
# Validate inputs
# -----------------------------------------------------------------------------
if [[ -z "$HOSTNAME" ]]; then
    log_error "Usage: $0 <hostname>"
    echo ""
    echo "Example: $0 vl51.eu-north1.osmo.nebius.cloud"
    echo ""
    LB_IP=$(kubectl get svc -n "${INGRESS_NS}" ingress-nginx-controller \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    if [[ -n "$LB_IP" ]]; then
        echo "Your LoadBalancer IP is: ${LB_IP}"
        echo "Create a DNS A record pointing your domain to this IP, then re-run this script."
    fi
    exit 1
fi

check_kubectl || exit 1
check_helm || exit 1

log_info "Hostname: ${HOSTNAME}"
log_info "TLS secret: ${TLS_SECRET}"

# Verify DNS resolves to the LoadBalancer IP
LB_IP=$(kubectl get svc -n "${INGRESS_NS}" ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
DNS_IP=$(dig +short "$HOSTNAME" 2>/dev/null | tail -1 || true)

if [[ -n "$LB_IP" && -n "$DNS_IP" ]]; then
    if [[ "$DNS_IP" == "$LB_IP" ]]; then
        log_success "DNS check: ${HOSTNAME} -> ${DNS_IP} (matches LoadBalancer)"
    else
        log_warning "DNS mismatch: ${HOSTNAME} -> ${DNS_IP}, but LoadBalancer IP is ${LB_IP}"
        log_warning "Let's Encrypt HTTP-01 challenge may fail if DNS doesn't point to the LoadBalancer."
    fi
elif [[ -z "$DNS_IP" ]]; then
    log_warning "Could not resolve ${HOSTNAME}. Make sure the DNS record exists."
fi

# Verify Ingress resources exist
INGRESS_COUNT=$(kubectl get ingress -n "${OSMO_NS}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$INGRESS_COUNT" -eq 0 ]]; then
    log_error "No Ingress resources found in namespace ${OSMO_NS}."
    log_error "Run 04-deploy-osmo-control-plane.sh first."
    exit 1
fi
log_info "Found ${INGRESS_COUNT} Ingress resource(s) in ${OSMO_NS}"

# -----------------------------------------------------------------------------
# Step 1: Install cert-manager
# -----------------------------------------------------------------------------
log_info "Installing cert-manager..."
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo update jetstack

if helm status cert-manager -n cert-manager &>/dev/null; then
    log_info "cert-manager already installed"
else
    helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager --create-namespace \
        --set crds.enabled=true \
        --wait --timeout 5m
fi
log_success "cert-manager ready"

# -----------------------------------------------------------------------------
# Step 2: Create Let's Encrypt ClusterIssuer
# -----------------------------------------------------------------------------
TLS_EMAIL="${OSMO_TLS_EMAIL:-noreply@${HOSTNAME#*.}}"
log_info "Creating Let's Encrypt ClusterIssuer (email: ${TLS_EMAIL})..."

kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${TLS_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-account-key
    solvers:
      - http01:
          ingress:
            class: nginx
EOF
log_success "ClusterIssuer created"

# -----------------------------------------------------------------------------
# Step 3: Patch all Ingress resources with TLS
# -----------------------------------------------------------------------------
log_info "Patching Ingress resources for TLS..."

for ing in $(kubectl get ingress -n "${OSMO_NS}" -o name 2>/dev/null); do
    ing_name="${ing#*/}"
    # Get current HTTP paths from this ingress
    CURRENT_HTTP=$(kubectl get "$ing" -n "${OSMO_NS}" -o jsonpath='{.spec.rules[0].http}')

    kubectl patch "$ing" -n "${OSMO_NS}" --type=merge -p "$(cat <<PATCH
{
  "metadata": {
    "annotations": {
      "cert-manager.io/cluster-issuer": "letsencrypt"
    }
  },
  "spec": {
    "tls": [{
      "hosts": ["${HOSTNAME}"],
      "secretName": "${TLS_SECRET}"
    }],
    "rules": [{
      "host": "${HOSTNAME}",
      "http": ${CURRENT_HTTP}
    }]
  }
}
PATCH
)" && log_success "  ${ing_name} patched" || log_warning "  Failed to patch ${ing_name}"
done

# -----------------------------------------------------------------------------
# Step 4: Wait for certificate
# -----------------------------------------------------------------------------
log_info "Waiting for TLS certificate to be issued (up to 120s)..."

CERT_READY=""
for i in $(seq 1 24); do
    CERT_READY=$(kubectl get certificate "${TLS_SECRET}" -n "${OSMO_NS}" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    if [[ "$CERT_READY" == "True" ]]; then
        log_success "TLS certificate issued and ready"
        break
    fi
    sleep 5
done

if [[ "$CERT_READY" != "True" ]]; then
    log_warning "Certificate not ready yet. Checking status..."
    kubectl describe certificate "${TLS_SECRET}" -n "${OSMO_NS}" 2>/dev/null | tail -10
    echo ""
    log_info "It may take a few more minutes. Check with:"
    echo "  kubectl get certificate -n ${OSMO_NS}"
    echo "  kubectl describe challenge -n ${OSMO_NS}"
fi

# -----------------------------------------------------------------------------
# Step 5: Update OSMO service_base_url to HTTPS
# -----------------------------------------------------------------------------
log_info "Updating OSMO service_base_url to https://${HOSTNAME}..."

kubectl port-forward -n "${OSMO_NS}" svc/osmo-service 8080:80 &>/dev/null &
_PF_PID=$!
trap 'kill $_PF_PID 2>/dev/null; wait $_PF_PID 2>/dev/null' EXIT

# Wait for port-forward
_pf_ready=false
for i in $(seq 1 15); do
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/version" 2>/dev/null | grep -q "200\|401\|403"; then
        _pf_ready=true
        break
    fi
    sleep 1
done

if [[ "$_pf_ready" == "true" ]]; then
    # Login
    if osmo login http://localhost:8080 --method dev --username admin 2>/dev/null; then
        cat > /tmp/service_url_tls.json <<SVCEOF
{
  "service_base_url": "https://${HOSTNAME}"
}
SVCEOF
        if osmo config update SERVICE --file /tmp/service_url_tls.json --description "Enable HTTPS" 2>/dev/null; then
            NEW_URL=$(curl -s "http://localhost:8080/api/configs/service" 2>/dev/null | jq -r '.service_base_url // ""')
            log_success "service_base_url updated to: ${NEW_URL}"
        else
            log_warning "Could not update service_base_url automatically."
            log_info "Run: ./07-configure-service-url.sh https://${HOSTNAME}"
        fi
        rm -f /tmp/service_url_tls.json
    else
        log_warning "Could not login to OSMO API. Update service_base_url manually:"
        log_info "  ./07-configure-service-url.sh https://${HOSTNAME}"
    fi
else
    log_warning "Could not connect to OSMO API. Update service_base_url manually:"
    log_info "  ./07-configure-service-url.sh https://${HOSTNAME}"
fi

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
echo ""
echo "========================================"
log_success "TLS enabled for OSMO"
echo "========================================"
echo ""
echo "OSMO is now accessible at:"
echo "  https://${HOSTNAME}"
echo "  https://${HOSTNAME}/api/version"
echo ""
echo "CLI login:"
echo "  osmo login https://${HOSTNAME} --method dev --username admin"
echo ""
