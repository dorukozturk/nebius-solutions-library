#!/bin/bash
#
# Deploy OSMO Service (Control Plane)
# https://nvidia.github.io/OSMO/main/deployment_guide/getting_started/deploy_service.html
#
# Components: API Service, Router, Web UI, Worker, Logger, Agent, Keycloak
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/defaults.sh"

echo ""
echo "========================================"
echo "  OSMO Service Deployment"
echo "========================================"
echo ""

# Check prerequisites
check_kubectl || exit 1
check_helm || exit 1

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
OSMO_NAMESPACE="${OSMO_NAMESPACE:-osmo}"
# Deploy Keycloak in same namespace as PostgreSQL to simplify DNS resolution
KEYCLOAK_NAMESPACE="${OSMO_NAMESPACE}"
OSMO_DOMAIN="${OSMO_DOMAIN:-osmo.local}"

# Keycloak admin password - check for existing secret first to maintain consistency
if [[ -z "${KEYCLOAK_ADMIN_PASSWORD:-}" ]]; then
    # Try to get existing password from secret
    EXISTING_KC_PASS=$(kubectl get secret keycloak-admin-secret -n "${OSMO_NAMESPACE}" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)
    if [[ -n "${EXISTING_KC_PASS}" ]]; then
        KEYCLOAK_ADMIN_PASSWORD="${EXISTING_KC_PASS}"
        log_info "Using existing Keycloak admin password from secret"
    else
        KEYCLOAK_ADMIN_PASSWORD="$(openssl rand -base64 12)"
        log_info "Generated new Keycloak admin password"
    fi
fi

# -----------------------------------------------------------------------------
# Get Database Configuration from Terraform (Nebius Managed PostgreSQL)
# -----------------------------------------------------------------------------
log_info "Using Nebius Managed PostgreSQL..."
    log_info "Retrieving database configuration..."

    # Get connection details from Terraform outputs
    POSTGRES_HOST=$(get_tf_output "postgresql.host" "../001-iac" || echo "")
    POSTGRES_PORT=$(get_tf_output "postgresql.port" "../001-iac" || echo "5432")
    POSTGRES_DB=$(get_tf_output "postgresql.database" "../001-iac" || echo "osmo")
    POSTGRES_USER=$(get_tf_output "postgresql.username" "../001-iac" || echo "osmo_admin")
    
    # Get password - try MysteryBox first, then Terraform output, then env vars
    # MysteryBox secret ID is set by secrets-init.sh as TF_VAR_postgresql_mysterybox_secret_id
    POSTGRES_SECRET_ID="${TF_VAR_postgresql_mysterybox_secret_id:-${OSMO_POSTGRESQL_SECRET_ID:-}}"
    
    if [[ -n "$POSTGRES_SECRET_ID" ]]; then
        log_info "Reading PostgreSQL password from MysteryBox (secret: $POSTGRES_SECRET_ID)..."
        POSTGRES_PASSWORD=$(get_mysterybox_secret "$POSTGRES_SECRET_ID" "password" || echo "")
        if [[ -n "$POSTGRES_PASSWORD" ]]; then
            log_success "PostgreSQL password retrieved from MysteryBox"
        else
            log_warning "Failed to read password from MysteryBox"
        fi
    fi
    
    # Fall back to Terraform output (only works if not using MysteryBox)
    if [[ -z "$POSTGRES_PASSWORD" ]]; then
        POSTGRES_PASSWORD=$(get_tf_output "postgresql_password" "../001-iac" || echo "")
    fi
    
    # Fall back to environment variables or prompt
    if [[ -z "$POSTGRES_HOST" || -z "$POSTGRES_PASSWORD" ]]; then
        log_warning "Could not retrieve PostgreSQL configuration automatically"
        log_info "Checking environment variables..."
        
        POSTGRES_HOST=${POSTGRES_HOST:-${OSMO_POSTGRES_HOST:-""}}
        POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-${OSMO_POSTGRES_PASSWORD:-""}}
        
        if [[ -z "$POSTGRES_HOST" ]]; then
            read_prompt_var "PostgreSQL Host" POSTGRES_HOST ""
        fi
        if [[ -z "$POSTGRES_PASSWORD" ]]; then
            read_secret_var "PostgreSQL Password" POSTGRES_PASSWORD
        fi
    fi

log_success "Database: ${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"

# -----------------------------------------------------------------------------
# Get Storage Configuration
# -----------------------------------------------------------------------------
log_info "Retrieving storage configuration..."

S3_BUCKET=$(get_tf_output "storage_bucket.name" "../001-iac" || echo "")
S3_ENDPOINT=$(get_tf_output "storage_bucket.endpoint" "../001-iac" || echo "https://storage.eu-north1.nebius.cloud")
S3_ACCESS_KEY=$(get_tf_output "storage_credentials.access_key_id" "../001-iac" || echo "")

# Secret access key is stored in MysteryBox (ephemeral, not in Terraform state)
S3_SECRET_REF_ID=$(get_tf_output "storage_secret_reference_id" "../001-iac" || echo "")
S3_SECRET_KEY=""

if [[ -n "$S3_SECRET_REF_ID" ]]; then
    log_info "Retrieving storage secret from MysteryBox..."
    # IAM access key secrets are stored with key "secret" in MysteryBox
    S3_SECRET_KEY=$(get_mysterybox_secret "$S3_SECRET_REF_ID" "secret" || echo "")
    if [[ -n "$S3_SECRET_KEY" ]]; then
        log_success "Storage secret retrieved from MysteryBox"
    else
        log_warning "Could not retrieve storage secret from MysteryBox"
    fi
fi

if [[ -n "$S3_BUCKET" ]]; then
    log_success "Storage: ${S3_BUCKET} @ ${S3_ENDPOINT}"
fi

# -----------------------------------------------------------------------------
# Add Helm Repositories
# -----------------------------------------------------------------------------
log_info "Adding Helm repositories..."
helm repo add osmo https://helm.ngc.nvidia.com/nvidia/osmo --force-update
helm repo add bitnami https://charts.bitnami.com/bitnami --force-update
helm repo update

# -----------------------------------------------------------------------------
# Step 1: Create Namespaces
# -----------------------------------------------------------------------------
log_info "Creating namespace..."
kubectl create namespace "${OSMO_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
# Note: Keycloak is deployed in the same namespace as OSMO (no separate namespace needed)

# -----------------------------------------------------------------------------
# Step 2: Configure PostgreSQL - Verify Connection and Create Databases
# -----------------------------------------------------------------------------
log_info "Verifying PostgreSQL connection..."

    # Delete any existing test/init pods
    kubectl delete pod osmo-db-test -n "${OSMO_NAMESPACE}" --ignore-not-found 2>/dev/null
    kubectl delete pod osmo-db-init -n "${OSMO_NAMESPACE}" --ignore-not-found 2>/dev/null

    # Create a temporary secret with DB credentials
    # NOTE: PGDATABASE must be the bootstrap database ('osmo') for Nebius MSP PostgreSQL
    kubectl create secret generic osmo-db-init-creds \
        --namespace "${OSMO_NAMESPACE}" \
        --from-literal=PGPASSWORD="${POSTGRES_PASSWORD}" \
        --from-literal=PGHOST="${POSTGRES_HOST}" \
        --from-literal=PGPORT="${POSTGRES_PORT}" \
        --from-literal=PGUSER="${POSTGRES_USER}" \
        --from-literal=PGDATABASE="${POSTGRES_DB}" \
        --dry-run=client -o yaml | kubectl apply -f -

    # -----------------------------------------------------------------------------
    # Connection Test - Verify credentials before proceeding
    # -----------------------------------------------------------------------------
    log_info "Testing PostgreSQL connection (this may take a moment)..."
    
    kubectl run osmo-db-test \
        --namespace "${OSMO_NAMESPACE}" \
        --image=postgres:16-alpine \
        --restart=Never \
        --env="PGPASSWORD=${POSTGRES_PASSWORD}" \
        --env="PGHOST=${POSTGRES_HOST}" \
        --env="PGPORT=${POSTGRES_PORT}" \
        --env="PGUSER=${POSTGRES_USER}" \
        --env="PGDATABASE=${POSTGRES_DB}" \
        --command -- sh -c 'psql -c "SELECT 1" >/dev/null 2>&1 && echo "CONNECTION_OK" || echo "CONNECTION_FAILED"' \
        >/dev/null 2>&1
    
    # Wait for test pod to complete
    test_elapsed=0
    test_status=""
    while [[ $test_elapsed -lt 60 ]]; do
        test_status=$(kubectl get pod osmo-db-test -n "${OSMO_NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
        if [[ "$test_status" == "Succeeded" || "$test_status" == "Failed" ]]; then
            break
        fi
        sleep 2
        ((test_elapsed += 2))
    done
    
    # Check test result
    test_result=$(kubectl logs osmo-db-test -n "${OSMO_NAMESPACE}" 2>/dev/null || echo "")
    kubectl delete pod osmo-db-test -n "${OSMO_NAMESPACE}" --ignore-not-found >/dev/null 2>&1
    
    if [[ "$test_result" != *"CONNECTION_OK"* ]]; then
        log_error "PostgreSQL connection test failed!"
        echo ""
        echo "Connection details:"
        echo "  Host:     ${POSTGRES_HOST}"
        echo "  Port:     ${POSTGRES_PORT}"
        echo "  Database: ${POSTGRES_DB}"
        echo "  User:     ${POSTGRES_USER}"
        echo "  Password: (from MysteryBox secret ${TF_VAR_postgresql_mysterybox_secret_id:-'not set'})"
        echo ""
        echo "Possible causes:"
        echo "  1. Password mismatch - MysteryBox password doesn't match PostgreSQL"
        echo "     Fix: Update MysteryBox or recreate PostgreSQL cluster"
        echo "  2. Network issue - Cluster cannot reach PostgreSQL"
        echo "  3. PostgreSQL not ready - Wait and retry"
        echo ""
        echo "To debug manually:"
        echo "  kubectl run psql-debug --rm -it --image=postgres:16-alpine -n osmo -- sh"
        echo "  PGPASSWORD='<password>' psql -h ${POSTGRES_HOST} -U ${POSTGRES_USER} -d ${POSTGRES_DB}"
        exit 1
    fi
    
    log_success "PostgreSQL connection verified"

    # -----------------------------------------------------------------------------
    # Database Creation
    # -----------------------------------------------------------------------------
    if [[ "${DEPLOY_KEYCLOAK:-false}" == "true" ]]; then
        log_info "Creating OSMO and Keycloak databases (if not exist)..."
    else
        log_info "Verifying OSMO database..."
    fi

    # NOTE: Nebius MSP PostgreSQL creates the bootstrap database ('osmo') automatically.
    # The bootstrap user can only connect to this database, not 'postgres'.
    # We connect to 'osmo' and create additional databases from there.
    # Pass DEPLOY_KEYCLOAK to the init pod
    kubectl apply -n "${OSMO_NAMESPACE}" -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: osmo-db-init
spec:
  containers:
    - name: db-init
      image: postgres:16-alpine
      envFrom:
        - secretRef:
            name: osmo-db-init-creds
      command: ["/bin/sh", "-c"]
      args:
        - |
          set -e
          echo "Connecting to PostgreSQL at \$PGHOST:\$PGPORT as \$PGUSER..."
          
          # NOTE: Nebius MSP PostgreSQL only allows the bootstrap user to connect
          # to the bootstrap database (osmo), not the 'postgres' database.
          # We connect to 'osmo' and create additional databases from there.
          
          # Test connection to the osmo database (created by Nebius during bootstrap)
          if ! psql -d "\${PGDATABASE:-osmo}" -c "SELECT 1" >/dev/null 2>&1; then
            echo "ERROR: Cannot connect to PostgreSQL"
            echo "Debug: PGHOST=\$PGHOST, PGPORT=\$PGPORT, PGUSER=\$PGUSER, PGDATABASE=\${PGDATABASE:-osmo}"
            # Try with verbose error
            psql -d "\${PGDATABASE:-osmo}" -c "SELECT 1" 2>&1 || true
            exit 1
          fi
          echo "Connection successful to database '\${PGDATABASE:-osmo}'"
          
          # The 'osmo' database already exists (created by Nebius bootstrap)
          echo "Database 'osmo' exists (created by Nebius MSP bootstrap)"
          
          # Create keycloak database only if Keycloak deployment is enabled
          DEPLOY_KEYCLOAK="${DEPLOY_KEYCLOAK:-false}"
          if [ "\$DEPLOY_KEYCLOAK" = "true" ]; then
            # Note: This requires the user to have CREATEDB privilege
            if psql -d "\${PGDATABASE:-osmo}" -tAc "SELECT 1 FROM pg_database WHERE datname='keycloak'" | grep -q 1; then
              echo "Database 'keycloak' already exists"
            else
              echo "Creating database 'keycloak'..."
              psql -d "\${PGDATABASE:-osmo}" -c "CREATE DATABASE keycloak;" || {
                echo "WARNING: Could not create 'keycloak' database."
                echo "The bootstrap user may not have CREATEDB privilege."
                echo "Keycloak will use a schema in the 'osmo' database instead."
              }
            fi
          fi
          
          # Verify databases exist
          echo ""
          echo "Verifying databases..."
          psql -d "\${PGDATABASE:-osmo}" -c "\l" | grep -E "osmo" || true
          
          echo ""
          echo "SUCCESS: Database initialization complete"
  restartPolicy: Never
EOF

    # Wait for pod to complete (init pods may finish before Ready condition is detected)
    log_info "Running database initialization..."
    
    # Poll for completion - init pods go directly to Completed/Succeeded very quickly
    max_wait=120
    elapsed=0
    pod_status=""
    
    while [[ $elapsed -lt $max_wait ]]; do
        pod_status=$(kubectl get pod osmo-db-init -n "${OSMO_NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
        
        if [[ "$pod_status" == "Succeeded" ]]; then
            break
        elif [[ "$pod_status" == "Failed" ]]; then
            log_error "Database initialization failed. Checking logs..."
            kubectl logs osmo-db-init -n "${OSMO_NAMESPACE}"
            kubectl delete pod osmo-db-init -n "${OSMO_NAMESPACE}" --ignore-not-found
            exit 1
        fi
        
        sleep 2
        ((elapsed += 2))
    done
    
    if [[ "$pod_status" != "Succeeded" ]]; then
        log_error "Database initialization timed out (status: $pod_status). Checking logs..."
        kubectl logs osmo-db-init -n "${OSMO_NAMESPACE}" 2>/dev/null || true
        kubectl delete pod osmo-db-init -n "${OSMO_NAMESPACE}" --ignore-not-found
        exit 1
    fi

    # Show logs for verification
    log_info "Database initialization output:"
    kubectl logs osmo-db-init -n "${OSMO_NAMESPACE}"

    # Cleanup
    kubectl delete pod osmo-db-init -n "${OSMO_NAMESPACE}" --ignore-not-found

log_success "Databases verified and ready"

# -----------------------------------------------------------------------------
# Step 3: Create Secrets
# -----------------------------------------------------------------------------
log_info "Creating secrets..."

# Database secret for Keycloak (only if Keycloak is being deployed)
if [[ "${DEPLOY_KEYCLOAK:-false}" == "true" ]]; then
    kubectl create secret generic keycloak-db-secret \
        --namespace "${KEYCLOAK_NAMESPACE}" \
        --from-literal=postgres-password="${POSTGRES_PASSWORD}" \
        --dry-run=client -o yaml | kubectl apply -f -
fi

# Create the postgres-secret that OSMO chart expects
# The chart looks for passwordSecretName: postgres-secret, passwordSecretKey: password
kubectl create secret generic postgres-secret \
    --namespace "${OSMO_NAMESPACE}" \
    --from-literal=password="${POSTGRES_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -

# OIDC secrets (only needed if Keycloak is deployed)
# These are placeholder values that get overwritten with real Keycloak client secrets
if [[ "${DEPLOY_KEYCLOAK:-false}" == "true" ]]; then
    HMAC_SECRET=$(openssl rand -base64 32)
    CLIENT_SECRET=$(openssl rand -base64 32)
    kubectl create secret generic oidc-secrets \
        --namespace "${OSMO_NAMESPACE}" \
        --from-literal=client_secret="${CLIENT_SECRET}" \
        --from-literal=hmac_secret="${HMAC_SECRET}" \
        --dry-run=client -o yaml | kubectl apply -f -
fi

# Storage secret (if available)
if [[ -n "$S3_ACCESS_KEY" && -n "$S3_SECRET_KEY" ]]; then
    kubectl create secret generic osmo-storage \
        --namespace "${OSMO_NAMESPACE}" \
        --from-literal=access-key-id="${S3_ACCESS_KEY}" \
        --from-literal=secret-access-key="${S3_SECRET_KEY}" \
        --dry-run=client -o yaml | kubectl apply -f -
fi

# MEK (Master Encryption Key) Configuration
# OSMO expects MEK in JWK (JSON Web Key) format, base64-encoded
# Reference: https://nvidia.github.io/OSMO/main/deployment_guide/getting_started/deploy_service.html
MEK_ID="${MEK_ID:-key1}"
log_info "Configuring MEK (Master Encryption Key)..."

# Try to read MEK from MysteryBox first (set by secrets-init.sh)
# MysteryBox secret ID is set as TF_VAR_mek_mysterybox_secret_id
MEK_SECRET_ID="${TF_VAR_mek_mysterybox_secret_id:-${OSMO_MEK_SECRET_ID:-}}"
MEK_DATA=""

if [[ -n "$MEK_SECRET_ID" ]]; then
    log_info "Reading MEK from MysteryBox (secret: $MEK_SECRET_ID)..."
    MEK_DATA=$(get_mysterybox_secret "$MEK_SECRET_ID" "mek" || echo "")
    if [[ -n "$MEK_DATA" ]]; then
        log_success "MEK retrieved from MysteryBox"
        # MEK from secrets-init.sh is in format: {"currentMek":"key1","meks":{"key1":"<base64-jwk>"}}
        # Extract the key ID and encoded value
        MEK_ID=$(echo "$MEK_DATA" | jq -r '.currentMek // "key1"' 2>/dev/null || echo "key1")
        MEK_ENCODED=$(echo "$MEK_DATA" | jq -r ".meks.${MEK_ID} // empty" 2>/dev/null || echo "")
        
        if [[ -z "$MEK_ENCODED" ]]; then
            log_warning "Could not parse MEK from MysteryBox, will generate new one"
            MEK_DATA=""
        fi
    else
        log_warning "Failed to read MEK from MysteryBox"
    fi
fi

# Generate new MEK if not retrieved from MysteryBox
if [[ -z "$MEK_DATA" || -z "$MEK_ENCODED" ]]; then
    log_info "Generating new MEK in JWK format..."
    MEK_KEY_RAW="$(openssl rand -base64 32 | tr -d '\n')"
    MEK_JWK="{\"k\":\"${MEK_KEY_RAW}\",\"kid\":\"${MEK_ID}\",\"kty\":\"oct\"}"
    MEK_ENCODED="$(echo -n "$MEK_JWK" | base64 | tr -d '\n')"
    log_success "New MEK generated"
fi

# Create MEK ConfigMap (OSMO expects ConfigMap, not Secret)
kubectl apply -n "${OSMO_NAMESPACE}" -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: mek-config
data:
  mek.yaml: |
    currentMek: ${MEK_ID}
    meks:
      ${MEK_ID}: ${MEK_ENCODED}
EOF

# Also create vault-secrets for backward compatibility (some OSMO versions need this)
kubectl create secret generic vault-secrets \
    --namespace "${OSMO_NAMESPACE}" \
    --from-literal=currentMek="${MEK_ID}" \
    --from-literal=vault-secrets.yaml="currentMek: ${MEK_ID}
meks:
  ${MEK_ID}: ${MEK_ENCODED}" \
    --dry-run=client -o yaml | kubectl apply -f -

log_success "MEK secrets created"

# -----------------------------------------------------------------------------
# Step 3.5: Deploy Redis (Required for OSMO rate limiting)
# -----------------------------------------------------------------------------
log_info "Deploying Redis..."

if kubectl get statefulset redis-master -n "${OSMO_NAMESPACE}" &>/dev/null; then
    log_info "Redis already deployed"
else
    helm upgrade --install redis bitnami/redis \
        --namespace "${OSMO_NAMESPACE}" \
        --set architecture=standalone \
        --set auth.enabled=false \
        --set master.persistence.size=1Gi \
        --set master.resources.requests.cpu=100m \
        --set master.resources.requests.memory=128Mi \
        --wait --timeout 5m
    
    log_success "Redis deployed"
fi

REDIS_HOST="redis-master.${OSMO_NAMESPACE}.svc.cluster.local"

# -----------------------------------------------------------------------------
# Step 4: Deploy Keycloak (Enable with DEPLOY_KEYCLOAK=true)
# -----------------------------------------------------------------------------
# Keycloak provides authentication for OSMO
# Required for: osmo login, osmo token, backend operator
# Reference: https://nvidia.github.io/OSMO/main/deployment_guide/getting_started/deploy_service.html#step-2-configure-keycloak

# Auto-detect TLS certificate early (needed for KC_EXTERNAL decision below)
TLS_SECRET="${OSMO_TLS_SECRET_NAME:-osmo-tls}"
TLS_ENABLED="false"
if kubectl get secret "${TLS_SECRET}" -n "${OSMO_NAMESPACE}" &>/dev/null; then
    log_info "TLS certificate detected (${TLS_SECRET})"
    TLS_ENABLED="true"
elif kubectl get certificate "${TLS_SECRET}" -n "${OSMO_NAMESPACE}" &>/dev/null; then
    log_info "TLS certificate pending (${TLS_SECRET})"
    TLS_ENABLED="true"
fi

# Keycloak service URL (same namespace as OSMO)
KEYCLOAK_HOST="keycloak.${OSMO_NAMESPACE}.svc.cluster.local"
KEYCLOAK_URL="http://${KEYCLOAK_HOST}:80"

# Derive Keycloak external hostname
# Priority: KEYCLOAK_HOSTNAME env var > auto-derive from OSMO_INGRESS_HOSTNAME > OSMO_DOMAIN
if [[ -n "${KEYCLOAK_HOSTNAME:-}" ]]; then
    AUTH_DOMAIN="${KEYCLOAK_HOSTNAME}"
elif [[ -n "${OSMO_INGRESS_HOSTNAME:-}" ]]; then
    AUTH_DOMAIN="auth.${OSMO_INGRESS_HOSTNAME}"
else
    AUTH_DOMAIN="auth.${OSMO_DOMAIN}"
fi
KC_TLS_SECRET="${KEYCLOAK_TLS_SECRET_NAME:-osmo-tls-auth}"

if [[ "${DEPLOY_KEYCLOAK:-false}" == "true" ]]; then
    log_info "Deploying Keycloak for OSMO authentication..."
    log_info "Reference: https://nvidia.github.io/OSMO/main/deployment_guide/getting_started/deploy_service.html#step-2-configure-keycloak"

    # Keycloak database was already created in Step 2 (osmo-db-init pod) when DEPLOY_KEYCLOAK=true

    # -------------------------------------------------------------------------
    # Step 4a: Create secrets for Keycloak
    # -------------------------------------------------------------------------
    log_info "Creating Keycloak secrets..."

    # Save admin password to secret for future re-runs
    kubectl create secret generic keycloak-admin-secret \
        --namespace "${OSMO_NAMESPACE}" \
        --from-literal=password="${KEYCLOAK_ADMIN_PASSWORD}" \
        --dry-run=client -o yaml | kubectl apply -f -

    # Create keycloak-db-secret for external database (per OSMO docs)
    kubectl create secret generic keycloak-db-secret \
        --namespace "${OSMO_NAMESPACE}" \
        --from-literal=postgres-password="${POSTGRES_PASSWORD}" \
        --dry-run=client -o yaml | kubectl apply -f -

    log_success "Keycloak secrets created"

    # -------------------------------------------------------------------------
    # Step 4b: Determine if Keycloak should use external TLS ingress
    # -------------------------------------------------------------------------
    KC_EXTERNAL="false"
    if [[ "$TLS_ENABLED" == "true" && -n "${OSMO_INGRESS_HOSTNAME:-}" ]]; then
        # Check TLS secret for auth domain exists
        if kubectl get secret "${KC_TLS_SECRET}" -n "${OSMO_NAMESPACE}" &>/dev/null || \
           kubectl get secret "${KC_TLS_SECRET}" -n "${INGRESS_NAMESPACE:-ingress-nginx}" &>/dev/null; then
            KC_EXTERNAL="true"
            log_info "Keycloak will be exposed externally at: https://${AUTH_DOMAIN}"
        elif kubectl get certificate "${KC_TLS_SECRET}" -n "${OSMO_NAMESPACE}" &>/dev/null; then
            KC_EXTERNAL="true"
            log_info "Keycloak TLS certificate pending — will create external ingress"
        else
            log_warning "TLS secret '${KC_TLS_SECRET}' for Keycloak not found."
            log_warning "Run: DEPLOY_KEYCLOAK=true ./04-enable-tls.sh ${OSMO_INGRESS_HOSTNAME}"
            log_warning "Keycloak will be internal-only (port-forward access)"
        fi
    fi

    # -------------------------------------------------------------------------
    # Step 4c: Install Keycloak using Bitnami Helm chart
    # -------------------------------------------------------------------------
    log_info "Installing Keycloak using Bitnami Helm chart..."

    # Add Bitnami repo
    helm repo add bitnami https://charts.bitnami.com/bitnami --force-update 2>/dev/null || true
    helm repo update bitnami

    # Create keycloak-values.yaml per OSMO documentation
    cat > /tmp/keycloak-values.yaml <<EOF
# Keycloak configuration for OSMO
# Based on: https://nvidia.github.io/OSMO/main/deployment_guide/getting_started/deploy_service.html#install-keycloak-using-bitnami-helm-chart

# Override the default image to use bitnamilegacy (no registry subscription needed)
global:
  security:
    allowInsecureImages: true

image:
  registry: docker.io
  repository: bitnamilegacy/keycloak
  tag: 26.1.1-debian-12-r0

$(if [[ "$KC_EXTERNAL" == "true" ]]; then
cat <<KC_PROD
# Production mode with TLS termination at NGINX ingress (proxy=edge)
production: true
proxy: edge
proxyHeaders: xforwarded
hostname: ${AUTH_DOMAIN}

# Admin user credentials
auth:
  adminUser: admin
  adminPassword: "${KEYCLOAK_ADMIN_PASSWORD}"

# Ingress (exposed via NGINX Ingress with TLS)
ingress:
  enabled: true
  tls: true
  ingressClassName: nginx
  hostname: ${AUTH_DOMAIN}
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
  path: /
  pathType: Prefix
  servicePort: 80
  extraTls:
    - hosts:
        - ${AUTH_DOMAIN}
      secretName: ${KC_TLS_SECRET}

# Autoscaling for production
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 3
  targetCPU: 80
  targetMemory: 80
KC_PROD
else
cat <<KC_DEV
# Development mode (no external ingress, use port-forward for access)
production: false

# Admin user credentials
auth:
  adminUser: admin
  adminPassword: "${KEYCLOAK_ADMIN_PASSWORD}"

# Disable ingress (use port-forward for access in this setup)
ingress:
  enabled: false

# Single replica for dev/test
replicaCount: 1
KC_DEV
fi)

# Resource allocation
resources:
  requests:
    cpu: "500m"
    memory: "512Mi"
  limits:
    cpu: "2"
    memory: "1Gi"

# External Database configuration (using Nebius Managed PostgreSQL)
postgresql:
  enabled: false
externalDatabase:
  host: "${POSTGRES_HOST}"
  port: ${POSTGRES_PORT}
  user: "${POSTGRES_USER}"
  password: "${POSTGRES_PASSWORD}"
  database: "keycloak"

# Additional environment variables (KC_BOOTSTRAP_* required for Keycloak 26.x)
extraEnvVars:
  # Admin bootstrap (required for Keycloak 26.x)
  - name: KC_BOOTSTRAP_ADMIN_USERNAME
    value: "admin"
  - name: KC_BOOTSTRAP_ADMIN_PASSWORD
    value: "${KEYCLOAK_ADMIN_PASSWORD}"
  - name: KEYCLOAK_ADMIN
    value: "admin"
  - name: KEYCLOAK_ADMIN_PASSWORD
    value: "${KEYCLOAK_ADMIN_PASSWORD}"
  # Database configuration (Bitnami entrypoint uses KEYCLOAK_DATABASE_* vars)
  - name: KEYCLOAK_DATABASE_HOST
    value: "${POSTGRES_HOST}"
  - name: KEYCLOAK_DATABASE_PORT
    value: "${POSTGRES_PORT}"
  - name: KEYCLOAK_DATABASE_NAME
    value: "keycloak"
  - name: KEYCLOAK_DATABASE_USER
    value: "${POSTGRES_USER}"
  - name: KEYCLOAK_DATABASE_PASSWORD
    value: "${POSTGRES_PASSWORD}"
  # Keycloak-native database configuration
  - name: KC_DB
    value: "postgres"
  - name: KC_DB_URL_HOST
    value: "${POSTGRES_HOST}"
  - name: KC_DB_URL_PORT
    value: "${POSTGRES_PORT}"
  - name: KC_DB_URL_DATABASE
    value: "keycloak"
  - name: KC_DB_USERNAME
    value: "${POSTGRES_USER}"
  - name: KC_DB_PASSWORD
    value: "${POSTGRES_PASSWORD}"
  # Hostname settings
$(if [[ "$KC_EXTERNAL" == "true" ]]; then
cat <<KC_HOSTNAME_VARS
  - name: KC_HOSTNAME
    value: "${AUTH_DOMAIN}"
  - name: KC_HOSTNAME_STRICT
    value: "true"
  - name: KC_HOSTNAME_STRICT_HTTPS
    value: "true"
  - name: KC_PROXY
    value: "edge"
KC_HOSTNAME_VARS
else
cat <<KC_DEV_VARS
  - name: KC_HOSTNAME_STRICT
    value: "false"
  - name: KC_HOSTNAME_STRICT_HTTPS
    value: "false"
KC_DEV_VARS
fi)
  - name: KC_HTTP_ENABLED
    value: "true"
  - name: KC_HEALTH_ENABLED
    value: "true"
EOF

    # Install or upgrade Keycloak
    helm upgrade --install keycloak bitnami/keycloak \
        --namespace "${OSMO_NAMESPACE}" \
        -f /tmp/keycloak-values.yaml \
        --timeout 10m || {
        log_warning "Helm install returned non-zero, checking pod status..."
    }

    rm -f /tmp/keycloak-values.yaml
    log_success "Keycloak Helm release installed"

    # Wait for Keycloak to be ready
    log_info "Waiting for Keycloak to be ready (this may take 3-5 minutes)..."

    # Wait for the pod to exist first
    for i in {1..30}; do
        if kubectl get pods -n "${OSMO_NAMESPACE}" -l app.kubernetes.io/name=keycloak 2>/dev/null | grep -q keycloak; then
            break
        fi
        echo "  Waiting for Keycloak pod to be created... ($i/30)"
        sleep 5
    done

    # Now wait for it to be ready
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=keycloak \
        -n "${OSMO_NAMESPACE}" --timeout=300s || {
        log_warning "Keycloak pod not ready yet, checking logs..."
        kubectl logs -n "${OSMO_NAMESPACE}" -l app.kubernetes.io/name=keycloak --tail=30 || true
    }

    # Additional wait for Keycloak to fully initialize
    log_info "Waiting for Keycloak to fully initialize..."
    sleep 30

    # -------------------------------------------------------------------------
    # Step 4c.1: Verify admin password works (handle stale DB)
    # -------------------------------------------------------------------------
    # KC_BOOTSTRAP_ADMIN_* only creates the admin user on FIRST database init.
    # If the keycloak DB already existed (e.g. from a prior deployment with a
    # different password), the bootstrap is a no-op and the stored password
    # won't match. We detect this and reset the password via SQL.
    log_info "Verifying Keycloak admin password..."

    KC_POD=$(kubectl get pods -n "${OSMO_NAMESPACE}" -l app.kubernetes.io/name=keycloak \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -n "$KC_POD" ]]; then
        KC_TOKEN_RESP=$(kubectl exec -n "${OSMO_NAMESPACE}" "${KC_POD}" -- \
            curl -s -X POST http://localhost:8080/realms/master/protocol/openid-connect/token \
            -d "client_id=admin-cli" \
            -d "username=admin" \
            -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
            -d "grant_type=password" 2>/dev/null || echo "")

        if echo "$KC_TOKEN_RESP" | grep -q "access_token"; then
            log_success "Keycloak admin password verified"
        else
            log_warning "Admin password mismatch (stale keycloak DB). Resetting via SQL..."
            # Use the db-init credentials to reset the admin password in the keycloak DB
            # Keycloak 26.x stores bcrypt hashes. We use the Keycloak KC_SPI approach instead:
            # Drop and recreate the keycloak database, then restart Keycloak so bootstrap runs fresh.
            kubectl delete pod osmo-kc-db-reset -n "${OSMO_NAMESPACE}" --ignore-not-found 2>/dev/null
            kubectl run osmo-kc-db-reset \
                --namespace "${OSMO_NAMESPACE}" \
                --image=postgres:16-alpine \
                --restart=Never \
                --env="PGPASSWORD=${POSTGRES_PASSWORD}" \
                --env="PGHOST=${POSTGRES_HOST}" \
                --env="PGPORT=${POSTGRES_PORT}" \
                --env="PGUSER=${POSTGRES_USER}" \
                --env="PGDATABASE=${POSTGRES_DB}" \
                --command -- sh -c '
                    echo "Dropping keycloak database..."
                    psql -c "DROP DATABASE IF EXISTS keycloak;"
                    echo "Recreating keycloak database..."
                    psql -c "CREATE DATABASE keycloak;"
                    echo "Done"
                ' >/dev/null 2>&1

            # Wait for reset pod
            for i in $(seq 1 30); do
                _rst_status=$(kubectl get pod osmo-kc-db-reset -n "${OSMO_NAMESPACE}" \
                    -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
                [[ "$_rst_status" == "Succeeded" || "$_rst_status" == "Failed" ]] && break
                sleep 2
            done
            kubectl logs osmo-kc-db-reset -n "${OSMO_NAMESPACE}" 2>/dev/null || true
            kubectl delete pod osmo-kc-db-reset -n "${OSMO_NAMESPACE}" --ignore-not-found 2>/dev/null

            if [[ "$_rst_status" == "Succeeded" ]]; then
                log_info "Keycloak DB reset. Restarting Keycloak pod for fresh bootstrap..."
                kubectl delete pod -n "${OSMO_NAMESPACE}" -l app.kubernetes.io/name=keycloak --wait=false
                sleep 10
                kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=keycloak \
                    -n "${OSMO_NAMESPACE}" --timeout=300s || log_warning "Keycloak pod not ready after restart"
                log_info "Waiting for Keycloak to fully initialize after restart..."
                sleep 20
                log_success "Keycloak restarted with fresh DB (admin password will match)"
            else
                log_error "Failed to reset keycloak DB. Admin password may not work."
                log_error "Manually reset: psql -h ${POSTGRES_HOST} -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c 'DROP DATABASE keycloak; CREATE DATABASE keycloak;'"
            fi
        fi
    fi

    # -------------------------------------------------------------------------
    # Step 4d: Import OSMO realm using official sample_osmo_realm.json
    # -------------------------------------------------------------------------
    log_info "Configuring Keycloak realm using official OSMO realm JSON..."

    # Generate client secret for osmo-browser-flow (confidential client)
    OIDC_CLIENT_SECRET=$(openssl rand -hex 16)

    # Determine OSMO base URL for client redirect URIs
    if [[ "$KC_EXTERNAL" == "true" ]]; then
        OSMO_BASE_URL="https://${OSMO_INGRESS_HOSTNAME}"
    else
        OSMO_BASE_URL="http://localhost:8080"
    fi

    # Upload the official realm JSON as a ConfigMap (so the job can mount it)
    log_info "Creating ConfigMap from sample_osmo_realm.json..."
    kubectl create configmap keycloak-realm-json \
        --namespace "${OSMO_NAMESPACE}" \
        --from-file=realm.json="${SCRIPT_DIR}/sample_osmo_realm.json" \
        --dry-run=client -o yaml | kubectl apply -f -

    # Create a job to import the realm and configure a test user
    cat > /tmp/keycloak-config-job.yaml <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: keycloak-osmo-setup
  namespace: ${OSMO_NAMESPACE}
spec:
  ttlSecondsAfterFinished: 300
  backoffLimit: 3
  template:
    spec:
      restartPolicy: OnFailure
      volumes:
      - name: realm-json
        configMap:
          name: keycloak-realm-json
      containers:
      - name: keycloak-setup
        image: curlimages/curl:8.5.0
        volumeMounts:
        - name: realm-json
          mountPath: /data
          readOnly: true
        command:
        - /bin/sh
        - -c
        - |
          set -e
          KEYCLOAK_URL="http://keycloak:80"

          echo "============================================"
          echo "  OSMO Keycloak Realm Import"
          echo "============================================"
          echo ""

          # -- Step 1: Prepare realm JSON --
          echo "=== Step 1: Prepare realm JSON ==="
          cp /data/realm.json /tmp/realm-import.json

          # Replace placeholder URLs with actual OSMO URL
          sed -i "s|https://default.com|${OSMO_BASE_URL}|g" /tmp/realm-import.json

          # Replace masked client secret with generated secret
          sed -i 's/"secret": "[*][*]*"/"secret": "${OIDC_CLIENT_SECRET}"/' /tmp/realm-import.json

          echo "  OSMO URL:   ${OSMO_BASE_URL}"
          echo "  Realm JSON: \$(wc -c < /tmp/realm-import.json) bytes"
          echo ""

          # -- Step 2: Wait for Keycloak --
          echo "=== Step 2: Wait for Keycloak ==="
          # NOTE: Keycloak 26.x serves /health/ready on the management port (9000),
          #       NOT on the main HTTP port (8080). The K8s service exposes port 80->8080,
          #       so /health/ready returns 404. Use /realms/master as readiness check instead.
          for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
            if curl -s -f "\${KEYCLOAK_URL}/realms/master" > /dev/null 2>&1; then
              echo "Keycloak is ready"
              break
            fi
            echo "  Attempt \$i: Keycloak not ready yet..."
            sleep 15
          done
          echo ""

          # -- Step 3: Get admin token --
          echo "=== Step 3: Get admin token ==="
          for i in 1 2 3 4 5; do
            TOKEN=\$(curl -s -X POST "\${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
              --data-urlencode "client_id=admin-cli" \
              --data-urlencode "username=admin" \
              --data-urlencode "password=${KEYCLOAK_ADMIN_PASSWORD}" \
              --data-urlencode "grant_type=password" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
            if [ -n "\$TOKEN" ]; then break; fi
            echo "  Retry \$i: waiting for token..."
            sleep 10
          done

          if [ -z "\$TOKEN" ]; then
            echo "FATAL: Failed to get admin token"
            exit 1
          fi
          echo "Got admin token"
          echo ""

          # -- Step 4: Import OSMO realm --
          echo "=== Step 4: Import OSMO realm ==="

          # Delete existing realm if present (idempotent re-runs)
          REALM_STATUS=\$(curl -s -o /dev/null -w "%{http_code}" "\${KEYCLOAK_URL}/admin/realms/osmo" \
            -H "Authorization: Bearer \$TOKEN")
          if [ "\$REALM_STATUS" = "200" ]; then
            echo "  Existing 'osmo' realm found - deleting for fresh import..."
            curl -s -X DELETE "\${KEYCLOAK_URL}/admin/realms/osmo" \
              -H "Authorization: Bearer \$TOKEN"
            echo "  Old realm deleted"
            sleep 5
          fi

          echo "Importing official OSMO realm from sample_osmo_realm.json..."
          IMPORT_HTTP=\$(curl -s -o /tmp/import-resp.txt -w "%{http_code}" \
            -X POST "\${KEYCLOAK_URL}/admin/realms" \
            -H "Authorization: Bearer \$TOKEN" \
            -H "Content-Type: application/json" \
            -d @/tmp/realm-import.json)

          if [ "\$IMPORT_HTTP" = "201" ] || [ "\$IMPORT_HTTP" = "204" ]; then
            echo "Realm imported successfully (HTTP \$IMPORT_HTTP)"
          else
            echo "WARNING: Realm import returned HTTP \$IMPORT_HTTP"
            cat /tmp/import-resp.txt 2>/dev/null || true
            echo ""
            echo "Trying partial import as fallback..."
            curl -s -X POST "\${KEYCLOAK_URL}/admin/realms/osmo/partialImport" \
              -H "Authorization: Bearer \$TOKEN" \
              -H "Content-Type: application/json" \
              -d @/tmp/realm-import.json || echo "Partial import also failed"
          fi

          # Verify realm exists
          sleep 3
          VERIFY=\$(curl -s -o /dev/null -w "%{http_code}" "\${KEYCLOAK_URL}/admin/realms/osmo" \
            -H "Authorization: Bearer \$TOKEN")
          if [ "\$VERIFY" != "200" ]; then
            echo "FATAL: Realm 'osmo' not found after import (HTTP \$VERIFY)"
            exit 1
          fi
          echo "Realm 'osmo' verified"
          echo ""

          # -- Step 5: Create test user --
          echo "=== Step 5: Create test user ==="

          # Refresh admin token
          TOKEN=\$(curl -s -X POST "\${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
            --data-urlencode "client_id=admin-cli" \
            --data-urlencode "username=admin" \
            --data-urlencode "password=${KEYCLOAK_ADMIN_PASSWORD}" \
            --data-urlencode "grant_type=password" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

          echo "Creating osmo-admin test user..."
          curl -s -X POST "\${KEYCLOAK_URL}/admin/realms/osmo/users" \
            -H "Authorization: Bearer \$TOKEN" \
            -H "Content-Type: application/json" \
            -d '{
              "username": "osmo-admin",
              "enabled": true,
              "emailVerified": true,
              "firstName": "OSMO",
              "lastName": "Admin",
              "email": "osmo-admin@example.com",
              "credentials": [{"type":"password","value":"osmo-admin","temporary":false}]
            }' || echo "User may already exist"
          echo ""

          # -- Step 6: Assign user to Admin group --
          echo "=== Step 6: Assign user to Admin group ==="

          USER_ID=\$(curl -s "\${KEYCLOAK_URL}/admin/realms/osmo/users?username=osmo-admin" \
            -H "Authorization: Bearer \$TOKEN" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

          if [ -n "\$USER_ID" ]; then
            echo "  User ID: \$USER_ID"

            ADMIN_GROUP_ID=\$(curl -s "\${KEYCLOAK_URL}/admin/realms/osmo/groups?search=Admin" \
              -H "Authorization: Bearer \$TOKEN" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

            if [ -n "\$ADMIN_GROUP_ID" ]; then
              echo "  Admin Group ID: \$ADMIN_GROUP_ID"
              curl -s -X PUT "\${KEYCLOAK_URL}/admin/realms/osmo/users/\${USER_ID}/groups/\${ADMIN_GROUP_ID}" \
                -H "Authorization: Bearer \$TOKEN" \
                -H "Content-Type: application/json" \
                -d '{}' || echo "Failed to assign group"
              echo "  User 'osmo-admin' assigned to Admin group (osmo-admin + osmo-user roles)"
            else
              echo "  WARNING: Admin group not found - user roles may need manual assignment"
            fi
          else
            echo "  WARNING: Could not find osmo-admin user ID"
          fi
          echo ""

          # -- Done --
          echo "========================================="
          echo "  Keycloak OSMO Configuration Complete"
          echo "========================================="
          echo ""
          echo "Realm:    osmo (imported from official sample_osmo_realm.json)"
          echo "Clients:  osmo-device        (public, device code + direct access)"
          echo "          osmo-browser-flow   (confidential, authorization code)"
          echo "Groups:   Admin, User, Backend Operator"
          echo "Roles:    osmo-admin, osmo-user, osmo-backend, grafana-*, dashboard-*"
          echo "Mappers:  JWT 'roles' claim configured on both clients"
          echo "Test user: osmo-admin / osmo-admin (Admin group)"
          echo ""
EOF

    # Delete any previous config job
    kubectl delete job keycloak-osmo-setup -n "${KEYCLOAK_NAMESPACE}" --ignore-not-found 2>/dev/null || true

    kubectl apply -f /tmp/keycloak-config-job.yaml

    log_info "Waiting for Keycloak realm import job..."
    kubectl wait --for=condition=complete job/keycloak-osmo-setup \
        -n "${KEYCLOAK_NAMESPACE}" --timeout=300s || {
        log_warning "Keycloak configuration may have failed, check logs:"
        kubectl logs -n "${KEYCLOAK_NAMESPACE}" -l job-name=keycloak-osmo-setup --tail=50 || true
    }

    # Store the client secret for OIDC (used by Envoy sidecar)
    kubectl create secret generic oidc-secrets \
        --namespace "${OSMO_NAMESPACE}" \
        --from-literal=client_secret="${OIDC_CLIENT_SECRET}" \
        --from-literal=hmac_secret="$(openssl rand -base64 32)" \
        --dry-run=client -o yaml | kubectl apply -f -

    # Clean up temporary files and ConfigMap
    rm -f /tmp/keycloak-config-job.yaml
    kubectl delete configmap keycloak-realm-json -n "${OSMO_NAMESPACE}" --ignore-not-found 2>/dev/null || true

    log_success "Keycloak deployed and configured"
    echo ""
    if [[ "$KC_EXTERNAL" == "true" ]]; then
        echo "Keycloak Access (external):"
        echo "  URL: https://${AUTH_DOMAIN}"
        echo "  Admin console: https://${AUTH_DOMAIN}/admin"
        echo "  Admin: admin / ${KEYCLOAK_ADMIN_PASSWORD}"
        echo "  Test User: osmo-admin / osmo-admin"
        echo ""
        echo "OSMO Auth Endpoints:"
        echo "  Token: https://${AUTH_DOMAIN}/realms/osmo/protocol/openid-connect/token"
        echo "  Auth:  https://${AUTH_DOMAIN}/realms/osmo/protocol/openid-connect/auth"
        echo ""
        # Enable OSMO auth with Envoy sidecars (production mode)
        AUTH_ENABLED="true"
        KEYCLOAK_EXTERNAL_URL="https://${AUTH_DOMAIN}"
        log_success "OSMO authentication will be ENABLED with Envoy sidecars"
    else
        echo "Keycloak Access (port-forward only):"
        echo "  kubectl port-forward -n ${KEYCLOAK_NAMESPACE} svc/keycloak 8081:80"
        echo "  URL: http://localhost:8081"
        echo "  Admin: admin / ${KEYCLOAK_ADMIN_PASSWORD}"
        echo "  Test User: osmo-admin / osmo-admin"
        echo ""
        echo "OSMO Auth Endpoints (in-cluster):"
        echo "  Token: ${KEYCLOAK_URL}/realms/osmo/protocol/openid-connect/token"
        echo "  Auth:  ${KEYCLOAK_URL}/realms/osmo/protocol/openid-connect/auth"
        echo ""
        # Auth disabled when Keycloak is internal-only
        AUTH_ENABLED="false"
        KEYCLOAK_EXTERNAL_URL=""
        log_info "Note: OSMO auth disabled (Keycloak is internal-only, no TLS ingress)"
        log_info "To enable auth, run: DEPLOY_KEYCLOAK=true ./04-enable-tls.sh ${OSMO_INGRESS_HOSTNAME:-<hostname>}"
    fi
else
    log_info "Skipping Keycloak (set DEPLOY_KEYCLOAK=true to enable)"
    log_warning "Without Keycloak, 'osmo login' and token creation will not work"
    log_info "Reference: https://nvidia.github.io/OSMO/main/deployment_guide/getting_started/deploy_service.html#step-2-configure-keycloak"
    AUTH_ENABLED="false"
    KEYCLOAK_EXTERNAL_URL=""
fi

# -----------------------------------------------------------------------------
# Step 5: Create OSMO Values File
# -----------------------------------------------------------------------------
log_info "Creating OSMO values file..."

# NGINX Ingress – run 03-deploy-nginx-ingress.sh before this script
# When OSMO_INGRESS_HOSTNAME is empty (default), ingress matches any Host header,
# allowing direct IP-based access. Set it to a real domain for host-based routing.
INGRESS_HOSTNAME="${OSMO_INGRESS_HOSTNAME:-}"
if [[ -n "$INGRESS_HOSTNAME" ]]; then
    log_info "Ingress hostname: ${INGRESS_HOSTNAME}"
else
    log_info "Ingress hostname: (any — IP-based access)"
fi

# TLS_SECRET and TLS_ENABLED were already set earlier (before Keycloak section)
if [[ "$TLS_ENABLED" == "true" ]]; then
    log_success "TLS certificate detected (${TLS_SECRET}) — will create HTTPS Ingress"
fi

# Create the values file with proper extraEnv and extraVolumes for each service
# This configures PostgreSQL password via env var and MEK via volume mount
cat > /tmp/osmo_values.yaml <<EOF
# OSMO Service values for Nebius deployment
# https://nvidia.github.io/OSMO/main/deployment_guide/getting_started/deploy_service.html

global:
  osmoImageLocation: nvcr.io/nvidia/osmo
  osmoImageTag: latest
  imagePullPolicy: IfNotPresent

# Service configurations (external - not deploying in chart)
services:
  postgres:
    enabled: false
    serviceName: "${POSTGRES_HOST}"
    port: ${POSTGRES_PORT}
    db: osmo
    user: "${POSTGRES_USER}"
    passwordSecretName: postgres-secret
    passwordSecretKey: password
  
  redis:
    enabled: false
    serviceName: "${REDIS_HOST}"
    port: 6379
    tlsEnabled: false
  
  # API service config
  service:
    scaling:
      minReplicas: 1
      maxReplicas: 1
    ingress:
      enabled: true
      prefix: /
      ingressClass: nginx
      sslEnabled: false
      annotations:
        nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
        nginx.ingress.kubernetes.io/proxy-buffers: "8 16k"
        nginx.ingress.kubernetes.io/proxy-busy-buffers-size: "32k"
        nginx.ingress.kubernetes.io/large-client-header-buffers: "4 16k"
    # Authentication configuration
$(if [[ "$AUTH_ENABLED" == "true" ]]; then
cat <<AUTH_BLOCK
    auth:
      enabled: true
      device_endpoint: ${KEYCLOAK_EXTERNAL_URL}/realms/osmo/protocol/openid-connect/auth/device
      device_client_id: osmo-device
      browser_endpoint: ${KEYCLOAK_EXTERNAL_URL}/realms/osmo/protocol/openid-connect/auth
      browser_client_id: osmo-browser-flow
      token_endpoint: ${KEYCLOAK_EXTERNAL_URL}/realms/osmo/protocol/openid-connect/token
      logout_endpoint: ${KEYCLOAK_EXTERNAL_URL}/realms/osmo/protocol/openid-connect/logout
AUTH_BLOCK
else
cat <<NOAUTH_BLOCK
    # NOTE: Auth is DISABLED. Set DEPLOY_KEYCLOAK=true with TLS to enable.
    auth:
      enabled: false
NOAUTH_BLOCK
fi)
    # PostgreSQL env vars (chart doesn't inject when postgres.enabled=false)
    extraEnv:
      - name: OSMO_POSTGRES_HOST
        value: "${POSTGRES_HOST}"
      - name: OSMO_POSTGRES_PORT
        value: "${POSTGRES_PORT}"
      - name: OSMO_POSTGRES_USER
        value: "${POSTGRES_USER}"
      - name: OSMO_POSTGRES_DATABASE
        value: "osmo"
      - name: OSMO_POSTGRES_PASSWORD
        valueFrom:
          secretKeyRef:
            name: postgres-secret
            key: password
      # Disable built-in OTEL metrics exporter (no collector at localhost:12345)
      - name: METRICS_OTEL_ENABLE
        value: "false"
    # MEK volume mount
    extraVolumes:
      - name: vault-secrets
        secret:
          secretName: vault-secrets
    extraVolumeMounts:
      - name: vault-secrets
        mountPath: /home/osmo/vault-agent/secrets
        readOnly: true
  
  # Worker service config
  worker:
    scaling:
      minReplicas: 1
      maxReplicas: 1
    extraEnv:
      - name: OSMO_POSTGRES_HOST
        value: "${POSTGRES_HOST}"
      - name: OSMO_POSTGRES_PORT
        value: "${POSTGRES_PORT}"
      - name: OSMO_POSTGRES_USER
        value: "${POSTGRES_USER}"
      - name: OSMO_POSTGRES_DATABASE
        value: "osmo"
      - name: OSMO_POSTGRES_PASSWORD
        valueFrom:
          secretKeyRef:
            name: postgres-secret
            key: password
      # Disable built-in OTEL metrics exporter (no collector at localhost:12345)
      - name: METRICS_OTEL_ENABLE
        value: "false"
    extraVolumes:
      - name: vault-secrets
        secret:
          secretName: vault-secrets
    extraVolumeMounts:
      - name: vault-secrets
        mountPath: /home/osmo/vault-agent/secrets
        readOnly: true
  
  # Logger service config
  logger:
    scaling:
      minReplicas: 1
      maxReplicas: 1
    extraEnv:
      - name: OSMO_POSTGRES_HOST
        value: "${POSTGRES_HOST}"
      - name: OSMO_POSTGRES_PORT
        value: "${POSTGRES_PORT}"
      - name: OSMO_POSTGRES_USER
        value: "${POSTGRES_USER}"
      - name: OSMO_POSTGRES_DATABASE
        value: "osmo"
      - name: OSMO_POSTGRES_PASSWORD
        valueFrom:
          secretKeyRef:
            name: postgres-secret
            key: password
      # Disable built-in OTEL metrics exporter (no collector at localhost:12345)
      - name: METRICS_OTEL_ENABLE
        value: "false"
    extraVolumes:
      - name: vault-secrets
        secret:
          secretName: vault-secrets
    extraVolumeMounts:
      - name: vault-secrets
        mountPath: /home/osmo/vault-agent/secrets
        readOnly: true
  
  # Agent service config
  agent:
    scaling:
      minReplicas: 1
      maxReplicas: 1
    extraEnv:
      - name: OSMO_POSTGRES_HOST
        value: "${POSTGRES_HOST}"
      - name: OSMO_POSTGRES_PORT
        value: "${POSTGRES_PORT}"
      - name: OSMO_POSTGRES_USER
        value: "${POSTGRES_USER}"
      - name: OSMO_POSTGRES_DATABASE
        value: "osmo"
      - name: OSMO_POSTGRES_PASSWORD
        valueFrom:
          secretKeyRef:
            name: postgres-secret
            key: password
      # Disable built-in OTEL metrics exporter (no collector at localhost:12345)
      - name: METRICS_OTEL_ENABLE
        value: "false"
    extraVolumes:
      - name: vault-secrets
        secret:
          secretName: vault-secrets
    extraVolumeMounts:
      - name: vault-secrets
        mountPath: /home/osmo/vault-agent/secrets
        readOnly: true
  
  # Delayed job monitor config
  delayedJobMonitor:
    replicas: 1
    extraEnv:
      - name: OSMO_POSTGRES_HOST
        value: "${POSTGRES_HOST}"
      - name: OSMO_POSTGRES_PORT
        value: "${POSTGRES_PORT}"
      - name: OSMO_POSTGRES_USER
        value: "${POSTGRES_USER}"
      - name: OSMO_POSTGRES_DATABASE
        value: "osmo"
      - name: OSMO_POSTGRES_PASSWORD
        valueFrom:
          secretKeyRef:
            name: postgres-secret
            key: password
      # Disable built-in OTEL metrics exporter (no collector at localhost:12345)
      - name: METRICS_OTEL_ENABLE
        value: "false"
    extraVolumes:
      - name: vault-secrets
        secret:
          secretName: vault-secrets
    extraVolumeMounts:
      - name: vault-secrets
        mountPath: /home/osmo/vault-agent/secrets
        readOnly: true

# Sidecar configurations
$(if [[ "$AUTH_ENABLED" == "true" ]]; then
cat <<ENVOY_ENABLED
sidecars:
  envoy:
    enabled: true
    useKubernetesSecrets: true

    # Paths that bypass authentication entirely
    skipAuthPaths:
      - /api/version
      - /api/auth/login
      - /api/auth/keys
      - /api/auth/refresh_token
      - /api/auth/jwt/refresh_token
      - /api/auth/jwt/access_token
      - /client/version

    service:
      port: 8000
      hostname: ${INGRESS_HOSTNAME}
      address: 127.0.0.1

    # OAuth2 Filter config (browser flow -> Keycloak)
    oauth2Filter:
      enabled: true
      tokenEndpoint: ${KEYCLOAK_EXTERNAL_URL}/realms/osmo/protocol/openid-connect/token
      authEndpoint: ${KEYCLOAK_EXTERNAL_URL}/realms/osmo/protocol/openid-connect/auth
      clientId: osmo-browser-flow
      authProvider: ${AUTH_DOMAIN}
      secretName: oidc-secrets
      clientSecretKey: client_secret
      hmacSecretKey: hmac_secret

    # JWT Filter config -- three providers
    jwt:
      user_header: x-osmo-user
      providers:
        # Provider 1: Keycloak device flow (CLI)
        - issuer: ${KEYCLOAK_EXTERNAL_URL}/realms/osmo
          audience: osmo-device
          jwks_uri: ${KEYCLOAK_EXTERNAL_URL}/realms/osmo/protocol/openid-connect/certs
          user_claim: preferred_username
          cluster: oauth
        # Provider 2: Keycloak browser flow (Web UI)
        - issuer: ${KEYCLOAK_EXTERNAL_URL}/realms/osmo
          audience: osmo-browser-flow
          jwks_uri: ${KEYCLOAK_EXTERNAL_URL}/realms/osmo/protocol/openid-connect/certs
          user_claim: preferred_username
          cluster: oauth
        # Provider 3: OSMO-signed JWTs (service accounts)
        - issuer: osmo
          audience: osmo
          jwks_uri: http://localhost:8000/api/auth/keys
          user_claim: unique_name
          cluster: service
ENVOY_ENABLED
else
cat <<ENVOY_DISABLED
sidecars:
  envoy:
    enabled: false
    service:
      hostname: ${OSMO_DOMAIN}
ENVOY_DISABLED
fi)

  # Disable rate limiting (requires proper Redis config)
  rateLimit:
    enabled: false

  # Disable log agent (configured for AWS CloudWatch by default, not available on Nebius)
  logAgent:
    enabled: false

  # Disable OTEL (requires proper OTEL backend configuration)
  otel:
    enabled: false
EOF

# -----------------------------------------------------------------------------
# Step 6: Deploy OSMO Service
# -----------------------------------------------------------------------------
log_info "Deploying OSMO Service..."

SERVICE_HELM_ARGS=(
    --namespace "${OSMO_NAMESPACE}"
    -f /tmp/osmo_values.yaml
)
[[ -n "$INGRESS_HOSTNAME" ]] && SERVICE_HELM_ARGS+=(--set "services.service.hostname=${INGRESS_HOSTNAME}")

helm upgrade --install osmo-service osmo/service \
    "${SERVICE_HELM_ARGS[@]}" \
    --wait --timeout 10m || {
    log_warning "OSMO Service deployment had issues"
    log_info "Checking pod status..."
    kubectl get pods -n "${OSMO_NAMESPACE}" --no-headers | head -10
}

log_success "OSMO Service deployed"

log_success "OSMO Service Helm deployment complete"

# -----------------------------------------------------------------------------
# Step 7: Deploy Router
# -----------------------------------------------------------------------------
log_info "Deploying OSMO Router..."

# Router requires configFile.enabled=true to mount the mek-config ConfigMap
# It also needs db-secret (not postgres-secret) for the password
kubectl create secret generic db-secret \
    --namespace "${OSMO_NAMESPACE}" \
    --from-literal=db-password="${POSTGRES_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -

# Build router values file (using YAML file instead of --set to avoid array escaping issues)
cat > /tmp/osmo_router_values.yaml <<EOF
global:
  domain: ${INGRESS_HOSTNAME:-osmo.local}

service:
  type: ClusterIP

services:
  configFile:
    enabled: true
  postgres:
    serviceName: "${POSTGRES_HOST}"
    port: ${POSTGRES_PORT}
    db: osmo
    user: "${POSTGRES_USER}"
  service:
    hostname: ${INGRESS_HOSTNAME:-}
    ingress:
      enabled: true
      ingressClass: nginx
      sslEnabled: false
      annotations:
        nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
        nginx.ingress.kubernetes.io/proxy-buffers-number: "4"
    scaling:
      minReplicas: 1
      maxReplicas: 1

sidecars:
  logAgent:
    enabled: false
$(if [[ "$AUTH_ENABLED" == "true" ]]; then
cat <<ROUTER_ENVOY
  envoy:
    enabled: true
    useKubernetesSecrets: true
    skipAuthPaths:
      - /api/router/version
    service:
      hostname: ${INGRESS_HOSTNAME}
    oauth2Filter:
      enabled: true
      forwardBearerToken: true
      tokenEndpoint: ${KEYCLOAK_EXTERNAL_URL}/realms/osmo/protocol/openid-connect/token
      authEndpoint: ${KEYCLOAK_EXTERNAL_URL}/realms/osmo/protocol/openid-connect/auth
      clientId: osmo-browser-flow
      authProvider: ${AUTH_DOMAIN}
      redirectPath: api/auth/getAToken
      logoutPath: logout
      secretName: oidc-secrets
      clientSecretKey: client_secret
      hmacSecretKey: hmac_secret
    jwt:
      enabled: true
      user_header: x-osmo-user
      providers:
        - issuer: ${KEYCLOAK_EXTERNAL_URL}/realms/osmo
          audience: osmo-device
          jwks_uri: ${KEYCLOAK_EXTERNAL_URL}/realms/osmo/protocol/openid-connect/certs
          user_claim: preferred_username
          cluster: oauth
        - issuer: ${KEYCLOAK_EXTERNAL_URL}/realms/osmo
          audience: osmo-browser-flow
          jwks_uri: ${KEYCLOAK_EXTERNAL_URL}/realms/osmo/protocol/openid-connect/certs
          user_claim: preferred_username
          cluster: oauth
        - issuer: osmo
          audience: osmo
          jwks_uri: http://osmo-service/api/auth/keys
          user_claim: unique_name
          cluster: osmoauth
    osmoauth:
      enabled: true
      port: 80
      hostname: ${INGRESS_HOSTNAME}
      address: osmo-service
ROUTER_ENVOY
else
echo "  envoy:"
echo "    enabled: false"
fi)
EOF

helm upgrade --install osmo-router osmo/router \
    --namespace "${OSMO_NAMESPACE}" \
    -f /tmp/osmo_router_values.yaml \
    --wait --timeout 5m || log_warning "Router deployment had issues"

rm -f /tmp/osmo_router_values.yaml

log_success "OSMO Router deployed"

# -----------------------------------------------------------------------------
# Step 8: Deploy Web UI (Optional)
# -----------------------------------------------------------------------------
if [[ "${DEPLOY_UI:-true}" == "true" ]]; then
    log_info "Deploying OSMO Web UI..."

    # Build UI values file (using YAML to avoid array escaping issues with --set)
    cat > /tmp/osmo_ui_values.yaml <<EOF
global:
  domain: ${INGRESS_HOSTNAME:-osmo.local}

services:
  ui:
    hostname: ${INGRESS_HOSTNAME:-}
    service:
      type: ClusterIP
    ingress:
      enabled: true
      ingressClass: nginx
      sslEnabled: false
      annotations:
        nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
        nginx.ingress.kubernetes.io/proxy-buffers-number: "4"
    replicas: 1
    apiHostname: osmo-service.${OSMO_NAMESPACE}.svc.cluster.local:80

sidecars:
  logAgent:
    enabled: false
$(if [[ "$AUTH_ENABLED" == "true" ]]; then
cat <<UI_ENVOY
  envoy:
    enabled: true
    useKubernetesSecrets: true
    service:
      hostname: ${INGRESS_HOSTNAME}
      address: 127.0.0.1
      port: 8000
    oauth2Filter:
      enabled: true
      tokenEndpoint: ${KEYCLOAK_EXTERNAL_URL}/realms/osmo/protocol/openid-connect/token
      authEndpoint: ${KEYCLOAK_EXTERNAL_URL}/realms/osmo/protocol/openid-connect/auth
      redirectPath: getAToken
      clientId: osmo-browser-flow
      authProvider: ${AUTH_DOMAIN}
      logoutPath: logout
      secretName: oidc-secrets
      clientSecretKey: client_secret
      hmacSecretKey: hmac_secret
    jwt:
      user_header: x-osmo-user
      providers:
        - issuer: ${KEYCLOAK_EXTERNAL_URL}/realms/osmo
          audience: osmo-device
          jwks_uri: ${KEYCLOAK_EXTERNAL_URL}/realms/osmo/protocol/openid-connect/certs
          user_claim: preferred_username
          cluster: oauth
        - issuer: ${KEYCLOAK_EXTERNAL_URL}/realms/osmo
          audience: osmo-browser-flow
          jwks_uri: ${KEYCLOAK_EXTERNAL_URL}/realms/osmo/protocol/openid-connect/certs
          user_claim: preferred_username
          cluster: oauth
UI_ENVOY
else
echo "  envoy:"
echo "    enabled: false"
fi)
EOF

    helm upgrade --install osmo-ui osmo/web-ui \
        --namespace "${OSMO_NAMESPACE}" \
        -f /tmp/osmo_ui_values.yaml \
        --wait --timeout 5m || log_warning "UI deployment had issues"

    rm -f /tmp/osmo_ui_values.yaml
    log_success "OSMO Web UI deployed"
fi

# Cleanup temp files
rm -f /tmp/osmo_values.yaml

# -----------------------------------------------------------------------------
# Step 8.5: Patch Ingress resources with TLS (if cert exists from 04-enable-tls.sh)
# -----------------------------------------------------------------------------
if [[ "$TLS_ENABLED" == "true" && -n "$INGRESS_HOSTNAME" ]]; then
    log_info "Patching Ingress resources for TLS..."
    for ing in $(kubectl get ingress -n "${OSMO_NAMESPACE}" -o name 2>/dev/null); do
        ing_name="${ing#*/}"
        [[ "$ing_name" == "osmo-tls-bootstrap" ]] && continue  # skip bootstrap ingress
        CURRENT_HTTP=$(kubectl get "$ing" -n "${OSMO_NAMESPACE}" -o jsonpath='{.spec.rules[0].http}')

        kubectl patch "$ing" -n "${OSMO_NAMESPACE}" --type=merge -p "$(cat <<PATCH
{
  "metadata": {
    "annotations": {
      "cert-manager.io/cluster-issuer": "letsencrypt"
    }
  },
  "spec": {
    "tls": [{
      "hosts": ["${INGRESS_HOSTNAME}"],
      "secretName": "${TLS_SECRET}"
    }],
    "rules": [{
      "host": "${INGRESS_HOSTNAME}",
      "http": ${CURRENT_HTTP}
    }]
  }
}
PATCH
)" && log_success "  ${ing_name}: TLS enabled" || log_warning "  Failed to patch ${ing_name}"
    done

    # Remove the bootstrap ingress (created by 04-enable-tls.sh Mode A)
    kubectl delete ingress osmo-tls-bootstrap -n "${OSMO_NAMESPACE}" --ignore-not-found 2>/dev/null
    log_success "Ingress TLS patching complete"
fi

# -----------------------------------------------------------------------------
# Step 9: Patch Deployments to Add vault-secrets Volume
# -----------------------------------------------------------------------------
# NOTE: The Helm chart's extraVolumes/extraVolumeMounts values don't work reliably.
# We must patch the deployments after Helm creates them to add the vault-secrets volume.
# This is a known workaround - the env vars work via extraEnv, but volumes don't.

log_info "Patching OSMO deployments to add vault-secrets volume mount..."

# Create the JSON patch file
cat > /tmp/vault-patch.json << 'PATCH_EOF'
[
  {"op": "add", "path": "/spec/template/spec/volumes/-", "value": {"name": "vault-secrets", "secret": {"secretName": "vault-secrets"}}},
  {"op": "add", "path": "/spec/template/spec/containers/0/volumeMounts/-", "value": {"name": "vault-secrets", "mountPath": "/home/osmo/vault-agent/secrets", "readOnly": true}}
]
PATCH_EOF

# All OSMO deployments that need the vault-secrets volume for MEK
OSMO_DEPLOYMENTS="osmo-service osmo-worker osmo-agent osmo-logger osmo-delayed-job-monitor osmo-router"

for deploy in $OSMO_DEPLOYMENTS; do
    if kubectl get deployment/$deploy -n "${OSMO_NAMESPACE}" &>/dev/null; then
        # Check if vault-secrets volume already exists
        EXISTING_VOL=$(kubectl get deployment/$deploy -n "${OSMO_NAMESPACE}" \
            -o jsonpath='{.spec.template.spec.volumes[*].name}' 2>/dev/null | grep -w "vault-secrets" || true)
        
        if [[ -z "$EXISTING_VOL" ]]; then
            log_info "  Patching $deploy to add vault-secrets volume..."
            if kubectl patch deployment/$deploy -n "${OSMO_NAMESPACE}" --type=json --patch-file=/tmp/vault-patch.json; then
                log_success "  $deploy patched successfully"
            else
                log_warning "  Failed to patch $deploy"
            fi
        else
            log_info "  $deploy already has vault-secrets volume, skipping"
        fi
    else
        log_info "  $deploy not found, skipping"
    fi
done

# Cleanup patch file
rm -f /tmp/vault-patch.json

# Wait for rollouts to complete
log_info "Waiting for deployments to roll out with new configuration..."
for deploy in $OSMO_DEPLOYMENTS; do
    if kubectl get deployment/$deploy -n "${OSMO_NAMESPACE}" &>/dev/null; then
        kubectl rollout status deployment/$deploy -n "${OSMO_NAMESPACE}" --timeout=180s || \
            log_warning "  Timeout waiting for $deploy rollout"
    fi
done

log_success "All OSMO deployments patched with vault-secrets volume"

# -----------------------------------------------------------------------------
# Step 10: Patch Services for Direct Access (without Envoy)
# -----------------------------------------------------------------------------
# When Envoy sidecar is disabled, services need to target port 8000 directly
# instead of the 'envoy-http' named port which doesn't exist.
# When Envoy IS enabled, the 'envoy-http' targetPort is correct -- skip patching.

if [[ "$AUTH_ENABLED" == "true" ]]; then
    log_info "Envoy sidecar is ENABLED -- skipping targetPort patches (envoy-http is correct)"
else
    log_info "Verifying service ports (Envoy disabled)..."

    OSMO_SERVICES="osmo-service osmo-router osmo-logger osmo-agent"

    for svc in $OSMO_SERVICES; do
        if kubectl get svc "$svc" -n "${OSMO_NAMESPACE}" &>/dev/null; then
            CURRENT_TARGET=$(kubectl get svc "$svc" -n "${OSMO_NAMESPACE}" \
                -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null || echo "")

            if [[ "$CURRENT_TARGET" == "envoy-http" || "$CURRENT_TARGET" == "envoy" ]]; then
                log_info "  Patching $svc: targetPort envoy-http -> 8000"
                kubectl patch svc "$svc" -n "${OSMO_NAMESPACE}" --type='json' \
                    -p='[{"op": "replace", "path": "/spec/ports/0/targetPort", "value": 8000}]' || \
                    log_warning "  Failed to patch $svc"
            else
                log_info "  $svc: targetPort = $CURRENT_TARGET (OK)"
            fi
        fi
    done

    log_success "Service ports verified"
fi

# -----------------------------------------------------------------------------
# Step 11: Verify Deployment
# -----------------------------------------------------------------------------
echo ""
log_info "Verifying deployment configuration..."

# Verify vault-secrets volumes are mounted
echo ""
echo "Volume configuration verification:"
for deploy in $OSMO_DEPLOYMENTS; do
    if kubectl get deployment/$deploy -n "${OSMO_NAMESPACE}" &>/dev/null; then
        VOL_CHECK=$(kubectl get deployment/$deploy -n "${OSMO_NAMESPACE}" \
            -o jsonpath='{.spec.template.spec.volumes[*].name}' 2>/dev/null | grep -w "vault-secrets" || echo "")
        ENV_CHECK=$(kubectl get deployment/$deploy -n "${OSMO_NAMESPACE}" \
            -o jsonpath='{.spec.template.spec.containers[0].env[*].name}' 2>/dev/null | grep -w "OSMO_POSTGRES_PASSWORD" || echo "")
        
        VOL_STATUS="✗"
        ENV_STATUS="✗"
        [[ -n "$VOL_CHECK" ]] && VOL_STATUS="✓"
        [[ -n "$ENV_CHECK" ]] && ENV_STATUS="✓"
        
        echo "  $deploy: vault-secrets=$VOL_STATUS, postgres_env=$ENV_STATUS"
    fi
done

echo ""
echo "Pods:"
kubectl get pods -n "${OSMO_NAMESPACE}"

echo ""
echo "Services:"
kubectl get svc -n "${OSMO_NAMESPACE}"

# -----------------------------------------------------------------------------
# Step 12: Configure service_base_url (required for workflow execution)
# -----------------------------------------------------------------------------
# The osmo-ctrl sidecar in every workflow pod needs service_base_url to
# stream logs, report task status, and refresh tokens.
# This is an application-level config that must be set via the OSMO API.

echo ""
log_info "Configuring service_base_url for workflow execution..."

# Detect target URL from Ingress
INGRESS_URL=$(detect_service_url 2>/dev/null || true)

if [[ -n "${OSMO_INGRESS_BASE_URL:-}" ]]; then
    TARGET_SERVICE_URL="${OSMO_INGRESS_BASE_URL}"
    log_info "Using explicit Ingress base URL: ${TARGET_SERVICE_URL}"
elif [[ "$TLS_ENABLED" == "true" && -n "$INGRESS_HOSTNAME" ]]; then
    TARGET_SERVICE_URL="https://${INGRESS_HOSTNAME}"
    log_info "TLS detected, using HTTPS: ${TARGET_SERVICE_URL}"
elif [[ -n "$INGRESS_URL" ]]; then
    TARGET_SERVICE_URL="${INGRESS_URL}"
    log_info "Auto-detected service URL: ${TARGET_SERVICE_URL}"
else
    log_warning "Could not detect Ingress URL. Skipping service_base_url configuration."
    log_warning "Run ./08-configure-service-url.sh manually after verifying the Ingress."
    TARGET_SERVICE_URL=""
fi

if [[ -n "$TARGET_SERVICE_URL" ]]; then
    # Start port-forward using the shared helper (auto-detects Envoy)
    start_osmo_port_forward "${OSMO_NAMESPACE}" 8080
    _PF_PID=$PORT_FORWARD_PID
    export _OSMO_PORT=8080

    _cleanup_pf() {
        if [[ -n "${_PF_PID:-}" ]]; then
            kill $_PF_PID 2>/dev/null || true
            wait $_PF_PID 2>/dev/null || true
        fi
    }

    # Wait for port-forward to be ready
    _pf_ready=false
    for i in $(seq 1 30); do
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/version" 2>/dev/null | grep -q "200\|401\|403"; then
            _pf_ready=true
            break
        fi
        sleep 1
    done

    if [[ "$_pf_ready" == "true" ]]; then
        # Login (no-op when bypassing Envoy -- osmo_curl handles auth headers)
        osmo_login 8080 || true

        # Check current value
        CURRENT_SVC_URL=$(osmo_curl GET "http://localhost:8080/api/configs/service" 2>/dev/null | jq -r '.service_base_url // ""')

        if [[ "$CURRENT_SVC_URL" == "$TARGET_SERVICE_URL" ]]; then
            log_success "service_base_url already configured: ${CURRENT_SVC_URL}"
        else
            if [[ -n "$CURRENT_SVC_URL" && "$CURRENT_SVC_URL" != "null" ]]; then
                log_warning "Updating service_base_url from '${CURRENT_SVC_URL}' to '${TARGET_SERVICE_URL}'"
            fi

            # Write config using the PATCH API helper
            cat > /tmp/service_url_fix.json << SVCEOF
{
  "service_base_url": "${TARGET_SERVICE_URL}"
}
SVCEOF
            if osmo_config_update SERVICE /tmp/service_url_fix.json "Set service_base_url for osmo-ctrl sidecar"; then
                # Verify
                NEW_SVC_URL=$(osmo_curl GET "http://localhost:8080/api/configs/service" 2>/dev/null | jq -r '.service_base_url // ""')
                if [[ "$NEW_SVC_URL" == "$TARGET_SERVICE_URL" ]]; then
                    log_success "service_base_url configured: ${NEW_SVC_URL}"
                else
                    log_warning "service_base_url verification failed. Run ./08-configure-service-url.sh manually."
                fi
            else
                log_warning "Failed to set service_base_url. Run ./08-configure-service-url.sh manually."
            fi
            rm -f /tmp/service_url_fix.json
        fi
    else
        log_warning "Port-forward not ready. Run ./08-configure-service-url.sh manually."
    fi

    _cleanup_pf
fi

echo ""
echo "========================================"
log_success "OSMO Control Plane deployment complete!"
echo "========================================"
echo ""

if [[ "$AUTH_ENABLED" == "true" ]]; then
    # --- Auth-enabled output ---
    echo "Authentication: ENABLED (Keycloak + Envoy sidecars)"
    echo ""
    echo "Keycloak Admin Console:"
    echo "  URL: https://${AUTH_DOMAIN}/admin"
    echo "  Admin: admin / ${KEYCLOAK_ADMIN_PASSWORD}"
    echo ""
    echo "OSMO Access:"
    if [[ -n "$INGRESS_URL" ]]; then
        echo "  OSMO API:    ${INGRESS_URL}/api/version   (unauthenticated -- skipAuthPath)"
        echo "  OSMO Web UI: ${INGRESS_URL}               (redirects to Keycloak login)"
    fi
    echo ""
    echo "Login methods:"
    echo "  Browser: Visit ${INGRESS_URL:-https://<domain>} -- you will be redirected to Keycloak"
    echo "  CLI:     osmo login ${INGRESS_URL:-https://<domain>}"
    echo "           (Opens browser for device authorization flow)"
    echo ""
    echo "Test user: osmo-admin / osmo-admin"
    echo ""
    echo "Keycloak realm management (groups, roles, users):"
    echo "  https://nvidia.github.io/OSMO/main/deployment_guide/appendix/authentication/keycloak_setup.html"
    echo ""
else
    # --- No-auth output ---
    if [[ "$TLS_ENABLED" == "true" && -n "$INGRESS_HOSTNAME" ]]; then
        echo "OSMO Access (HTTPS via NGINX Ingress + cert-manager):"
        echo "  OSMO API: https://${INGRESS_HOSTNAME}/api/version"
        echo "  OSMO UI:  https://${INGRESS_HOSTNAME}"
        echo "  OSMO CLI: osmo login https://${INGRESS_HOSTNAME} --method dev --username admin"
        echo ""
    elif [[ -n "$INGRESS_URL" ]]; then
        echo "OSMO Access (via NGINX Ingress LoadBalancer):"
        echo "  OSMO API: ${INGRESS_URL}/api/version"
        echo "  OSMO UI:  ${INGRESS_URL}"
        echo "  OSMO CLI: osmo login ${INGRESS_URL} --method dev --username admin"
        echo ""
    else
        log_warning "Could not detect Ingress LoadBalancer IP."
        echo "  Check: kubectl get svc -n ${INGRESS_NAMESPACE:-ingress-nginx}"
        echo ""
        echo "  Fallback (port-forward):"
        echo "    kubectl port-forward -n ${OSMO_NAMESPACE} svc/osmo-service 8080:80"
        echo "    URL: http://localhost:8080"
        echo ""
    fi

    echo "NOTE: OSMO API authentication is DISABLED."
    echo "      The API is accessible without tokens."
    echo "      Set DEPLOY_KEYCLOAK=true with TLS to enable Keycloak + Envoy auth."
    echo ""
    echo "Test the API:"
    if [[ -n "$INGRESS_URL" ]]; then
        echo "  curl ${INGRESS_URL}/api/version"
        echo "  curl ${INGRESS_URL}/api/workflow"
    else
        echo "  curl http://localhost:8080/api/version"
        echo "  curl http://localhost:8080/api/workflow"
    fi
    echo ""
    if [[ "${DEPLOY_KEYCLOAK:-false}" == "true" ]]; then
        echo "Keycloak Access (internal only, auth not enforced):"
        echo "  kubectl port-forward -n ${KEYCLOAK_NAMESPACE} svc/keycloak 8081:80"
        echo "  URL: http://localhost:8081"
        echo "  Admin: admin / ${KEYCLOAK_ADMIN_PASSWORD}"
        echo "  Test User: osmo-admin / osmo-admin"
        echo ""
    fi
fi

echo "Ingress resources:"
kubectl get ingress -n "${OSMO_NAMESPACE}" 2>/dev/null || true
echo ""
echo "Next step - Deploy Backend Operator:"
echo "  ./06-deploy-osmo-backend.sh"
echo ""
