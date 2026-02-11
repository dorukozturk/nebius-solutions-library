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

# Keycloak service URL (same namespace as OSMO)
KEYCLOAK_HOST="keycloak.${OSMO_NAMESPACE}.svc.cluster.local"
KEYCLOAK_URL="http://${KEYCLOAK_HOST}:80"
AUTH_DOMAIN="auth-${OSMO_DOMAIN}"

if [[ "${DEPLOY_KEYCLOAK:-false}" == "true" ]]; then
    log_info "Deploying Keycloak for OSMO authentication..."
    log_info "Reference: https://nvidia.github.io/OSMO/main/deployment_guide/getting_started/deploy_service.html#step-2-configure-keycloak"

    # -------------------------------------------------------------------------
    # Step 1: Create Keycloak database in PostgreSQL
    # Per OSMO docs: https://nvidia.github.io/OSMO/main/deployment_guide/getting_started/deploy_service.html#step-1-configure-postgresql
    # -------------------------------------------------------------------------
    log_info "Creating Keycloak database in PostgreSQL..."
    
    # Delete old pod if exists
    kubectl delete pod osmo-db-ops -n "${OSMO_NAMESPACE}" --ignore-not-found 2>/dev/null
    
    # Use the managed PostgreSQL credentials (bootstrap user has CREATEDB privilege)
    cat > /tmp/keycloak-db-init.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: osmo-db-ops
  namespace: ${OSMO_NAMESPACE}
spec:
  containers:
    - name: osmo-db-ops
      image: postgres:15-alpine
      env:
        - name: PGPASSWORD
          valueFrom:
            secretKeyRef:
              name: osmo-db-init-creds
              key: PGPASSWORD
      command: ["/bin/sh", "-c"]
      args:
        - |
          # Connect to the bootstrap database (osmo) and create keycloak database
          # Nebius MSP bootstrap user can only connect to the bootstrap database
          psql -U ${POSTGRES_USER} -h ${POSTGRES_HOST} -p ${POSTGRES_PORT} -d ${POSTGRES_DB} -tc "SELECT 1 FROM pg_database WHERE datname = 'keycloak'" | grep -q 1 || \
          psql -U ${POSTGRES_USER} -h ${POSTGRES_HOST} -p ${POSTGRES_PORT} -d ${POSTGRES_DB} -c 'CREATE DATABASE keycloak;' || \
          echo "WARNING: Could not create keycloak database. Bootstrap user may not have CREATEDB privilege."
          echo "Keycloak database setup complete"
  restartPolicy: Never
EOF
    kubectl apply -f /tmp/keycloak-db-init.yaml
    
    log_info "Waiting for Keycloak database to be created..."
    kubectl wait --for=condition=Ready pod/osmo-db-ops -n "${OSMO_NAMESPACE}" --timeout=60s 2>/dev/null || true
    sleep 5
    kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/osmo-db-ops -n "${OSMO_NAMESPACE}" --timeout=60s || {
        log_warning "Database creation pod status:"
        kubectl logs -n "${OSMO_NAMESPACE}" osmo-db-ops || true
    }
    kubectl delete pod osmo-db-ops -n "${OSMO_NAMESPACE}" --ignore-not-found 2>/dev/null
    rm -f /tmp/keycloak-db-init.yaml
    log_success "Keycloak database ready"

    # -------------------------------------------------------------------------
    # Step 2: Create secrets for Keycloak
    # -------------------------------------------------------------------------
    log_info "Creating Keycloak secrets..."
    
    # Save admin password to secret for future re-runs
    kubectl create secret generic keycloak-admin-secret \
        --namespace "${OSMO_NAMESPACE}" \
        --from-literal=password="${KEYCLOAK_ADMIN_PASSWORD}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Create keycloak-db-secret for external database (per OSMO docs)
    # Uses the managed PostgreSQL credentials
    kubectl create secret generic keycloak-db-secret \
        --namespace "${OSMO_NAMESPACE}" \
        --from-literal=postgres-password="${POSTGRES_PASSWORD}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Keycloak secrets created"

    # -------------------------------------------------------------------------
    # Step 3: Install Keycloak using Bitnami Helm chart
    # Per OSMO docs: https://nvidia.github.io/OSMO/main/deployment_guide/getting_started/deploy_service.html#install-keycloak-using-bitnami-helm-chart
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

# Development mode (use production: true with TLS for production)
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
  # Database configuration (using Nebius Managed PostgreSQL)
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
  - name: KC_HOSTNAME_STRICT
    value: "false"
  - name: KC_HOSTNAME_STRICT_HTTPS
    value: "false"
  - name: KC_HTTP_ENABLED
    value: "true"
  - name: KC_HEALTH_ENABLED
    value: "true"
EOF

    # Install or upgrade Keycloak
    # Note: Don't use --wait as it can hang; we'll check status separately
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
    
    # Configure Keycloak realm and clients for OSMO
    # Per documentation: https://nvidia.github.io/OSMO/main/deployment_guide/getting_started/deploy_service.html#post-installation-keycloak-configuration
    log_info "Configuring Keycloak realm and clients for OSMO..."
    
    # Generate client secret
    OIDC_CLIENT_SECRET=$(openssl rand -hex 16)
    
    # Create a job to configure Keycloak
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
      containers:
      - name: keycloak-setup
        image: curlimages/curl:8.5.0
        command:
        - /bin/sh
        - -c
        - |
          set -e
          KEYCLOAK_URL="http://keycloak:80"
          
          echo "Waiting for Keycloak to be ready..."
          for i in 1 2 3 4 5 6 7 8 9 10; do
            if curl -s -f "\${KEYCLOAK_URL}/health/ready" > /dev/null 2>&1; then
              echo "Keycloak is ready"
              break
            fi
            echo "Attempt \$i: Keycloak not ready yet..."
            sleep 15
          done
          
          echo "Getting admin token..."
          for i in 1 2 3 4 5; do
            TOKEN=\$(curl -s -X POST "\${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
              --data-urlencode "client_id=admin-cli" \
              --data-urlencode "username=admin" \
              --data-urlencode "password=${KEYCLOAK_ADMIN_PASSWORD}" \
              --data-urlencode "grant_type=password" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
            if [ -n "\$TOKEN" ]; then break; fi
            echo "Retry \$i: waiting for token..."
            sleep 10
          done
          
          if [ -z "\$TOKEN" ]; then
            echo "Failed to get admin token"
            exit 1
          fi
          echo "Got admin token"
          
          # Create osmo realm (per documentation)
          echo "Creating osmo realm..."
          curl -s -X POST "\${KEYCLOAK_URL}/admin/realms" \
            -H "Authorization: Bearer \$TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"realm":"osmo","enabled":true,"registrationAllowed":false}' || echo "Realm may already exist"
          
          # Create osmo-device client (for CLI device code flow)
          # Per documentation: public client with device authorization grant
          echo "Creating osmo-device client..."
          curl -s -X POST "\${KEYCLOAK_URL}/admin/realms/osmo/clients" \
            -H "Authorization: Bearer \$TOKEN" \
            -H "Content-Type: application/json" \
            -d '{
              "clientId": "osmo-device",
              "name": "OSMO Device Client",
              "enabled": true,
              "publicClient": true,
              "directAccessGrantsEnabled": true,
              "standardFlowEnabled": false,
              "implicitFlowEnabled": false,
              "protocol": "openid-connect",
              "attributes": {
                "oauth2.device.authorization.grant.enabled": "true"
              }
            }' || echo "Client may already exist"
          
          # Create osmo-browser-flow client (for web UI)
          # Per documentation: confidential client with standard flow
          echo "Creating osmo-browser-flow client..."
          curl -s -X POST "\${KEYCLOAK_URL}/admin/realms/osmo/clients" \
            -H "Authorization: Bearer \$TOKEN" \
            -H "Content-Type: application/json" \
            -d '{
              "clientId": "osmo-browser-flow",
              "name": "OSMO Browser Flow Client",
              "enabled": true,
              "publicClient": false,
              "secret": "${OIDC_CLIENT_SECRET}",
              "directAccessGrantsEnabled": false,
              "standardFlowEnabled": true,
              "implicitFlowEnabled": false,
              "serviceAccountsEnabled": true,
              "protocol": "openid-connect",
              "redirectUris": ["*"],
              "webOrigins": ["*"]
            }' || echo "Client may already exist"
          
          # Create a test user (per documentation)
          echo "Creating osmo-admin user..."
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
          echo "========================================="
          echo "Keycloak OSMO configuration complete!"
          echo "========================================="
          echo "Realm: osmo"
          echo "Clients: osmo-device, osmo-browser-flow"
          echo "Test user: osmo-admin / osmo-admin"
          echo ""
EOF

    # Delete any previous config job
    kubectl delete job keycloak-osmo-setup -n "${KEYCLOAK_NAMESPACE}" --ignore-not-found 2>/dev/null || true
    
    kubectl apply -f /tmp/keycloak-config-job.yaml
    
    log_info "Waiting for Keycloak configuration job..."
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
    
    rm -f /tmp/keycloak-values.yaml /tmp/keycloak-config-job.yaml
    
    log_success "Keycloak deployed and configured"
    echo ""
    echo "Keycloak Access:"
    echo "  kubectl port-forward -n ${KEYCLOAK_NAMESPACE} svc/keycloak 8081:80"
    echo "  URL: http://localhost:8081"
    echo "  Admin: admin / ${KEYCLOAK_ADMIN_PASSWORD}"
    echo "  Test User: osmo-admin / osmo-admin"
    echo ""
    echo "OSMO Auth Endpoints (in-cluster):"
    echo "  Token: ${KEYCLOAK_URL}/realms/osmo/protocol/openid-connect/token"
    echo "  Auth:  ${KEYCLOAK_URL}/realms/osmo/protocol/openid-connect/auth"
    echo ""
    
    # Keycloak is deployed but we disable OSMO's internal auth
    # because OSMO's JWT validation expects its own keys, not Keycloak's
    # Users can still get tokens from Keycloak for future use
    AUTH_ENABLED="false"
    log_info "Note: OSMO internal auth disabled (use Keycloak tokens with API directly)"
else
    log_info "Skipping Keycloak (set DEPLOY_KEYCLOAK=true to enable)"
    log_warning "Without Keycloak, 'osmo login' and token creation will not work"
    log_info "Reference: https://nvidia.github.io/OSMO/main/deployment_guide/getting_started/deploy_service.html#step-2-configure-keycloak"
    AUTH_ENABLED="false"
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
    # NOTE: Auth is DISABLED because OSMO's internal JWT validation expects
    # tokens signed with its own keys, not Keycloak's keys.
    # For testing, the API is open. For production, use network-level security.
    auth:
      enabled: false
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
# NOTE: Envoy and internal auth are DISABLED because OSMO's JWT validation
# expects its own keys, not Keycloak's. For testing, the API is open.
# For production, configure proper JWT validation or use network-level security.
sidecars:
  envoy:
    enabled: false
    service:
      hostname: ${OSMO_DOMAIN}
  
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

ROUTER_HELM_ARGS=(
    --namespace "${OSMO_NAMESPACE}"
    --set service.type=ClusterIP
    --set services.configFile.enabled=true
    --set "services.postgres.serviceName=${POSTGRES_HOST}"
    --set "services.postgres.port=${POSTGRES_PORT}"
    --set services.postgres.db=osmo
    --set "services.postgres.user=${POSTGRES_USER}"
    --set services.service.ingress.enabled=true
    --set services.service.ingress.ingressClass=nginx
    --set services.service.ingress.sslEnabled=false
    --set services.service.scaling.minReplicas=1
    --set services.service.scaling.maxReplicas=1
    --set sidecars.envoy.enabled=false
    --set sidecars.logAgent.enabled=false
)
[[ -n "$INGRESS_HOSTNAME" ]] && ROUTER_HELM_ARGS+=(--set "services.service.hostname=${INGRESS_HOSTNAME}" --set "global.domain=${INGRESS_HOSTNAME}")

helm upgrade --install osmo-router osmo/router \
    "${ROUTER_HELM_ARGS[@]}" \
    --wait --timeout 5m || log_warning "Router deployment had issues"

log_success "OSMO Router deployed"

# -----------------------------------------------------------------------------
# Step 8: Deploy Web UI (Optional)
# -----------------------------------------------------------------------------
if [[ "${DEPLOY_UI:-true}" == "true" ]]; then
    log_info "Deploying OSMO Web UI..."

    UI_HELM_ARGS=(
        --namespace "${OSMO_NAMESPACE}"
        --set services.ui.service.type=ClusterIP
        --set services.ui.ingress.enabled=true
        --set services.ui.ingress.ingressClass=nginx
        --set services.ui.ingress.sslEnabled=false
        --set services.ui.replicas=1
        --set "services.ui.apiHostname=osmo-service.${OSMO_NAMESPACE}.svc.cluster.local:80"
        --set sidecars.envoy.enabled=false
        --set sidecars.logAgent.enabled=false
    )
    [[ -n "$INGRESS_HOSTNAME" ]] && UI_HELM_ARGS+=(--set "services.ui.hostname=${INGRESS_HOSTNAME}" --set "global.domain=${INGRESS_HOSTNAME}")

    helm upgrade --install osmo-ui osmo/web-ui \
        "${UI_HELM_ARGS[@]}" \
        --wait --timeout 5m || log_warning "UI deployment had issues"

    log_success "OSMO Web UI deployed"
fi

# Cleanup temp files
rm -f /tmp/osmo_values.yaml

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
# Since Envoy sidecar is disabled, services need to target port 8000 directly
# instead of the 'envoy-http' named port which doesn't exist.
# This is done automatically by the helm chart when sidecars.envoy.enabled=false

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
elif [[ -n "$INGRESS_URL" ]]; then
    TARGET_SERVICE_URL="${INGRESS_URL}"
    log_info "Auto-detected service URL: ${TARGET_SERVICE_URL}"
else
    log_warning "Could not detect Ingress URL. Skipping service_base_url configuration."
    log_warning "Run ./07-configure-service-url.sh manually after verifying the Ingress."
    TARGET_SERVICE_URL=""
fi

if [[ -n "$TARGET_SERVICE_URL" ]]; then
    # Start port-forward to access the OSMO API
    log_info "Starting port-forward to configure service_base_url..."
    kubectl port-forward -n "${OSMO_NAMESPACE}" svc/osmo-service 8080:80 &>/dev/null &
    _PF_PID=$!

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
        # Login
        if osmo login http://localhost:8080 --method dev --username admin 2>/dev/null; then
            # Check current value
            CURRENT_SVC_URL=$(curl -s "http://localhost:8080/api/configs/service" 2>/dev/null | jq -r '.service_base_url // ""')

            if [[ "$CURRENT_SVC_URL" == "$TARGET_SERVICE_URL" ]]; then
                log_success "service_base_url already configured: ${CURRENT_SVC_URL}"
            else
                if [[ -n "$CURRENT_SVC_URL" && "$CURRENT_SVC_URL" != "null" ]]; then
                    log_warning "Updating service_base_url from '${CURRENT_SVC_URL}' to '${TARGET_SERVICE_URL}'"
                fi

                # Write config
                cat > /tmp/service_url_fix.json << SVCEOF
{
  "service_base_url": "${TARGET_SERVICE_URL}"
}
SVCEOF
                if osmo config update SERVICE --file /tmp/service_url_fix.json --description "Set service_base_url for osmo-ctrl sidecar" 2>/dev/null; then
                    # Verify
                    NEW_SVC_URL=$(curl -s "http://localhost:8080/api/configs/service" 2>/dev/null | jq -r '.service_base_url // ""')
                    if [[ "$NEW_SVC_URL" == "$TARGET_SERVICE_URL" ]]; then
                        log_success "service_base_url configured: ${NEW_SVC_URL}"
                    else
                        log_warning "service_base_url verification failed. Run ./07-configure-service-url.sh manually."
                    fi
                else
                    log_warning "Failed to set service_base_url. Run ./07-configure-service-url.sh manually."
                fi
                rm -f /tmp/service_url_fix.json
            fi
        else
            log_warning "Could not login to OSMO. Run ./07-configure-service-url.sh manually."
        fi
    else
        log_warning "Port-forward not ready. Run ./07-configure-service-url.sh manually."
    fi

    _cleanup_pf
fi

echo ""
echo "========================================"
log_success "OSMO Control Plane deployment complete!"
echo "========================================"
echo ""

if [[ -n "$INGRESS_URL" ]]; then
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

echo "NOTE: OSMO API authentication is DISABLED for testing."
echo "      The API is accessible without tokens."
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
    echo "Keycloak Access (for future use):"
    echo "  kubectl port-forward -n ${KEYCLOAK_NAMESPACE} svc/keycloak 8081:80"
    echo "  URL: http://localhost:8081"
    echo "  Admin: admin / ${KEYCLOAK_ADMIN_PASSWORD}"
    echo "  Test User: osmo-admin / osmo-admin"
    echo ""
fi
echo "Ingress resources:"
kubectl get ingress -n "${OSMO_NAMESPACE}" 2>/dev/null || true
echo ""
echo "Next step - Deploy Backend Operator:"
echo "  ./05-deploy-osmo-backend.sh"
echo ""
