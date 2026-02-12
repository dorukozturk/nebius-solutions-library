#!/bin/bash
#
# Enable TLS/HTTPS using cert-manager + Let's Encrypt
#
# Can be run at two points in the deployment flow:
#
#   A) Right after 03-deploy-nginx-ingress.sh (RECOMMENDED):
#      Installs cert-manager, issues the TLS certificate early.
#      When 05-deploy-osmo-control-plane.sh runs later, it auto-detects the
#      certificate and creates TLS-enabled Ingress resources from the start.
#
#   B) After 05-deploy-osmo-control-plane.sh (retrofit existing deployment):
#      Does everything in (A) plus patches existing OSMO Ingress resources
#      and updates service_base_url to HTTPS.
#
# Prerequisites:
#   1. NGINX Ingress Controller deployed (03-deploy-nginx-ingress.sh)
#   2. A DNS A record pointing your domain to the LoadBalancer IP
#
# Usage:
#   ./04-enable-tls.sh <hostname>
#
# Example:
#   ./04-enable-tls.sh vl51.eu-north1.osmo.nebius.cloud
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
HOSTNAME="${HOSTNAME%.}"  # Strip trailing dot (FQDN notation)
TLS_SECRET="${OSMO_TLS_SECRET_NAME:-osmo-tls}"
OSMO_NS="${OSMO_NAMESPACE:-osmo}"
INGRESS_NS="${INGRESS_NAMESPACE:-ingress-nginx}"

echo ""
echo "========================================"
echo "  Enable TLS/HTTPS"
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

# Keycloak auth subdomain support
DEPLOY_KEYCLOAK="${DEPLOY_KEYCLOAK:-false}"
KC_TLS_SECRET="${KEYCLOAK_TLS_SECRET_NAME:-osmo-tls-auth}"
AUTH_HOSTNAME=""
if [[ "$DEPLOY_KEYCLOAK" == "true" ]]; then
    if [[ -n "${KEYCLOAK_HOSTNAME:-}" ]]; then
        AUTH_HOSTNAME="${KEYCLOAK_HOSTNAME}"
    else
        AUTH_HOSTNAME="auth.${HOSTNAME}"
    fi
    log_info "Keycloak auth hostname: ${AUTH_HOSTNAME}"
    log_info "Keycloak TLS secret: ${KC_TLS_SECRET}"
fi

# Get LoadBalancer IP
LB_IP=$(kubectl get svc -n "${INGRESS_NS}" ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)

# Prompt user to set up DNS records before proceeding
echo ""
echo "========================================"
echo "  DNS Record Setup Required"
echo "========================================"
echo ""
if [[ -n "$LB_IP" ]]; then
    echo "Create the following DNS A record(s) pointing to your LoadBalancer IP:"
    echo ""
    echo "  ${HOSTNAME}  ->  ${LB_IP}"
    if [[ -n "$AUTH_HOSTNAME" ]]; then
        echo "  ${AUTH_HOSTNAME}  ->  ${LB_IP}"
    fi
else
    echo "LoadBalancer IP not yet assigned. Check with:"
    echo "  kubectl get svc -n ${INGRESS_NS} ingress-nginx-controller"
    echo ""
    echo "Once the IP is available, create DNS A record(s) for:"
    echo "  ${HOSTNAME}"
    if [[ -n "$AUTH_HOSTNAME" ]]; then
        echo "  ${AUTH_HOSTNAME}"
    fi
fi
echo ""
echo "Let's Encrypt HTTP-01 challenges require DNS to resolve to the LoadBalancer."
echo ""
read_prompt_var "Press Enter once DNS records are configured (or type 'skip' to skip DNS check)" DNS_CONFIRM ""

# Verify DNS resolves to the LoadBalancer IP
if [[ "$DNS_CONFIRM" != "skip" ]]; then
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

    if [[ -n "$AUTH_HOSTNAME" ]]; then
        AUTH_DNS_IP=$(dig +short "$AUTH_HOSTNAME" 2>/dev/null | tail -1 || true)
        if [[ -n "$LB_IP" && -n "$AUTH_DNS_IP" ]]; then
            if [[ "$AUTH_DNS_IP" == "$LB_IP" ]]; then
                log_success "DNS check: ${AUTH_HOSTNAME} -> ${AUTH_DNS_IP} (matches LoadBalancer)"
            else
                log_warning "DNS mismatch: ${AUTH_HOSTNAME} -> ${AUTH_DNS_IP}, but LoadBalancer IP is ${LB_IP}"
            fi
        elif [[ -z "$AUTH_DNS_IP" ]]; then
            log_warning "Could not resolve ${AUTH_HOSTNAME}. Keycloak TLS cert may fail."
        fi
    fi
fi

# Check if OSMO is already deployed (determines whether to patch Ingress / update config)
INGRESS_COUNT=$(kubectl get ingress -n "${OSMO_NS}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$INGRESS_COUNT" -gt 0 ]]; then
    log_info "Found ${INGRESS_COUNT} Ingress resource(s) in ${OSMO_NS} (will patch with TLS)"
    OSMO_DEPLOYED="true"
else
    log_info "No OSMO Ingress resources yet — preparing cert-manager and certificate"
    log_info "Step 05 will auto-detect the TLS cert and create HTTPS Ingress"
    OSMO_DEPLOYED="false"
fi

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
# Step 3: Issue TLS certificate
# -----------------------------------------------------------------------------

# Ensure the OSMO namespace exists (needed for Certificate resource)
kubectl create namespace "${OSMO_NS}" --dry-run=client -o yaml | kubectl apply -f -

if [[ "$OSMO_DEPLOYED" == "true" ]]; then
    # Mode B: Patch existing Ingress resources with TLS
    log_info "Patching Ingress resources for TLS..."

    for ing in $(kubectl get ingress -n "${OSMO_NS}" -o name 2>/dev/null); do
        ing_name="${ing#*/}"
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
else
    # Mode A: Create a temporary Ingress to trigger HTTP-01 challenge
    # cert-manager needs an Ingress with the annotation to issue the cert
    log_info "Creating temporary Ingress for certificate issuance..."
    kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: osmo-tls-bootstrap
  namespace: ${OSMO_NS}
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - ${HOSTNAME}
      secretName: ${TLS_SECRET}
  rules:
    - host: ${HOSTNAME}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: osmo-tls-placeholder
                port:
                  number: 80
EOF
    log_success "Bootstrap Ingress created"
fi

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
# Step 4b: Issue TLS certificate for Keycloak auth subdomain (if DEPLOY_KEYCLOAK=true)
# -----------------------------------------------------------------------------
if [[ -n "$AUTH_HOSTNAME" ]]; then
    log_info "Issuing TLS certificate for Keycloak auth subdomain: ${AUTH_HOSTNAME}..."

    # Create bootstrap Ingress for auth subdomain (to trigger HTTP-01 challenge)
    kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: osmo-tls-auth-bootstrap
  namespace: ${OSMO_NS}
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - ${AUTH_HOSTNAME}
      secretName: ${KC_TLS_SECRET}
  rules:
    - host: ${AUTH_HOSTNAME}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: osmo-tls-placeholder
                port:
                  number: 80
EOF
    log_success "Auth subdomain bootstrap Ingress created"

    # Wait for auth certificate
    log_info "Waiting for auth TLS certificate to be issued (up to 120s)..."
    AUTH_CERT_READY=""
    for i in $(seq 1 24); do
        AUTH_CERT_READY=$(kubectl get certificate "${KC_TLS_SECRET}" -n "${OSMO_NS}" \
            -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
        if [[ "$AUTH_CERT_READY" == "True" ]]; then
            log_success "Auth TLS certificate issued and ready"
            break
        fi
        sleep 5
    done

    if [[ "$AUTH_CERT_READY" != "True" ]]; then
        log_warning "Auth certificate not ready yet. It may take a few more minutes."
        log_info "Check with: kubectl get certificate ${KC_TLS_SECRET} -n ${OSMO_NS}"
    fi

    # Clean up the bootstrap Ingress if Keycloak will create its own
    if [[ "$OSMO_DEPLOYED" == "true" ]]; then
        kubectl delete ingress osmo-tls-auth-bootstrap -n "${OSMO_NS}" --ignore-not-found 2>/dev/null
    fi
fi

# -----------------------------------------------------------------------------
# Step 5: Update OSMO service_base_url to HTTPS (only if OSMO is deployed)
# -----------------------------------------------------------------------------
if [[ "$OSMO_DEPLOYED" == "true" ]]; then
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
                log_info "Run: ./08-configure-service-url.sh https://${HOSTNAME}"
            fi
            rm -f /tmp/service_url_tls.json
        else
            log_warning "Could not login to OSMO API. Update service_base_url manually:"
            log_info "  ./08-configure-service-url.sh https://${HOSTNAME}"
        fi
    else
        log_warning "Could not connect to OSMO API. Update service_base_url manually:"
        log_info "  ./08-configure-service-url.sh https://${HOSTNAME}"
    fi
else
    log_info "Skipping service_base_url update (OSMO not deployed yet)"
    log_info "Step 05 will auto-detect TLS and use https:// for service_base_url"
fi

# -----------------------------------------------------------------------------
# Step 6: Clean up bootstrap Ingress (if OSMO was deployed after cert issued)
# -----------------------------------------------------------------------------
if [[ "$OSMO_DEPLOYED" == "true" ]]; then
    # Remove the bootstrap ingress if it exists (from a previous Mode A run)
    kubectl delete ingress osmo-tls-bootstrap -n "${OSMO_NS}" --ignore-not-found 2>/dev/null
fi

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
echo ""
echo "========================================"
log_success "TLS setup complete"
echo "========================================"
echo ""

if [[ "$OSMO_DEPLOYED" == "true" ]]; then
    echo "OSMO is now accessible at:"
    echo "  https://${HOSTNAME}"
    echo "  https://${HOSTNAME}/api/version"
    echo ""
    echo "CLI login:"
    echo "  osmo login https://${HOSTNAME} --method dev --username admin"
else
    echo "TLS certificate prepared for: ${HOSTNAME}"
    if [[ -n "$AUTH_HOSTNAME" ]]; then
        echo "Auth TLS certificate prepared for: ${AUTH_HOSTNAME}"
    fi
    echo ""
    echo "Next steps:"
    echo "  1. Wait for certificate(s) to be ready: kubectl get certificate -n ${OSMO_NS}"
    echo "  2. Deploy OSMO: ./05-deploy-osmo-control-plane.sh"
    echo "     (It will auto-detect the TLS cert and create HTTPS Ingress)"
    if [[ -n "$AUTH_HOSTNAME" ]]; then
        echo "  3. Deploy with Keycloak: DEPLOY_KEYCLOAK=true ./05-deploy-osmo-control-plane.sh"
        echo "     (Keycloak will be exposed at https://${AUTH_HOSTNAME})"
    fi
fi
echo ""
