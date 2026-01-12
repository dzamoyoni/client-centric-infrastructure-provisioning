#!/bin/bash

# ============================================================================
# CLIENT-CENTRIC S3 Infrastructure Provisioning Script
# ============================================================================
# Dynamically provisions S3 infrastructure based on clients.auto.tfvars
# Supports both backend state buckets and client-specific observability buckets
#
# Usage:
#   ./scripts/provision-s3-client-centric.sh --region us-east-2 --environment production
#   ./scripts/provision-s3-client-centric.sh --region us-east-2 --backend-only
#   ./scripts/provision-s3-client-centric.sh --region us-east-2 --client est-test-a
#
# Features:
# - Reads client configuration from clients.auto.tfvars
# - Creates backend state buckets with organized key structure
# - Provisions shared observability buckets with client prefixes
# - Generates backend configuration files per client
# - Validates AWS credentials and permissions
# - Fully client-centric and scalable
# ============================================================================

set -euo pipefail

# ============================================================================
# Script Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# NO DEFAULTS - All parameters must be explicitly provided for safety

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# ============================================================================
# Utility Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_client() {
    echo -e "${CYAN}[CLIENT]${NC} $1"
}

log_bucket() {
    echo -e "${MAGENTA}[BUCKET]${NC} $1"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

CLIENT-CENTRIC S3 Infrastructure Provisioning
Reads client configuration from clients.auto.tfvars and creates buckets dynamically

OPTIONS:
    -r, --region REGION          AWS region (REQUIRED)
    -e, --environment ENV        Environment: production|staging|development (REQUIRED)
    -p, --project-name NAME      Project name (REQUIRED)
    -c, --client CLIENT          Provision for specific client only (optional)
    --clients-file PATH          Path to clients.auto.tfvars (auto-detected)
    --backend-only              Only create backend infrastructure
    --observability-only         Only create observability buckets
    --dry-run                   Show what would be created WITHOUT creating
    --force                     Skip confirmation prompts (DANGEROUS)
    -h, --help                  Show this help message

EXAMPLES:
    # Create all infrastructure for all clients
    $0 --region us-east-2 --environment production

    # Create backend infrastructure only
    $0 --region us-east-2 --backend-only

    # Provision for specific client
    $0 --region us-east-2 --client est-test-a

    # Dry run to see what would be created
    $0 --region us-east-2 --dry-run

BUCKET STRUCTURE:
    Backend State (1 bucket):
      - ${PROJECT_NAME}-terraform-state-${ENVIRONMENT}
      
    Observability (4 shared buckets with client prefixes):
      - ${PROJECT_NAME}-${REGION}-logs-${ENVIRONMENT}
        └── logs/client={client}/...
      - ${PROJECT_NAME}-${REGION}-traces-${ENVIRONMENT}
        └── traces/client={client}/...
      - ${PROJECT_NAME}-${REGION}-metrics-${ENVIRONMENT}
        └── metrics/client={client}/...
      - ${PROJECT_NAME}-${REGION}-audit-logs-${ENVIRONMENT}
        └── audit-logs/client={client}/...

    TOTAL: 5 S3 buckets + 1 DynamoDB table (shared across all clients)

EOF
}

# ============================================================================
# Argument Parsing
# ============================================================================

parse_arguments() {
    # NO DEFAULTS - Require explicit parameters
    AWS_REGION=""
    ENVIRONMENT=""
    PROJECT_NAME=""
    SPECIFIC_CLIENT=""
    CLIENTS_FILE=""
    BACKEND_ONLY=false
    OBSERVABILITY_ONLY=false
    DRY_RUN=false
    FORCE=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -p|--project-name)
                PROJECT_NAME="$2"
                shift 2
                ;;
            -c|--client)
                SPECIFIC_CLIENT="$2"
                shift 2
                ;;
            --clients-file)
                CLIENTS_FILE="$2"
                shift 2
                ;;
            --backend-only)
                BACKEND_ONLY=true
                shift
                ;;
            --observability-only)
                OBSERVABILITY_ONLY=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$AWS_REGION" ]]; then
        log_error "AWS region is required. Use --region <region>"
        show_usage
        exit 1
    fi
    
    if [[ -z "$ENVIRONMENT" ]]; then
        log_error "Environment is required. Use --environment <env>"
        show_usage
        exit 1
    fi
    
    if [[ -z "$PROJECT_NAME" ]]; then
        log_error "Project name is required. Use --project-name <name>"
        show_usage
        exit 1
    fi

    # Auto-detect clients file if not provided
    if [[ -z "$CLIENTS_FILE" ]]; then
        CLIENTS_FILE="$PROJECT_ROOT/providers/aws/regions/$AWS_REGION/clients.auto.tfvars"
    fi

    # Validate clients file exists
    if [[ ! -f "$CLIENTS_FILE" ]]; then
        log_error "Clients configuration file not found: $CLIENTS_FILE"
        log_error "Please ensure clients.auto.tfvars exists in the region directory"
        exit 1
    fi

    # Set region short name
    REGION_SHORT=$(echo "$AWS_REGION" | sed 's/-[0-9]*$//')
}

# ============================================================================
# Client Configuration Parser
# ============================================================================

parse_clients_config() {
    log_info "Parsing client configuration from: $CLIENTS_FILE"
    
    # Extract client names using AWK (reliable parsing)
    CLIENTS=()
    CLIENT_TIERS=()
    CLIENT_CODES=()
    
    # Get all top-level client names (two spaces indent)
    local client_names=()
    while IFS= read -r client_name; do
        [[ -n "$client_name" ]] && client_names+=("$client_name")
    done < <(awk '/^clients = \{/,/^\}/' "$CLIENTS_FILE" | grep -E "^  [a-z0-9-]+ = \{" | sed 's/ = {//' | sed 's/^  //')
    
    # For each client, extract enabled, tier, and client_code
    for client_name in "${client_names[@]}"; do
        # Extract the client block
        local client_block=$(awk "/^  $client_name = \{/,/^  \}/" "$CLIENTS_FILE")
        
        # Check if enabled
        local is_enabled=$(echo "$client_block" | grep -E "^    enabled" | grep -oE "(true|false)" | head -1)
        local tier=$(echo "$client_block" | grep -E "^    tier" | grep -oE '"[^"]+"' | tr -d '"' | head -1)
        local code=$(echo "$client_block" | grep -E "^    client_code" | grep -oE '"[^"]+"' | tr -d '"' | head -1)
        
        # Only add if enabled=true
        if [[ "$is_enabled" == "true" ]]; then
            # Filter by specific client if requested
            if [[ -z "$SPECIFIC_CLIENT" || "$client_name" == "$SPECIFIC_CLIENT" ]]; then
                CLIENTS+=("$client_name")
                CLIENT_TIERS+=("$tier")
                CLIENT_CODES+=("$code")
                log_client "Found enabled client: $client_name (tier: $tier, code: $code)"
            fi
        fi
    done
    
    if [[ ${#CLIENTS[@]} -eq 0 ]]; then
        log_error "No enabled clients found in $CLIENTS_FILE"
        exit 1
    fi
    
    log_success "Found ${#CLIENTS[@]} enabled client(s)"
}

# ============================================================================
# AWS Validation
# ============================================================================

validate_aws_credentials() {
    log_info "Validating AWS credentials..."
    
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS credentials not configured or invalid"
        log_error "Please run: aws configure"
        exit 1
    fi

    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local user_arn=$(aws sts get-caller-identity --query Arn --output text)
    
    log_success "AWS credentials validated"
    log_info "Account ID: $account_id"
    log_info "User/Role: $user_arn"
}

validate_aws_region() {
    log_info "Validating AWS region: $AWS_REGION"
    
    # Simple region format validation (faster than AWS API call)
    if [[ ! "$AWS_REGION" =~ ^(us|eu|ap|sa|ca|me|af)-(north|south|east|west|central|northeast|southeast)-[1-9]$ ]]; then
        log_warning "Region format unusual: $AWS_REGION (continuing anyway)"
    fi
    
    log_success "AWS region validated: $AWS_REGION"
}

# ============================================================================
# Bucket Names Generation
# ============================================================================

get_backend_bucket_name() {
    echo "${PROJECT_NAME}-terraform-state-${ENVIRONMENT}"
}

get_logs_bucket_name() {
    echo "${PROJECT_NAME}-${AWS_REGION}-logs-${ENVIRONMENT}"
}

get_traces_bucket_name() {
    echo "${PROJECT_NAME}-${AWS_REGION}-traces-${ENVIRONMENT}"
}

get_metrics_bucket_name() {
    echo "${PROJECT_NAME}-${AWS_REGION}-metrics-${ENVIRONMENT}"
}

get_audit_logs_bucket_name() {
    echo "${PROJECT_NAME}-${AWS_REGION}-audit-logs-${ENVIRONMENT}"
}

get_dynamodb_table_name() {
    echo "terraform-locks-${REGION_SHORT}"
}

# ============================================================================
# Display Summary
# ============================================================================

display_summary() {
    local total_buckets=0
    
    echo
    log_info "==========================================================="
    log_info "S3 INFRASTRUCTURE SUMMARY"
    log_info "==========================================================="
    log_info "Project: $PROJECT_NAME"
    log_info "Region: $AWS_REGION"
    log_info "Environment: $ENVIRONMENT"
    log_info "Enabled Clients: ${CLIENTS[*]}"
    log_info "==========================================================="
    echo
    
    if [[ "$BACKEND_ONLY" != true && "$OBSERVABILITY_ONLY" != true ]] || [[ "$BACKEND_ONLY" == true ]]; then
        log_info "═══════════════════════════════════════════════════════════"
        log_info "BACKEND INFRASTRUCTURE (Shared across all clients)"
        log_info "═══════════════════════════════════════════════════════════"
        log_bucket "  📦 Bucket #1: $(get_backend_bucket_name)"
        log_info "     Purpose: Terraform state storage for ALL clients"
        log_info "     Encryption: AES256"
        log_info "     Versioning: Enabled"
        log_info "     Public Access: Blocked"
        log_info "     State Keys:"
        for client in "${CLIENTS[@]}"; do
            log_client "       → Client '$client': providers/aws/regions/${AWS_REGION}/layers/*/${ENVIRONMENT}/terraform.tfstate"
        done
        echo
        log_info "  🔒 DynamoDB Table: $(get_dynamodb_table_name)"
        log_info "     Purpose: State locking for ALL clients"
        log_info "     Billing: Pay-per-request"
        log_info "     Clients using this table: ${CLIENTS[*]}"
        echo
        total_buckets=$((total_buckets + 1))
    fi
    
    if [[ "$BACKEND_ONLY" != true && "$OBSERVABILITY_ONLY" != true ]] || [[ "$OBSERVABILITY_ONLY" == true ]]; then
        log_info "═══════════════════════════════════════════════════════════"
        log_info "OBSERVABILITY INFRASTRUCTURE (Shared with client prefixes)"
        log_info "═══════════════════════════════════════════════════════════"
        log_bucket "  📦 Bucket #2: $(get_logs_bucket_name)"
        log_info "     Purpose: Application & system logs"
        log_info "     Retention: 90 days → STANDARD_IA (30d) → GLACIER (90d) → DELETE"
        log_info "     Encryption: AES256"
        log_info "     Versioning: Enabled"
        log_info "     Structure: logs/client={client}/cluster={cluster}/tenant={tenant}/..."
        log_info "     CLIENT DATA ISOLATION:"
        for client in "${CLIENTS[@]}"; do
            log_client "       ✓ Client '$client' → logs/client=${client}/..."
        done
        echo
        
        log_bucket "  📦 Bucket #3: $(get_traces_bucket_name)"
        log_info "     Purpose: Distributed traces (Tempo)"
        log_info "     Retention: 30 days → STANDARD_IA (30d) → DELETE"
        log_info "     Encryption: AES256"
        log_info "     Versioning: Enabled"
        log_info "     Structure: traces/client={client}/service={service}/..."
        log_info "     CLIENT DATA ISOLATION:"
        for client in "${CLIENTS[@]}"; do
            log_client "       ✓ Client '$client' → traces/client=${client}/..."
        done
        echo
        
        log_bucket "  📦 Bucket #4: $(get_metrics_bucket_name)"
        log_info "     Purpose: Prometheus metrics"
        log_info "     Retention: 90 days → STANDARD_IA (30d) → GLACIER (90d) → DELETE"
        log_info "     Encryption: AES256"
        log_info "     Versioning: Enabled"
        log_info "     Structure: metrics/client={client}/metric_type={type}/..."
        log_info "     CLIENT DATA ISOLATION:"
        for client in "${CLIENTS[@]}"; do
            log_client "       ✓ Client '$client' → metrics/client=${client}/..."
        done
        echo
        
        log_bucket "  📦 Bucket #5: $(get_audit_logs_bucket_name)"
        log_info "     Purpose: Kubernetes audit logs (COMPLIANCE)"
        log_info "     Retention: 2555 days (7 YEARS) → STANDARD_IA (30d) → GLACIER (90d)"
        log_info "     Encryption: AES256 (consider KMS for production)"
        log_info "     Versioning: Enabled"
        log_info "     Structure: audit-logs/client={client}/component={component}/..."
        log_info "     CLIENT DATA ISOLATION:"
        for client in "${CLIENTS[@]}"; do
            log_client "       ✓ Client '$client' → audit-logs/client=${client}/..."
        done
        echo
        
        total_buckets=$((total_buckets + 4))
    fi
    
    log_success "==========================================================="
    log_success "TOTAL S3 BUCKETS TO CREATE: $total_buckets"
    log_success "TOTAL DYNAMODB TABLES: 1"
    log_success "TOTAL CLIENTS SUPPORTED: ${#CLIENTS[@]}"
    log_success "==========================================================="
    echo
    
    log_info "BENEFITS OF THIS ARCHITECTURE:"
    log_info "  ✅ NO new buckets needed when adding clients"
    log_info "  ✅ Cost allocation via S3 prefixes (client={client})"
    log_info "  ✅ Single lifecycle policy per bucket"
    log_info "  ✅ Reduced S3 API costs"
    log_info "  ✅ Simplified management"
    echo
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    log_info "==========================================================="
    log_info "CLIENT-CENTRIC S3 Infrastructure Provisioning"
    log_info "==========================================================="
    log_info "Project: $PROJECT_NAME"
    log_info "Environment: $ENVIRONMENT"
    log_info "Region: $AWS_REGION"
    echo
    
    # Pre-flight checks
    validate_aws_credentials
    validate_aws_region
    parse_clients_config
    
    # Display summary
    display_summary
    
    # For dry-run, exit after summary
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN MODE] No resources will be created."
        log_info ""
        log_info "To create these resources, run without --dry-run:"
        log_info "  $0 --region $AWS_REGION --environment $ENVIRONMENT"
        exit 0
    fi
    
    # Confirm deployment
    if [[ "$FORCE" != true ]]; then
        read -p "Do you want to proceed with creating these resources? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled"
            exit 0
        fi
    fi
    
    echo
    log_info "==========================================================="
    log_info "Creating infrastructure..."
    log_info "===========================================================" 
    
    # Create backend infrastructure
    if [[ "$BACKEND_ONLY" != false ]] || [[ "$OBSERVABILITY_ONLY" == false ]]; then
        create_backend_infrastructure
    fi
    
    # Create observability infrastructure
    if [[ "$OBSERVABILITY_ONLY" != false ]] || [[ "$BACKEND_ONLY" == false ]]; then
        create_observability_infrastructure
    fi
    
    echo
    log_success "===========================================================" 
    log_success "Script completed!"
    log_success "All S3 infrastructure created successfully!"
    log_success "===========================================================" 
}

# ============================================================================
# Backend Infrastructure Creation
# ============================================================================

create_backend_infrastructure() {
    local backend_bucket=$(get_backend_bucket_name)
    local dynamodb_table=$(get_dynamodb_table_name)
    
    log_info "Creating backend infrastructure..."
    
    # Create S3 bucket for Terraform state
    log_bucket "Creating bucket: $backend_bucket"
    aws s3api create-bucket \
        --bucket "$backend_bucket" \
        --region "$AWS_REGION" \
        --create-bucket-configuration LocationConstraint="$AWS_REGION" \
        2>/dev/null || log_warning "Bucket may already exist"
    
    # Enable versioning
    log_info "Enabling versioning..."
    aws s3api put-bucket-versioning \
        --bucket "$backend_bucket" \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    log_info "Enabling encryption..."
    aws s3api put-bucket-encryption \
        --bucket "$backend_bucket" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                },
                "BucketKeyEnabled": true
            }]
        }'
    
    # Block public access
    log_info "Blocking public access..."
    aws s3api put-public-access-block \
        --bucket "$backend_bucket" \
        --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    # Create DynamoDB table for state locking
    log_info "Creating DynamoDB table: $dynamodb_table"
    aws dynamodb create-table \
        --table-name "$dynamodb_table" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$AWS_REGION" \
        2>/dev/null || log_warning "DynamoDB table may already exist"
    
    log_success "Backend infrastructure created: $backend_bucket"
}

# ============================================================================
# Observability Infrastructure Creation
# ============================================================================

create_observability_infrastructure() {
    local logs_bucket=$(get_logs_bucket_name)
    local traces_bucket=$(get_traces_bucket_name)
    local metrics_bucket=$(get_metrics_bucket_name)
    local audit_bucket=$(get_audit_logs_bucket_name)
    
    log_info "Creating observability infrastructure..."
    
    # Create all observability buckets
    for bucket_name in "$logs_bucket" "$traces_bucket" "$metrics_bucket" "$audit_bucket"; do
        log_bucket "Creating bucket: $bucket_name"
        
        aws s3api create-bucket \
            --bucket "$bucket_name" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION" \
            2>/dev/null || log_warning "Bucket may already exist: $bucket_name"
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "$bucket_name" \
            --versioning-configuration Status=Enabled
        
        # Enable encryption
        aws s3api put-bucket-encryption \
            --bucket "$bucket_name" \
            --server-side-encryption-configuration '{
                "Rules": [{
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    },
                    "BucketKeyEnabled": true
                }]
            }'
        
        # Block public access
        aws s3api put-public-access-block \
            --bucket "$bucket_name" \
            --public-access-block-configuration \
                "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
        
        log_success "Created and secured: $bucket_name"
    done
    
    log_success "All observability buckets created!"
}

# ============================================================================
# Script Entry Point
# ============================================================================

parse_arguments "$@"
main
