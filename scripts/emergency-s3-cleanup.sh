#!/bin/bash

# ============================================================================
# Emergency S3 Cleanup Script - When Terraform State is Corrupted
# ============================================================================
# This script is for emergency situations where:
# - Terraform state is corrupted or missing
# - Normal terraform destroy doesn't work
# - Manual cleanup of S3 resources is required
# - You need to forcefully remove all S3 buckets and related resources
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
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

# Emergency backup directory
EMERGENCY_BACKUP_DIR="${PROJECT_ROOT}/backups/emergency-cleanup-$(date +%Y%m%d-%H%M%S)"

# Flags
DRY_RUN=false
FORCE_DELETE=false
BACKUP_BEFORE_DELETE=false
VERBOSE=false
NUCLEAR_OPTION=false

# ============================================================================
# Utility Functions
# ============================================================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] [EMERGENCY]${NC} $*"
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

nuclear_warn() {
    echo -e "${PURPLE}[NUCLEAR]${NC} $*"
}

show_usage() {
    cat << EOF
${RED}EMERGENCY S3 CLEANUP SCRIPT${NC}

${YELLOW} WARNING: This is for EMERGENCY use only when Terraform is broken!${NC}
${YELLOW}  This will FORCEFULLY DELETE S3 buckets WITHOUT Terraform validation!${NC}

${YELLOW}WHEN TO USE THIS:${NC}
    - Terraform state is corrupted
    - Normal 'terraform destroy' fails
    - You need to manually clean up S3 resources
    - Infrastructure is in an inconsistent state

${YELLOW}USAGE:${NC}
    $(basename "$0") [OPTIONS]

${YELLOW}OPTIONS:${NC}
    -r, --region REGION         AWS region (default: auto-detect)
    -p, --project PROJECT       Project name pattern to match
    -a, --account-id ACCOUNT    AWS account ID for safety validation
    
    --dry-run                   Show what would be deleted without deleting
    --force                     Force deletion without safety prompts
    --backup                    Backup all bucket contents before deletion
    --nuclear                   Delete ALL buckets matching patterns (DANGEROUS!)
    --verbose                   Enable verbose output
    
    -h, --help                  Show this help message

${YELLOW}EMERGENCY CLEANUP PROCESS:${NC}
    1. Auto-discover S3 buckets matching your project patterns
    2. Backup bucket contents and configurations (if requested)
    3. Force delete all objects, versions, and delete markers
    4. Delete buckets themselves
    5. Clean up related DynamoDB tables
    6. Verify complete cleanup

${YELLOW}EXAMPLES:${NC}
    # Emergency cleanup with backup (RECOMMENDED)
    $(basename "$0") --project myproject --backup --dry-run
    
    # Force cleanup without backup (DANGEROUS)
    $(basename "$0") --project myproject --force
    
    # Nuclear option - delete ALL matching buckets
    $(basename "$0") --project myproject --nuclear --force

${RED}⚠️  CRITICAL WARNINGS:${NC}
${RED}    - This bypasses ALL Terraform safety checks${NC}
${RED}    - This will PERMANENTLY DELETE data${NC}
${RED}    - Backend state will be DESTROYED${NC}
${RED}    - Use --backup to save data before deletion${NC}
${RED}    - Test with --dry-run first!${NC}

EOF
}

# ============================================================================
# Safety and Validation Functions
# ============================================================================

validate_aws_account() {
    local expected_account="${1:-}"
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        fatal "AWS CLI not configured or invalid credentials"
    fi
    
    local current_account
    current_account=$(aws sts get-caller-identity --query 'Account' --output text)
    
    log "Current AWS Account: $current_account"
    
    if [[ -n "$expected_account" && "$current_account" != "$expected_account" ]]; then
        fatal "Account mismatch! Expected: $expected_account, Current: $current_account"
    fi
    
    local identity
    identity=$(aws sts get-caller-identity --query 'Arn' --output text)
    log "AWS Identity: $identity"
    
    return 0
}

emergency_confirmation() {
    local project_pattern="$1"
    
    echo ""
    error EMERGENCY S3 CLEANUP CONFIRMATION"
    error ""
    error "This will PERMANENTLY DELETE S3 buckets matching:"
    error "  Project Pattern: $project_pattern"
    error "  Region: $(aws configure get region 2>/dev/null || echo 'default')"
    error "  Account: $(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null)"
    error ""
    error "  THIS BYPASSES ALL TERRAFORM SAFETY CHECKS!"
    error "  ALL DATA WILL BE PERMANENTLY LOST!"
    error "  BACKEND STATE WILL BE DESTROYED!"
    error ""
    
    if [[ "$NUCLEAR_OPTION" == "true" ]]; then
        nuclear_warn "NUCLEAR OPTION ENABLED - ALL MATCHING BUCKETS WILL BE DELETED!"
        echo -e "${PURPLE}Type 'NUCLEAR-DELETE-EVERYTHING' to proceed:${NC} "
        read -r confirmation
        if [[ "$confirmation" != "NUCLEAR-DELETE-EVERYTHING" ]]; then
            log "Nuclear deletion cancelled."
            exit 0
        fi
    else
        echo -e "${RED}Type 'EMERGENCY-DELETE-S3-BUCKETS' to proceed:${NC} "
        read -r confirmation
        if [[ "$confirmation" != "EMERGENCY-DELETE-S3-BUCKETS" ]]; then
            log "Emergency cleanup cancelled."
            exit 0
        fi
    fi
    
    echo ""
    warn " Proceeding with emergency S3 cleanup in 5 seconds..."
    warn " Press Ctrl+C to abort!"
    for i in {5..1}; do
        echo -n " $i... "
        sleep 1
    done
    echo ""
    error " STARTING EMERGENCY CLEANUP NOW!"
    echo ""
}

# ============================================================================
# Discovery Functions
# ============================================================================

discover_project_s3_buckets() {
    local project_pattern="$1"
    
    log " Discovering S3 buckets matching project pattern: $project_pattern"
    
    local all_buckets
    all_buckets=$(aws s3api list-buckets --query 'Buckets[].Name' --output text)
    
    local matching_buckets=()
    while IFS= read -r bucket; do
        if [[ "$bucket" == *"$project_pattern"* ]]; then
            matching_buckets+=("$bucket")
            log "  ✓ Found: $bucket"
        fi
    done <<< "$all_buckets"
    
    if [[ ${#matching_buckets[@]} -eq 0 ]]; then
        warn "No S3 buckets found matching pattern: $project_pattern"
        return 0
    fi
    
    log " Total buckets found: ${#matching_buckets[@]}"
    printf '%s\n' "${matching_buckets[@]}"
}

discover_related_dynamodb_tables() {
    local project_pattern="$1"
    
    log " Discovering DynamoDB tables related to project: $project_pattern"
    
    local all_tables
    all_tables=$(aws dynamodb list-tables --query 'TableNames[]' --output text 2>/dev/null || echo "")
    
    local matching_tables=()
    while IFS= read -r table; do
        if [[ "$table" == *"terraform-locks"* ]] || [[ "$table" == *"$project_pattern"* ]]; then
            matching_tables+=("$table")
            log "  ✓ Found DynamoDB table: $table"
        fi
    done <<< "$all_tables"
    
    if [[ ${#matching_tables[@]} -eq 0 ]]; then
        log "No related DynamoDB tables found"
        return 0
    fi
    
    printf '%s\n' "${matching_tables[@]}"
}

# ============================================================================
# Emergency Backup Functions
# ============================================================================

emergency_backup_bucket() {
    local bucket_name="$1"
    local backup_path="$EMERGENCY_BACKUP_DIR/$bucket_name"
    
    log " Emergency backup of bucket: $bucket_name"
    
    mkdir -p "$backup_path/data"
    mkdir -p "$backup_path/config"
    
    # Backup all current objects
    log "   Backing up current objects..."
    aws s3 sync "s3://$bucket_name" "$backup_path/data/" || warn "Failed to backup some objects"
    
    # Backup configurations
    log "    Backing up bucket configurations..."
    
    # Bucket info
    aws s3api list-objects-v2 --bucket "$bucket_name" > "$backup_path/config/objects.json" 2>/dev/null || true
    aws s3api get-bucket-versioning --bucket "$bucket_name" > "$backup_path/config/versioning.json" 2>/dev/null || true
    aws s3api get-bucket-lifecycle-configuration --bucket "$bucket_name" > "$backup_path/config/lifecycle.json" 2>/dev/null || true
    aws s3api get-bucket-encryption --bucket "$bucket_name" > "$backup_path/config/encryption.json" 2>/dev/null || true
    aws s3api get-bucket-notification-configuration --bucket "$bucket_name" > "$backup_path/config/notifications.json" 2>/dev/null || true
    aws s3api get-bucket-tagging --bucket "$bucket_name" > "$backup_path/config/tags.json" 2>/dev/null || true
    aws s3api get-bucket-policy --bucket "$bucket_name" > "$backup_path/config/policy.json" 2>/dev/null || true
    
    # Object versions if versioning is enabled
    if aws s3api get-bucket-versioning --bucket "$bucket_name" --query 'Status' --output text 2>/dev/null | grep -q "Enabled"; then
        log "  Backing up object versions metadata..."
        aws s3api list-object-versions --bucket "$bucket_name" > "$backup_path/config/versions.json" 2>/dev/null || true
    fi
    
    success " Emergency backup completed: $backup_path"
}

emergency_backup_all() {
    local buckets=("$@")
    
    if [[ ${#buckets[@]} -eq 0 ]]; then
        return 0
    fi
    
    log " Starting emergency backup of ${#buckets[@]} buckets..."
    
    for bucket in "${buckets[@]}"; do
        emergency_backup_bucket "$bucket"
    done
    
    # Create restore script
    cat > "$EMERGENCY_BACKUP_DIR/restore-instructions.md" << EOF
# Emergency S3 Restore Instructions

This backup was created on: $(date)
Buckets backed up: ${#buckets[@]}

## Restore Process:

1. **Recreate buckets:**
   \`\`\`bash
   aws s3 mb s3://bucket-name --region your-region
   \`\`\`

2. **Restore objects:**
   \`\`\`bash
   aws s3 sync ./bucket-name/data/ s3://bucket-name/
   \`\`\`

3. **Restore configurations using the JSON files in config/ directories**

## Buckets in this backup:
$(printf '- %s\n' "${buckets[@]}")
EOF
    
    success "All emergency backups completed: $EMERGENCY_BACKUP_DIR"
}

# ============================================================================
# Emergency Destruction Functions
# ============================================================================

emergency_force_empty_bucket() {
    local bucket_name="$1"
    
    log "Force emptying bucket: $bucket_name"
    
    if ! aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        log "  Bucket $bucket_name no longer exists"
        return 0
    fi
    
    # Delete all current objects
    log "  Deleting current objects..."
    aws s3 rm "s3://$bucket_name" --recursive 2>/dev/null || warn "Some objects may remain"
    
    # Handle versioned objects
    local versioning_status
    versioning_status=$(aws s3api get-bucket-versioning --bucket "$bucket_name" --query 'Status' --output text 2>/dev/null || echo "None")
    
    if [[ "$versioning_status" == "Enabled" ]]; then
        log "  Force deleting all object versions..."
        
        # Delete all versions
        aws s3api list-object-versions --bucket "$bucket_name" --output text \
            --query 'Versions[].[Key,VersionId]' 2>/dev/null | \
        while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" && "$key" != "None" && "$version_id" != "None" ]]; then
                aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version_id" 2>/dev/null || true
            fi
        done
        
        # Delete all delete markers
        aws s3api list-object-versions --bucket "$bucket_name" --output text \
            --query 'DeleteMarkers[].[Key,VersionId]' 2>/dev/null | \
        while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" && "$key" != "None" && "$version_id" != "None" ]]; then
                aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version_id" 2>/dev/null || true
            fi
        done
    fi
    
    # Clean up multipart uploads
    log " Cleaning up multipart uploads..."
    aws s3api list-multipart-uploads --bucket "$bucket_name" --output text \
        --query 'Uploads[].[Key,UploadId]' 2>/dev/null | \
    while read -r key upload_id; do
        if [[ -n "$key" && -n "$upload_id" && "$key" != "None" && "$upload_id" != "None" ]]; then
            aws s3api abort-multipart-upload --bucket "$bucket_name" --key "$key" --upload-id "$upload_id" 2>/dev/null || true
        fi
    done
    
    success "Force emptied bucket: $bucket_name"
}

emergency_force_delete_bucket() {
    local bucket_name="$1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "[DRY RUN] Would force delete bucket: $bucket_name"
        return 0
    fi
    
    log " Force deleting bucket: $bucket_name"
    
    # First empty the bucket completely
    emergency_force_empty_bucket "$bucket_name"
    
    # Now delete the bucket itself
    if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        if aws s3api delete-bucket --bucket "$bucket_name" 2>/dev/null; then
            success " Successfully deleted bucket: $bucket_name"
        else
            error  Failed to delete bucket: $bucket_name (may still contain objects)"
            return 1
        fi
    else
        log " Bucket $bucket_name was already deleted"
    fi
}

emergency_delete_dynamodb_table() {
    local table_name="$1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "[DRY RUN] Would delete DynamoDB table: $table_name"
        return 0
    fi
    
    log "Force deleting DynamoDB table: $table_name"
    
    if aws dynamodb describe-table --table-name "$table_name" >/dev/null 2>&1; then
        aws dynamodb delete-table --table-name "$table_name" >/dev/null 2>&1 || warn "Failed to delete table: $table_name"
        success " Deleted DynamoDB table: $table_name"
    else
        log " DynamoDB table $table_name doesn't exist"
    fi
}

# ============================================================================
# Main Emergency Cleanup
# ============================================================================

emergency_cleanup_all() {
    local project_pattern="$1"
    
    log "Starting emergency S3 cleanup for project: $project_pattern"
    
    # Discover all resources
    local s3_buckets dynamodb_tables
    mapfile -t s3_buckets < <(discover_project_s3_buckets "$project_pattern")
    mapfile -t dynamodb_tables < <(discover_related_dynamodb_tables "$project_pattern")
    
    if [[ ${#s3_buckets[@]} -eq 0 && ${#dynamodb_tables[@]} -eq 0 ]]; then
        warn "No resources found matching project pattern: $project_pattern"
        return 0
    fi
    
    log "Emergency cleanup targets:"
    log "  S3 Buckets: ${#s3_buckets[@]}"
    log "  DynamoDB Tables: ${#dynamodb_tables[@]}"
    
    # Backup if requested
    if [[ "$BACKUP_BEFORE_DELETE" == "true" && "$DRY_RUN" != "true" ]]; then
        emergency_backup_all "${s3_buckets[@]}"
    fi
    
    # Delete S3 buckets
    if [[ ${#s3_buckets[@]} -gt 0 ]]; then
        log "Force deleting ${#s3_buckets[@]} S3 buckets..."
        for bucket in "${s3_buckets[@]}"; do
            emergency_force_delete_bucket "$bucket"
        done
    fi
    
    # Delete DynamoDB tables
    if [[ ${#dynamodb_tables[@]} -gt 0 ]]; then
        log " Force deleting ${#dynamodb_tables[@]} DynamoDB tables..."
        for table in "${dynamodb_tables[@]}"; do
            emergency_delete_dynamodb_table "$table"
        done
    fi
    
    success " Emergency cleanup completed!"
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    local region=""
    local project_pattern=""
    local account_id=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--region)
                region="$2"
                shift 2
                ;;
            -p|--project)
                project_pattern="$2"
                shift 2
                ;;
            -a|--account-id)
                account_id="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --backup)
                BACKUP_BEFORE_DELETE=true
                shift
                ;;
            --nuclear)
                NUCLEAR_OPTION=true
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
    
    # Validate inputs
    if [[ -z "$project_pattern" ]]; then
        error "Project pattern is required. Use -p or --project"
        show_usage
        exit 1
    fi
    
    log "EMERGENCY S3 CLEANUP STARTING"
    log "Project Pattern: $project_pattern"
    log "Dry Run: $DRY_RUN"
    log "Force Delete: $FORCE_DELETE"
    log "Backup Before Delete: $BACKUP_BEFORE_DELETE"
    log "Nuclear Option: $NUCLEAR_OPTION"
    
    # Safety validations
    validate_aws_account "$account_id"
    
    # Emergency confirmation
    if [[ "$FORCE_DELETE" != "true" && "$DRY_RUN" != "true" ]]; then
        emergency_confirmation "$project_pattern"
    fi
    
    # Execute emergency cleanup
    emergency_cleanup_all "$project_pattern"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn  DRY RUN COMPLETE - No actual changes were made"
    else
        success "EMERGENCY CLEANUP COMPLETED!"
        if [[ "$BACKUP_BEFORE_DELETE" == "true" ]]; then
            success "Emergency backups saved to: $EMERGENCY_BACKUP_DIR"
        fi
    fi
}

# Execute main function
main "$@"