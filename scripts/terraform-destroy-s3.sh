#!/bin/bash

# ============================================================================
# Terraform-Integrated S3 Destruction Script
# ============================================================================
# This script integrates with Terraform to safely destroy S3 infrastructure
# by first using Terraform destroy and then handling any remaining resources
# that Terraform couldn't clean up (like versioned objects).
# ============================================================================

set -euo pipefail

# ============================================================================
# Configuration and Constants
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Default paths
DEFAULT_TERRAFORM_DIR="${PROJECT_ROOT}/infrastructure/s3-provisioning"
BACKUP_DIR="${PROJECT_ROOT}/backups/terraform-destroy-$(date +%Y%m%d-%H%M%S)"

# Flags
DRY_RUN=false
SKIP_STATE_BACKUP=false
AUTO_APPROVE=false
VERBOSE=false

# ============================================================================
# Utility Functions
# ============================================================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

fatal() {
    error "$*"
    exit 1
}

show_usage() {
    cat << EOF
${GREEN}Terraform-Integrated S3 Destruction Script${NC}

This script uses Terraform to destroy S3 infrastructure safely, then cleans up
any remaining resources that Terraform couldn't handle (like versioned objects).

${YELLOW}USAGE:${NC}
    $(basename "$0") [OPTIONS]

${YELLOW}OPTIONS:${NC}
    -d, --terraform-dir DIR     Terraform directory (default: infrastructure/s3-provisioning)
    -t, --target TARGET         Specific Terraform target to destroy (e.g., module.logs_bucket)
    
    --dry-run                   Show what would be destroyed without actually destroying
    --auto-approve              Skip Terraform confirmation prompts
    --skip-state-backup         Skip backing up Terraform state before destruction
    --verbose                   Enable verbose output
    
    -h, --help                  Show this help message

${YELLOW}EXAMPLES:${NC}
    # Destroy all S3 infrastructure managed by Terraform
    $(basename "$0")
    
    # Destroy only the logs bucket module
    $(basename "$0") --target module.logs_bucket
    
    # Dry run to see what would be destroyed
    $(basename "$0") --dry-run
    
    # Auto-approve destruction (use with caution!)
    $(basename "$0") --auto-approve --target module.traces_bucket

${YELLOW}PROCESS:${NC}
    1. Backup Terraform state files
    2. Run terraform destroy for managed resources
    3. Clean up any remaining S3 objects/versions that Terraform couldn't delete
    4. Verify all resources are destroyed

${RED}WARNING:${NC} This will destroy Terraform-managed S3 infrastructure!

EOF
}

# ============================================================================
# Terraform Functions
# ============================================================================

check_terraform() {
    if ! command -v terraform >/dev/null 2>&1; then
        fatal "Terraform CLI is not installed. Please install it first."
    fi
    
    log "Terraform version: $(terraform version -json | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1)"
}

check_terraform_directory() {
    local terraform_dir="$1"
    
    if [[ ! -d "$terraform_dir" ]]; then
        fatal "Terraform directory not found: $terraform_dir"
    fi
    
    if [[ ! -f "$terraform_dir/main.tf" ]]; then
        fatal "No main.tf found in Terraform directory: $terraform_dir"
    fi
    
    log "Using Terraform directory: $terraform_dir"
}

backup_terraform_state() {
    local terraform_dir="$1"
    local backup_path="$BACKUP_DIR/terraform-state"
    
    log "Backing up Terraform state..."
    mkdir -p "$backup_path"
    
    # Backup local state if it exists
    if [[ -f "$terraform_dir/terraform.tfstate" ]]; then
        cp "$terraform_dir/terraform.tfstate" "$backup_path/"
        log "Local state backed up"
    fi
    
    # Backup remote state by pulling it
    if [[ -f "$terraform_dir/.terraform/terraform.tfstate" ]]; then
        cp "$terraform_dir/.terraform/terraform.tfstate" "$backup_path/remote-terraform.tfstate"
        log "Remote state backed up"
    fi
    
    # Backup terraform files
    cp -r "$terraform_dir"/*.tf "$backup_path/" 2>/dev/null || true
    cp "$terraform_dir"/.terraform.lock.hcl "$backup_path/" 2>/dev/null || true
    
    success "Terraform state backed up to: $backup_path"
}

get_s3_resources_from_state() {
    local terraform_dir="$1"
    
    log "Getting S3 resources from Terraform state..."
    
    cd "$terraform_dir"
    
    # Get all S3-related resources
    local s3_resources
    s3_resources=$(terraform state list | grep -E "(aws_s3_|aws_dynamodb_table)" || true)
    
    if [[ -z "$s3_resources" ]]; then
        warn "No S3 resources found in Terraform state"
        return 0
    fi
    
    log "Found S3 resources in Terraform state:"
    echo "$s3_resources" | while read -r resource; do
        log "  - $resource"
    done
    
    echo "$s3_resources"
}

terraform_plan_destroy() {
    local terraform_dir="$1"
    local target="${2:-}"
    
    log "Creating Terraform destroy plan..."
    
    cd "$terraform_dir"
    
    local plan_args=()
    if [[ -n "$target" ]]; then
        plan_args+=(-target="$target")
        log "Planning destroy for target: $target"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        terraform plan -destroy "${plan_args[@]}"
    else
        terraform plan -destroy -out=destroy.tfplan "${plan_args[@]}"
        success "Destroy plan saved to: destroy.tfplan"
    fi
}

terraform_destroy() {
    local terraform_dir="$1"
    local auto_approve="$2"
    
    log "Executing Terraform destroy..."
    
    cd "$terraform_dir"
    
    local destroy_args=()
    if [[ "$auto_approve" == "true" ]]; then
        destroy_args+=(-auto-approve)
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "[DRY RUN] Would execute: terraform destroy ${destroy_args[*]}"
    else
        if [[ -f "destroy.tfplan" ]]; then
            terraform apply destroy.tfplan
            rm -f destroy.tfplan
        else
            terraform destroy "${destroy_args[@]}"
        fi
        success "Terraform destroy completed"
    fi
}

# ============================================================================
# Post-Terraform Cleanup Functions
# ============================================================================

get_bucket_names_from_config() {
    local terraform_dir="$1"
    local buckets=()
    
    log "Extracting bucket names from Terraform configuration..."
    
    # Get project info from terraform configuration or use defaults
    local project_name="myproject"
    local region="us-east-1"
    local environment="production"
    
    # Try to extract from terraform files if they exist
    if [[ -f "$terraform_dir/main.tf" ]]; then
        project_name=$(grep -E 'project_name.*=' "$terraform_dir/main.tf" | head -1 | sed 's/.*"\([^"]*\)".*/\1/' 2>/dev/null || echo "myproject")
        region=$(grep -E 'region.*=' "$terraform_dir/main.tf" | head -1 | sed 's/.*"\([^"]*\)".*/\1/' 2>/dev/null || echo "us-east-1")
        environment=$(grep -E 'environment.*=' "$terraform_dir/main.tf" | head -1 | sed 's/.*"\([^"]*\)".*/\1/' 2>/dev/null || echo "production")
    fi
    
    # Build bucket patterns based on discovered/default values
    local bucket_patterns=(
        "${project_name}-${region}-logs-${environment}"
        "${project_name}-${region}-traces-${environment}"  
        "${project_name}-${region}-backups-${environment}"
        "${project_name}-terraform-state-${environment}"
    )
    
    for bucket in "${bucket_patterns[@]}"; do
        if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
            buckets+=("$bucket")
            log "Found existing bucket: $bucket"
        fi
    done
    
    printf '%s\n' "${buckets[@]}"
}

cleanup_remaining_bucket_contents() {
    local bucket_name="$1"
    
    log "Cleaning up remaining contents in bucket: $bucket_name"
    
    if ! aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        log "Bucket $bucket_name no longer exists, skipping cleanup"
        return 0
    fi
    
    # Clean up versioned objects that Terraform couldn't delete
    local versioning_status
    versioning_status=$(aws s3api get-bucket-versioning --bucket "$bucket_name" --query 'Status' --output text 2>/dev/null || echo "None")
    
    if [[ "$versioning_status" == "Enabled" ]]; then
        log "Cleaning up versioned objects from $bucket_name..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            local version_count
            version_count=$(aws s3api list-object-versions --bucket "$bucket_name" --query 'length(Versions)' --output text 2>/dev/null || echo "0")
            
            # Handle AWS CLI returning "None" instead of a number
            if [[ "$version_count" == "None" || "$version_count" == "" ]]; then
                version_count=0
            fi
            
            warn "[DRY RUN] Would delete $version_count object versions from $bucket_name"
        else
            # Delete all versions
            aws s3api list-object-versions --bucket "$bucket_name" --output text \
                --query 'Versions[].[Key,VersionId]' 2>/dev/null | \
            while read -r key version_id; do
                if [[ -n "$key" && -n "$version_id" && "$key" != "None" && "$version_id" != "None" ]]; then
                    aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version_id" >/dev/null || true
                fi
            done
            
            # Delete all delete markers
            aws s3api list-object-versions --bucket "$bucket_name" --output text \
                --query 'DeleteMarkers[].[Key,VersionId]' 2>/dev/null | \
            while read -r key version_id; do
                if [[ -n "$key" && -n "$version_id" && "$key" != "None" && "$version_id" != "None" ]]; then
                    aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version_id" >/dev/null || true
                fi
            done
        fi
    fi
    
    # Clean up remaining current objects
    local object_count
    object_count=$(aws s3api list-objects-v2 --bucket "$bucket_name" --query 'KeyCount' --output text 2>/dev/null || echo "0")
    
    # Handle AWS CLI returning "None" instead of a number
    if [[ "$object_count" == "None" || "$object_count" == "" ]]; then
        object_count=0
    fi
    
    if [[ "$object_count" -gt 0 ]]; then
        log "Cleaning up $object_count remaining objects from $bucket_name..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            warn "[DRY RUN] Would delete $object_count objects from $bucket_name"
        else
            aws s3 rm "s3://$bucket_name" --recursive || warn "Some objects may not have been deleted"
        fi
    fi
    
    # Try to delete the bucket if it's now empty
    if [[ "$DRY_RUN" != "true" ]]; then
        if aws s3api delete-bucket --bucket "$bucket_name" 2>/dev/null; then
            success "Successfully deleted remaining bucket: $bucket_name"
        else
            warn "Could not delete bucket $bucket_name (may still contain objects)"
        fi
    fi
}

cleanup_remaining_dynamodb_tables() {
    local region="$1"
    
    # Generate table name from region  
    local region_short=$(echo "$region" | sed 's/-[0-9]*$//')
    local table_name="terraform-locks-${region_short}"
    
    log "Checking for remaining DynamoDB table: $table_name"
    
    if aws dynamodb describe-table --table-name "$table_name" >/dev/null 2>&1; then
        if [[ "$DRY_RUN" == "true" ]]; then
            warn "[DRY RUN] Would delete DynamoDB table: $table_name"
        else
            log "Deleting remaining DynamoDB table: $table_name"
            aws dynamodb delete-table --table-name "$table_name" >/dev/null
            success "Successfully deleted DynamoDB table: $table_name"
        fi
    else
        log "DynamoDB table $table_name already deleted or doesn't exist"
    fi
}

# ============================================================================
# Verification Functions
# ============================================================================

verify_destruction() {
    local terraform_dir="$1"
    
    log "Verifying complete destruction..."
    
    cd "$terraform_dir"
    
    # Check if any resources remain in state
    local remaining_resources
    remaining_resources=$(terraform state list 2>/dev/null | grep -E "(aws_s3_|aws_dynamodb_table)" || true)
    
    if [[ -n "$remaining_resources" ]]; then
        warn "Some resources still exist in Terraform state:"
        echo "$remaining_resources" | while read -r resource; do
            warn "  - $resource"
        done
        return 1
    fi
    
    # Check if buckets still exist in AWS - discover dynamically
    local terraform_config_buckets
    mapfile -t terraform_config_buckets < <(get_bucket_names_from_config "$terraform_dir")
    
    local bucket_patterns=("${terraform_config_buckets[@]}")
    
    local remaining_buckets=()
    for bucket in "${bucket_patterns[@]}"; do
        if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
            remaining_buckets+=("$bucket")
        fi
    done
    
    if [[ ${#remaining_buckets[@]} -gt 0 ]]; then
        warn "Some S3 buckets still exist in AWS:"
        for bucket in "${remaining_buckets[@]}"; do
            warn "  - $bucket"
        done
        return 1
    fi
    
    success "All S3 infrastructure has been successfully destroyed!"
    return 0
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    local terraform_dir="$DEFAULT_TERRAFORM_DIR"
    local target=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--terraform-dir)
                terraform_dir="$2"
                shift 2
                ;;
            -t|--target)
                target="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --auto-approve)
                AUTO_APPROVE=true
                shift
                ;;
            --skip-state-backup)
                SKIP_STATE_BACKUP=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                set -x
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log "=========================================="
    log "Terraform-Integrated S3 Destruction"
    log "=========================================="
    log "Terraform Directory: $terraform_dir"
    log "Dry Run: $DRY_RUN"
    log "Auto Approve: $AUTO_APPROVE"
    log "Skip State Backup: $SKIP_STATE_BACKUP"
    
    if [[ -n "$target" ]]; then
        log "Target: $target"
    fi
    
    log "=========================================="
    
    # Pre-checks
    check_terraform
    check_terraform_directory "$terraform_dir"
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        fatal "AWS CLI is not configured or credentials are invalid"
    fi
    
    # Safety confirmation
    if [[ "$AUTO_APPROVE" != "true" && "$DRY_RUN" != "true" ]]; then
        echo ""
        warn "⚠️  WARNING: This will destroy Terraform-managed S3 infrastructure!"
        echo -e "${YELLOW}Are you sure you want to continue? (y/N):${NC} "
        read -r confirmation
        
        if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
            log "Operation cancelled."
            exit 0
        fi
    fi
    
    # Step 1: Backup state
    if [[ "$SKIP_STATE_BACKUP" != "true" && "$DRY_RUN" != "true" ]]; then
        backup_terraform_state "$terraform_dir"
    fi
    
    # Step 2: Show what will be destroyed
    get_s3_resources_from_state "$terraform_dir"
    
    # Step 3: Plan destruction
    terraform_plan_destroy "$terraform_dir" "$target"
    
    # Step 4: Execute Terraform destroy
    terraform_destroy "$terraform_dir" "$AUTO_APPROVE"
    
    # Step 5: Clean up remaining resources
    if [[ -z "$target" ]]; then  # Only do full cleanup if not targeting specific resources
        log "Performing post-Terraform cleanup..."
        
        # Get bucket names that might need cleanup
        local buckets
        mapfile -t buckets < <(get_bucket_names_from_config "$terraform_dir")
        
        for bucket in "${buckets[@]}"; do
            cleanup_remaining_bucket_contents "$bucket"
        done
        
        # Cleanup DynamoDB tables using detected region
        local detected_region="us-east-1"
        if [[ -f "$terraform_dir/main.tf" ]]; then
            detected_region=$(grep -E 'region.*=' "$terraform_dir/main.tf" | head -1 | sed 's/.*"\([^"]*\)".*/\1/' 2>/dev/null || echo "us-east-1")
        fi
        cleanup_remaining_dynamodb_tables "$detected_region"
    fi
    
    # Step 6: Verify complete destruction
    if [[ "$DRY_RUN" != "true" && -z "$target" ]]; then
        if verify_destruction "$terraform_dir"; then
            success "✅ Complete S3 infrastructure destruction verified!"
        else
            warn "⚠️  Some resources may still exist. Check the warnings above."
        fi
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN COMPLETE - No actual changes were made"
    else
        success "Terraform S3 destruction completed!"
        if [[ "$SKIP_STATE_BACKUP" != "true" ]]; then
            success "State backup saved to: $BACKUP_DIR"
        fi
    fi
}

# Execute main function with all arguments
main "$@"