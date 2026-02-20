#!/bin/bash
#
# Nebius Environment Initialization Script
# 
# This script sets up environment variables needed for Terraform deployment.
# Run with: source ./nebius-env-init.sh
#
# NOTE: Do NOT use 'set -e' as this script is meant to be sourced
#

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

# Check if jq is installed
has_jq() {
    command -v jq &>/dev/null
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

# Interactive prompt with default value
prompt_with_default() {
    local prompt=$1
    local default=$2
    local var_name=$3

    read_prompt_var "$prompt" "$var_name" "$default"
}

# List existing projects in a tenant
list_projects() {
    local tenant_id=$1
    local nebius_path=$(get_nebius_path)
    
    echo -e "${CYAN}Fetching existing projects...${NC}"
    local projects=$("$nebius_path" iam project list --parent-id "$tenant_id" --format json 2>/dev/null)
    
    if [[ -z "$projects" || "$projects" == "[]" ]]; then
        echo "  No projects found in this tenant."
        return 1
    fi
    
    echo ""
    echo "Existing projects:"
    echo "$projects" | jq -r '.[] | "  - \(.metadata.name) (\(.metadata.id))"' 2>/dev/null || echo "  (Could not parse projects)"
    echo ""
    return 0
}

# Create a new project
create_project() {
    local tenant_id=$1
    local project_name=$2
    local nebius_path=$(get_nebius_path)
    
    echo -e "${BLUE}Creating new project: $project_name${NC}"
    
    if "$nebius_path" iam project create --parent-id "$tenant_id" --name "$project_name" 2>&1; then
        echo -e "${GREEN}[✓]${NC} Project created successfully"
        
        # Get the project ID
        local project_id=$("$nebius_path" iam project get-by-name --parent-id "$tenant_id" --name "$project_name" --format json 2>/dev/null | jq -r '.metadata.id')
        
        if [[ -n "$project_id" && "$project_id" != "null" ]]; then
            echo "  Project ID: $project_id"
            echo "$project_id"
            return 0
        fi
    fi
    
    echo -e "${RED}[ERROR]${NC} Failed to create project"
    return 1
}

# Get project ID by name
get_project_id_by_name() {
    local tenant_id=$1
    local project_name=$2
    local nebius_path=$(get_nebius_path)
    
    "$nebius_path" iam project get-by-name --parent-id "$tenant_id" --name "$project_name" --format json 2>/dev/null | jq -r '.metadata.id'
}

# Interactive project selection/creation
select_or_create_project() {
    local tenant_id=$1
    local nebius_path=$(get_nebius_path)
    
    echo ""
    echo -e "${BLUE}Project Configuration${NC}"
    echo ""
    echo "Options:"
    echo "  1) Use existing project (enter project ID)"
    echo "  2) Create new project"
    echo "  3) List existing projects first"
    echo ""
    
    local choice
    read_prompt_var "Choose option [1/2/3]" choice ""
    
    case $choice in
        1)
            read_prompt_var "Enter Project ID" NEBIUS_PROJECT_ID ""
            ;;
        2)
            local project_name
            read_prompt_var "Enter new project name" project_name ""
            
            if [[ -z "$project_name" ]]; then
                echo -e "${RED}[ERROR]${NC} Project name cannot be empty"
                return 1
            fi
            
            # Check if project already exists
            local existing_id=$(get_project_id_by_name "$tenant_id" "$project_name")
            if [[ -n "$existing_id" && "$existing_id" != "null" ]]; then
                echo -e "${YELLOW}[INFO]${NC} Project '$project_name' already exists"
                echo "  Using existing project ID: $existing_id"
                NEBIUS_PROJECT_ID="$existing_id"
            else
                NEBIUS_PROJECT_ID=$(create_project "$tenant_id" "$project_name")
                if [[ $? -ne 0 || -z "$NEBIUS_PROJECT_ID" ]]; then
                    return 1
                fi
            fi
            ;;
        3)
            list_projects "$tenant_id"
            echo ""
            read_prompt_var "Enter Project ID from the list above (or 'new' to create)" input ""
            
            if [[ "$input" == "new" ]]; then
                local project_name
                read_prompt_var "Enter new project name" project_name ""
                
                if [[ -z "$project_name" ]]; then
                    echo -e "${RED}[ERROR]${NC} Project name cannot be empty"
                    return 1
                fi
                
                NEBIUS_PROJECT_ID=$(create_project "$tenant_id" "$project_name")
                if [[ $? -ne 0 || -z "$NEBIUS_PROJECT_ID" ]]; then
                    return 1
                fi
            else
                NEBIUS_PROJECT_ID="$input"
            fi
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} Invalid option"
            return 1
            ;;
    esac
    
    return 0
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
    
    # Step 3: Configure deployment settings
    echo -e "${BLUE}Step 3: Configure deployment settings${NC}"

    local nebius_path=$(get_nebius_path)

    # Check for existing environment variables or use defaults
    local current_tenant="${NEBIUS_TENANT_ID:-}"
    local current_project="${NEBIUS_PROJECT_ID:-}"
    local current_region="${NEBIUS_REGION:-eu-north1}"

    # Sanitize previously set values in case they were corrupted by a failed prompt
    if [[ -n "$current_tenant" && ! "$current_tenant" =~ ^tenant-[a-z0-9]+$ ]]; then
        current_tenant=""
    fi
    if [[ -n "$current_project" && ! "$current_project" =~ ^project-[a-z0-9]+$ ]]; then
        current_project=""
    fi
    echo ""

    # Tenant ID
    if [[ -z "$current_tenant" ]]; then
        echo "Tenant ID is required. Find it in the Nebius Console under IAM > Tenants"
        echo ""
        read_prompt_var "List available tenants? (y/N)" list_tenants ""

        if [[ "$list_tenants" =~ ^[yY]$ ]]; then
            echo ""
            echo "Fetching available tenants..."
            local tenants=$("$nebius_path" iam tenant list --format json 2>/dev/null)
            if [[ -n "$tenants" && "$tenants" != "[]" ]]; then
                echo ""
                echo "Available tenants:"
                if has_jq; then
                    local page_token=""
                    local total_count=0
                    local last_tenant_id=""
                    while :; do
                        if [[ -n "$page_token" ]]; then
                            tenants=$("$nebius_path" iam tenant list --format json --page-token "$page_token" 2>/dev/null)
                        else
                            tenants=$("$nebius_path" iam tenant list --format json 2>/dev/null)
                        fi

                        echo "$tenants" | jq -r '.items // . | map(select(.metadata.name | startswith("billing-test") | not)) | .[] | "  - \(.metadata.name): \(.metadata.id)"' 2>/dev/null || true
                        local page_count
                        page_count=$(echo "$tenants" | jq -r '(.items // .) | map(select(.metadata.name | startswith("billing-test") | not)) | length' 2>/dev/null || echo "0")
                        total_count=$((total_count + page_count))
                        if [[ "$page_count" -gt 0 ]]; then
                            last_tenant_id=$(echo "$tenants" | jq -r '(.items // .) | map(select(.metadata.name | startswith("billing-test") | not)) | .[-1].metadata.id' 2>/dev/null)
                        fi

                        page_token=$(echo "$tenants" | jq -r '.next_page_token // empty' 2>/dev/null)
                        if [[ -z "$page_token" ]]; then
                            break
                        fi
                    done

                    # Auto-detect if only one tenant across all pages
                    if [[ "$total_count" == "1" ]]; then
                        current_tenant="$last_tenant_id"
                        echo -e "${GREEN}[✓]${NC} Auto-detected tenant: $current_tenant"
                    fi
                else
                    echo "  (jq not found; run 'brew install jq' to show tenants)"
                fi
            else
                echo "  No tenants found."
            fi
            echo ""
        fi

        prompt_with_default "Enter Tenant ID" "$current_tenant" "NEBIUS_TENANT_ID"
    else
        prompt_with_default "Tenant ID" "$current_tenant" "NEBIUS_TENANT_ID"
    fi
    
    # Validate tenant ID
    if [[ -z "$NEBIUS_TENANT_ID" ]]; then
        echo -e "${RED}[ERROR]${NC} Tenant ID is required!"
        return 1
    fi
    
    # Project ID - with option to create
    if [[ -z "$current_project" ]]; then
        echo ""
        echo "No project configured. You can use an existing project or create a new one."
        if ! select_or_create_project "$NEBIUS_TENANT_ID"; then
            return 1
        fi
    else
        echo ""
        echo "Current project: $current_project"
        read_prompt_var "Use this project? (Y/n/new)" use_current ""
        
        case $use_current in
            n|N)
                if ! select_or_create_project "$NEBIUS_TENANT_ID"; then
                    return 1
                fi
                ;;
            new)
                local project_name
                read_prompt_var "Enter new project name" project_name ""
                NEBIUS_PROJECT_ID=$(create_project "$NEBIUS_TENANT_ID" "$project_name")
                if [[ $? -ne 0 || -z "$NEBIUS_PROJECT_ID" ]]; then
                    return 1
                fi
                ;;
            *)
                NEBIUS_PROJECT_ID="$current_project"
                ;;
        esac
    fi
    
    # Validate project ID format
    if [[ -z "$NEBIUS_PROJECT_ID" ]]; then
        echo -e "${RED}[ERROR]${NC} Project ID is required!"
        return 1
    fi
    
    # Check if project ID looks valid (should start with 'project-')
    if [[ ! "$NEBIUS_PROJECT_ID" =~ ^project-[a-z0-9]+ ]]; then
        echo -e "${RED}[ERROR]${NC} Invalid project ID format: '$NEBIUS_PROJECT_ID'"
        echo "  Project IDs should look like: project-e00abc123def456"
        echo ""
        echo "  Run this to list your projects:"
        echo "    nebius iam project list --parent-id $NEBIUS_TENANT_ID"
        return 1
    fi
    
    # Region
    echo ""
    echo "Available regions:"
    echo "  - eu-north1   (Finland - H100, H200, L40S)"
    echo "  - eu-north2   (H200)"
    echo "  - eu-west1    (H200)"
    echo "  - me-west1    (B200)"
    echo "  - uk-south1   (B300)"
    echo "  - us-central1 (H200, B200)"
    prompt_with_default "Region" "${current_region:-eu-north1}" "NEBIUS_REGION"
    
    # Step 4: Export environment variables
    echo ""
    echo -e "${BLUE}Step 4: Setting environment variables${NC}"
    
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
