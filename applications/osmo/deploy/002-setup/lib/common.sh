#!/bin/bash
#
# Common functions for setup scripts
#

# Colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Pause on error so the user can read the output before the terminal closes
trap '_exit_code=$?; if [[ $_exit_code -ne 0 ]]; then echo ""; log_error "Script failed (exit code $_exit_code). Press Enter to close..."; read -r; fi' EXIT

# Read input with a prompt into a variable (bash/zsh compatible).
read_prompt_var() {
    local prompt=$1
    local var_name=$2
    local default=$3
    local value=""
    local read_from="/dev/tty"
    local write_to="/dev/tty"

    if [[ ! -r "/dev/tty" || ! -w "/dev/tty" ]]; then
        read_from="/dev/stdin"
        write_to="/dev/stdout"
    fi

    if [[ -n "$default" ]]; then
        printf "%s [%s]: " "$prompt" "$default" >"$write_to"
    else
        printf "%s: " "$prompt" >"$write_to"
    fi

    IFS= read -r value <"$read_from"
    if [[ -z "$value" && -n "$default" ]]; then
        value="$default"
    fi

    eval "$var_name='$value'"
}

# Read a secret value into a variable (no echo).
read_secret_var() {
    local prompt=$1
    local var_name=$2
    local value=""
    local read_from="/dev/tty"
    local write_to="/dev/tty"

    if [[ ! -r "/dev/tty" || ! -w "/dev/tty" ]]; then
        read_from="/dev/stdin"
        write_to="/dev/stdout"
    fi

    printf "%s: " "$prompt" >"$write_to"
    stty -echo <"$read_from"
    IFS= read -r value <"$read_from"
    stty echo <"$read_from"
    printf "\n" >"$write_to"

    eval "$var_name='$value'"
}

# Check if command exists
check_command() {
    command -v "$1" &>/dev/null
}

# Retry with exponential backoff
retry_with_backoff() {
    local max_attempts=${1:-5}
    local delay=${2:-2}
    local max_delay=${3:-60}
    shift 3
    local cmd=("$@")
    
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        log_info "Attempt $attempt/$max_attempts: ${cmd[*]}"
        if "${cmd[@]}"; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log_warning "Failed, retrying in ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2))
            if [[ $delay -gt $max_delay ]]; then
                delay=$max_delay
            fi
        fi
        ((attempt++))
    done
    
    log_error "All $max_attempts attempts failed"
    return 1
}

# Wait for a condition with timeout
wait_for_condition() {
    local description=$1
    local timeout=${2:-300}
    local interval=${3:-10}
    shift 3
    local cmd=("$@")
    
    log_info "Waiting for $description (timeout: ${timeout}s)..."
    
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if "${cmd[@]}" &>/dev/null; then
            log_success "$description"
            return 0
        fi
        sleep "$interval"
        ((elapsed += interval))
        echo -n "."
    done
    
    echo ""
    log_error "Timeout waiting for $description"
    return 1
}

# Check kubectl connection
check_kubectl() {
    if ! check_command kubectl; then
        log_error "kubectl not found"
        return 1
    fi
    
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        return 1
    fi
    
    log_success "kubectl connected to cluster"
    return 0
}

# Check Helm
check_helm() {
    if ! check_command helm; then
        log_error "helm not found"
        return 1
    fi
    
    log_success "helm available"
    return 0
}

# Install Helm chart with retry
helm_install() {
    local name=$1
    local chart=$2
    local namespace=$3
    shift 3
    local extra_args=("$@")
    
    log_info "Installing Helm chart: $name"
    
    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
    
    retry_with_backoff 3 5 30 helm upgrade --install "$name" "$chart" \
        --namespace "$namespace" \
        --wait --timeout 10m \
        "${extra_args[@]}"
}

# Wait for pods to be ready
wait_for_pods() {
    local namespace=$1
    local label_selector=$2
    local timeout=${3:-300}
    
    wait_for_condition "pods with label $label_selector in $namespace" \
        "$timeout" 10 \
        kubectl wait --for=condition=Ready pods \
            -n "$namespace" \
            -l "$label_selector" \
            --timeout=10s
}

# Detect OSMO service URL from the NGINX Ingress Controller's LoadBalancer.
#
# Lookup order:
#   1. LoadBalancer external IP   (cloud assigns a public/internal IP)
#   2. LoadBalancer hostname       (some clouds return a DNS name instead)
#   3. Controller ClusterIP        (fallback – works from inside the cluster)
#
# Usage:
#   url=$(detect_service_url)
#   [[ -n "$url" ]] && echo "OSMO reachable at $url"
detect_service_url() {
    local ns="${INGRESS_NAMESPACE:-ingress-nginx}"
    local url=""

    # Find the controller service (works for the community ingress-nginx chart)
    local lb_ip lb_host cluster_ip svc_name
    svc_name=$(kubectl get svc -n "$ns" \
        -l app.kubernetes.io/name=ingress-nginx,app.kubernetes.io/component=controller \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    if [[ -n "$svc_name" ]]; then
        # 1. LoadBalancer IP
        lb_ip=$(kubectl get svc "$svc_name" -n "$ns" \
            -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
        if [[ -n "$lb_ip" ]]; then
            echo "http://${lb_ip}"
            return 0
        fi

        # 2. LoadBalancer hostname (e.g. ELB on AWS)
        lb_host=$(kubectl get svc "$svc_name" -n "$ns" \
            -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
        if [[ -n "$lb_host" ]]; then
            echo "http://${lb_host}"
            return 0
        fi

        # 3. ClusterIP of the controller
        cluster_ip=$(kubectl get svc "$svc_name" -n "$ns" \
            -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
        if [[ -n "$cluster_ip" && "$cluster_ip" != "None" ]]; then
            echo "http://${cluster_ip}"
            return 0
        fi
    fi

    # Nothing found
    return 1
}

# Get Terraform output (supports nested values like "postgresql.host")
get_tf_output() {
    local name=$1
    local tf_dir=${2:-../001-iac}
    
    # Check if name contains a dot (nested value)
    if [[ "$name" == *.* ]]; then
        local base_name="${name%%.*}"
        local key="${name#*.}"
        terraform -chdir="$tf_dir" output -json "$base_name" 2>/dev/null | jq -r ".$key // empty"
    else
        terraform -chdir="$tf_dir" output -json "$name" 2>/dev/null | jq -r '. // empty'
    fi
}

# Get Nebius CLI path
get_nebius_path() {
    if command -v nebius &>/dev/null; then
        command -v nebius
    elif [[ -x "$HOME/.nebius/bin/nebius" ]]; then
        echo "$HOME/.nebius/bin/nebius"
    fi
}

# Read secret from Nebius MysteryBox
# Usage: get_mysterybox_secret <secret_id> <key>
# Returns the secret value or empty string if not found
get_mysterybox_secret() {
    local secret_id=$1
    local key=$2
    local nebius_path=$(get_nebius_path)
    
    if [[ -z "$nebius_path" ]]; then
        log_warning "Nebius CLI not found, cannot read from MysteryBox"
        return 1
    fi
    
    if [[ -z "$secret_id" ]]; then
        return 1
    fi
    
    local result=$("$nebius_path" mysterybox v1 payload get-by-key \
        --secret-id "$secret_id" \
        --key "$key" \
        --format json 2>/dev/null)
    
    if [[ -n "$result" ]]; then
        echo "$result" | jq -r '.data.string_value // empty' 2>/dev/null
    fi
}
