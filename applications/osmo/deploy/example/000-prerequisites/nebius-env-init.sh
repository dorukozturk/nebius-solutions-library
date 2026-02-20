#!/bin/bash
#
# Nebius Environment Initialization Script
#
# This script sets up environment variables needed for Terraform deployment.
# Run with: source ./nebius-env-init.sh
#
# Configure your deployment by setting the values below.
#
# NOTE: Do NOT use 'set -e' as this script is meant to be sourced
#

# ========================================
# CONFIGURATION - Set your values here
# ========================================
NEBIUS_TENANT_ID="${NEBIUS_TENANT_ID:-}"        # e.g. tenant-abc123def456
NEBIUS_PROJECT_ID="${NEBIUS_PROJECT_ID:-}"      # e.g. project-abc123def456
NEBIUS_REGION="${NEBIUS_REGION:-eu-north1}"     # eu-north1, eu-north2, eu-west1, me-west1, uk-south1, us-central1
# ========================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "========================================"
echo "  Nebius Environment Initialization"
echo "========================================"
echo ""

# Detect WSL
is_wsl() {
    grep -qi microsoft /proc/version 2>/dev/null
}

# Get Nebius CLI path
get_nebius_path() {
    if command -v nebius &>/dev/null; then
        command -v nebius
    elif [[ -x "$HOME/.nebius/bin/nebius" ]]; then
        echo "$HOME/.nebius/bin/nebius"
    fi
}

# Check if Nebius CLI is installed
check_nebius_cli() {
    local nebius_path=$(get_nebius_path)
    if [[ -z "$nebius_path" ]]; then
        echo -e "${RED}[ERROR]${NC} Nebius CLI is not installed."
        echo ""
        echo "Install it by running: ./install-tools.sh"
        echo "Or manually: curl -sSL https://storage.eu-north1.nebius.cloud/nebius/install.sh | bash"
        return 1
    fi

    # Add to PATH if needed
    if ! command -v nebius &>/dev/null && [[ -x "$HOME/.nebius/bin/nebius" ]]; then
        export PATH="$HOME/.nebius/bin:$PATH"
        echo -e "${YELLOW}[INFO]${NC} Added ~/.nebius/bin to PATH"
    fi

    return 0
}

# Check if Nebius CLI is authenticated
check_nebius_auth() {
    local nebius_path=$(get_nebius_path)
    if [[ -z "$nebius_path" ]]; then
        return 1
    fi

    # Clear potentially corrupted token
    if [[ -n "$NEBIUS_IAM_TOKEN" ]]; then
        echo -e "${YELLOW}[INFO]${NC} Clearing NEBIUS_IAM_TOKEN environment variable"
        unset NEBIUS_IAM_TOKEN
    fi

    # Test authentication by listing profiles
    if "$nebius_path" profile list &>/dev/null; then
        return 0
    fi
    return 1
}

# Main initialization
main() {
    # Step 1: Check Nebius CLI
    echo -e "${BLUE}Step 1: Checking Nebius CLI${NC}"
    if ! check_nebius_cli; then
        return 1
    fi
    echo -e "${GREEN}[✓]${NC} Nebius CLI found"
    echo ""

    # Step 2: Check authentication
    echo -e "${BLUE}Step 2: Checking authentication${NC}"
    if ! check_nebius_auth; then
        echo -e "${YELLOW}[!]${NC} Nebius CLI not authenticated"
        echo ""
        echo "Please authenticate with Nebius CLI before running this script."
        echo ""
        echo "Authentication steps:"
        echo "  1. Run: nebius profile create"
        echo "  2. Follow the interactive prompts"
        echo "  3. Complete browser-based authentication"
        if is_wsl; then
            echo ""
            echo -e "${YELLOW}WSL Note:${NC} If browser doesn't open automatically,"
            echo "  copy the URL from the terminal and paste it in your browser."
        fi
        echo ""
        echo "After authentication, run this script again:"
        echo "  source ./nebius-env-init.sh"
        return 1
    fi
    echo -e "${GREEN}[✓]${NC} Nebius CLI authenticated"
    echo ""

    # Step 3: Validate configuration
    echo -e "${BLUE}Step 3: Validating configuration${NC}"

    if [[ -z "$NEBIUS_TENANT_ID" ]]; then
        echo -e "${RED}[ERROR]${NC} NEBIUS_TENANT_ID is not set."
        echo "  Edit the CONFIGURATION section at the top of this script."
        return 1
    fi

    if [[ ! "$NEBIUS_TENANT_ID" =~ ^tenant-[a-z0-9]+ ]]; then
        echo -e "${RED}[ERROR]${NC} Invalid tenant ID format: '$NEBIUS_TENANT_ID'"
        echo "  Tenant IDs should look like: tenant-e00abc123def456"
        return 1
    fi

    if [[ -z "$NEBIUS_PROJECT_ID" ]]; then
        echo -e "${RED}[ERROR]${NC} NEBIUS_PROJECT_ID is not set."
        echo "  Edit the CONFIGURATION section at the top of this script."
        return 1
    fi

    if [[ ! "$NEBIUS_PROJECT_ID" =~ ^project-[a-z0-9]+ ]]; then
        echo -e "${RED}[ERROR]${NC} Invalid project ID format: '$NEBIUS_PROJECT_ID'"
        echo "  Project IDs should look like: project-e00abc123def456"
        return 1
    fi

    if [[ -z "$NEBIUS_REGION" ]]; then
        echo -e "${RED}[ERROR]${NC} NEBIUS_REGION is not set."
        echo "  Edit the CONFIGURATION section at the top of this script."
        return 1
    fi

    echo -e "${GREEN}[✓]${NC} Configuration valid"
    echo ""

    # Step 4: Export environment variables
    echo -e "${BLUE}Step 4: Setting environment variables${NC}"

    local nebius_path=$(get_nebius_path)

    export NEBIUS_TENANT_ID
    export NEBIUS_PROJECT_ID
    export NEBIUS_REGION

    # Get IAM token for Terraform provider authentication
    echo "Getting IAM token for Terraform..."
    unset NEBIUS_IAM_TOKEN  # Clear any old/corrupted token
    export NEBIUS_IAM_TOKEN=$("$nebius_path" iam get-access-token)

    if [[ -z "$NEBIUS_IAM_TOKEN" ]]; then
        echo -e "${RED}[ERROR]${NC} Failed to get IAM token"
        return 1
    fi
    echo -e "${GREEN}[✓]${NC} IAM token obtained"

    # Terraform variables
    export TF_VAR_tenant_id="$NEBIUS_TENANT_ID"
    export TF_VAR_parent_id="$NEBIUS_PROJECT_ID"
    export TF_VAR_region="$NEBIUS_REGION"

    echo ""
    echo -e "${GREEN}[✓]${NC} Environment variables set:"
    echo "    NEBIUS_TENANT_ID   = $NEBIUS_TENANT_ID"
    echo "    NEBIUS_PROJECT_ID  = $NEBIUS_PROJECT_ID"
    echo "    NEBIUS_REGION      = $NEBIUS_REGION"
    echo "    NEBIUS_IAM_TOKEN   = ${NEBIUS_IAM_TOKEN:0:20}... (truncated)"
    echo "    TF_VAR_tenant_id   = $TF_VAR_tenant_id"
    echo "    TF_VAR_parent_id   = $TF_VAR_parent_id"
    echo "    TF_VAR_region      = $TF_VAR_region"

    # Step 5: Verify connectivity
    echo ""
    echo -e "${BLUE}Step 5: Verifying connectivity${NC}"

    if "$nebius_path" iam project get --id "$NEBIUS_PROJECT_ID" &>/dev/null; then
        echo -e "${GREEN}[✓]${NC} Successfully connected to Nebius project"
    else
        echo -e "${YELLOW}[!]${NC} Could not verify project access (this may be normal for new projects)"
    fi

    echo ""
    echo "========================================"
    echo -e "${GREEN}Environment initialization complete!${NC}"
    echo "========================================"
    echo ""
    echo "Next steps:"
    echo "  1. source ./secrets-init.sh           # Initialize MysteryBox secrets (recommended)"
    echo "  2. cd ../001-iac"
    echo "  3. cp terraform.tfvars.cost-optimized-secure.example terraform.tfvars"
    echo "  4. terraform init && terraform apply"
    echo ""

    return 0
}

# Run main function
main