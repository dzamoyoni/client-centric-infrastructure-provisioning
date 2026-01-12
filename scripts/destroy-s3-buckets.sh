#!/bin/bash

# ============================================================================
# S3 Bucket Destruction Script 
#  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#  !!!!!!!!!! PLEASE RUN THIS SCRIPT IF CONSEQUENCES ARE WELL UNDERSTOOD !!!!!
#  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# ============================================================================
# This script safely destroys S3 buckets with all their contents, handling:
# - Versioned objects and delete markers
# - Multipart uploads
# - Encrypted objects
# - Cross-region replication
# - Lifecycle configurations
# - IAM policies and roles
# - DynamoDB tables (for backend state)
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
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Default values
DEFAULT_REGION="us-east-2"
DEFAULT_ENVIRONMENT="production"
DEFAULT_PROJECT="ohio-01"
BACKUP_DIR="${PROJECT_ROOT}/backups/bucket-contents-$(date +%Y%m%d-%H%M%S)"

# Flags
DRY_RUN=false
FORCE_DELETE=false
SKIP_CONFIRMATION=false
BACKUP_BEFORE_DELETE=false
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
${CYAN}S3 Bucket Destruction Script${NC}

${YELLOW}USAGE:${NC}
    $(basename "$0") [OPTIONS]

${YELLOW}OPTIONS:${NC}
    -r, --region REGION         AWS region (default: $DEFAULT_REGION)
    -e, --environment ENV       Environment (default: $DEFAULT_ENVIRONMENT)  
    -p, --project PROJECT       Project name (default: $DEFAULT_PROJECT)
    -b, --bucket BUCKET         Specific bucket name to destroy
    -t, --type TYPE             Bucket type to destroy (logs|traces|metrics|audit_logs|backups|backend-state|access-logs|all)
    
    --dry-run                   Show what would be deleted without actually deleting
    --force                     Skip safety checks and force deletion
    --skip-confirmation         Skip interactive confirmation prompts
    --backup                    Backup bucket contents before deletion
    --verbose                   Enable verbose output
    
    -h, --help                  Show this help message

${YELLOW}EXAMPLES:${NC}
    # Destroy all buckets (with confirmation)
    $(basename "$0") --type all
    
    # Destroy specific bucket type
    $(basename "$0") --type logs --region us-east-2
    
    # Destroy specific bucket by name
    $(basename "$0") --bucket myproject-logs-bucket
    
    # Dry run to see what would be deleted
    $(basename "$0") --type all --dry-run
    
    # Force delete with backup
    $(basename "$0") --type all --force --backup
    
    # Clean up access logs buckets created by enterprise features
    $(basename "$0") --type access-logs

${RED}WARNING:${NC} This script will PERMANENTLY DELETE S3 buckets and ALL their contents!
${RED}         Backend state buckets require special handling and confirmation!${NC}
${YELLOW}NOTE:${NC} Enterprise S3 configurations (analytics, metrics, notifications) are automatically cleaned up before bucket deletion.

EOF
}

# ============================================================================
# AWS Utility Functions  
# ============================================================================

check_aws_cli() {
    if ! command -v aws >/dev/null 2>&1; then
        fatal "AWS CLI is not installed. Please install it first."
    fi
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        fatal "AWS CLI is not configured or credentials are invalid."
    fi
    
    local identity
    identity=$(aws sts get-caller-identity --output text --query 'Account')
    log "Connected to AWS Account: ${identity}"
}

check_terraform_cli() {
    if ! command -v terraform >/dev/null 2>&1; then
        warn "Terraform CLI not found. Some features may not work."
        return 1
    fi
    return 0
}

get_bucket_region() {
    local bucket_name="$1"
    
    aws s3api get-bucket-location \
        --bucket "$bucket_name" \
        --output text \
        --query 'LocationConstraint' 2>/dev/null || echo "us-east-1"
}

bucket_exists() {
    local bucket_name="$1"
    aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null
}

# ============================================================================
# Auto-Detection Functions
# ============================================================================

auto_detect_project_config() {
    local detected_project="ohio-01"
    local detected_region="us-east-2"
    local detected_environment="production"
    
    # Try to detect from current terraform configuration
    local terraform_dirs=(
        "./infrastructure/s3-provisioning"
        "./examples/s3-infrastructure-setup"
        "./"
    )
    
    for terraform_dir in "${terraform_dirs[@]}"; do
        if [[ -f "$terraform_dir/main.tf" ]]; then
            # Extract values from terraform files
            detected_project=$(grep -E 'project_name.*=' "$terraform_dir/main.tf" | head -1 | sed 's/.*"\([^"]*\)".*/\1/' 2>/dev/null || echo "myproject")
            detected_region=$(grep -E 'region.*=' "$terraform_dir/main.tf" | head -1 | sed 's/.*"\([^"]*\)".*/\1/' 2>/dev/null || echo "us-east-1")
            detected_environment=$(grep -E 'environment.*=' "$terraform_dir/main.tf" | head -1 | sed 's/.*"\([^"]*\)".*/\1/' 2>/dev/null || echo "production")
            break
        fi
    done
    
    # Also try from AWS provider region if available
    if [[ "$detected_region" == "us-east-2" ]]; then
        local aws_region
        aws_region=$(aws configure get region 2>/dev/null || echo "us-east-1")
        if [[ -n "$aws_region" ]]; then
            detected_region="$aws_region"
        fi
    fi
    
    echo "$detected_project,$detected_region,$detected_environment"
}

# ============================================================================
# Bucket Discovery Functions
# ============================================================================

discover_terraform_buckets() {
    local terraform_dir="$1"
    local buckets=()
    
    if [[ ! -d "$terraform_dir" ]]; then
        warn "Terraform directory not found: $terraform_dir"
        return 0
    fi
    
    log "Discovering buckets from Terraform state in: $terraform_dir"
    
    if check_terraform_cli && [[ -f "$terraform_dir/.terraform/terraform.tfstate" ]]; then
        # Get buckets from Terraform state
        local state_buckets
        state_buckets=$(cd "$terraform_dir" && terraform state list 2>/dev/null | grep 'aws_s3_bucket\.' || true)
        
        while IFS= read -r resource; do
            if [[ -n "$resource" ]]; then
                local bucket_name
                bucket_name=$(cd "$terraform_dir" && terraform state show "$resource" 2>/dev/null | grep -E '^[ ]*bucket[ ]*=' | sed 's/.*= "\(.*\)"/\1/' || true)
                if [[ -n "$bucket_name" ]]; then
                    buckets+=("$bucket_name")
                fi
            fi
        done <<< "$state_buckets"
    fi
    
    printf '%s\n' "${buckets[@]}"
}

discover_project_buckets() {
    local project="$1"
    local region="$2"
    local environment="$3"
    
    log "Discovering buckets for project: $project, region: $region, environment: $environment"
    
    local patterns=(
        "${project}-${region}-*-${environment}"
        "${project}-terraform-state-${environment}"
        "${project}-*-${environment}"
    )
    
    local buckets=()
    for pattern in "${patterns[@]}"; do
        local matching_buckets
        matching_buckets=$(aws s3api list-buckets \
            --query "Buckets[?starts_with(Name, '$(echo "$pattern" | sed 's/\*//')')].[Name]" \
            --output text 2>/dev/null || true)
        
        while IFS= read -r bucket; do
            if [[ -n "$bucket" && "$bucket" != "None" ]]; then
                buckets+=("$bucket")
            fi
        done <<< "$matching_buckets"
    done
    
    # Remove duplicates
    printf '%s\n' "${buckets[@]}" | sort -u
}

# ============================================================================
# Bucket Backup Functions
# ============================================================================

backup_bucket_contents() {
    local bucket_name="$1"
    local backup_path="$BACKUP_DIR/$bucket_name"
    
    log "Backing up bucket contents: $bucket_name"
    
    mkdir -p "$backup_path"
    
    # Backup current versions
    log "Backing up current object versions..."
    aws s3 sync "s3://$bucket_name" "$backup_path/current/" \
        --storage-class STANDARD_IA || warn "Failed to backup some current objects"
    
    # Backup versioned objects if versioning is enabled
    if aws s3api get-bucket-versioning --bucket "$bucket_name" --query 'Status' --output text 2>/dev/null | grep -q "Enabled"; then
        log "Backing up object versions and delete markers..."
        
        aws s3api list-object-versions --bucket "$bucket_name" --output text \
            --query 'Versions[].[Key,VersionId]' > "$backup_path/versions.txt" || true
        
        aws s3api list-object-versions --bucket "$bucket_name" --output text \
            --query 'DeleteMarkers[].[Key,VersionId]' > "$backup_path/delete-markers.txt" || true
    fi
    
    # Backup bucket configuration
    mkdir -p "$backup_path/config"
    
    # Lifecycle configuration
    aws s3api get-bucket-lifecycle-configuration --bucket "$bucket_name" \
        > "$backup_path/config/lifecycle.json" 2>/dev/null || true
    
    # Versioning configuration
    aws s3api get-bucket-versioning --bucket "$bucket_name" \
        > "$backup_path/config/versioning.json" 2>/dev/null || true
    
    # Encryption configuration
    aws s3api get-bucket-encryption --bucket "$bucket_name" \
        > "$backup_path/config/encryption.json" 2>/dev/null || true
    
    # Replication configuration
    aws s3api get-bucket-replication --bucket "$bucket_name" \
        > "$backup_path/config/replication.json" 2>/dev/null || true
    
    # Object ownership controls
    aws s3api get-bucket-ownership-controls --bucket "$bucket_name" \
        > "$backup_path/config/ownership.json" 2>/dev/null || true
    
    # Access logging configuration
    aws s3api get-bucket-logging --bucket "$bucket_name" \
        > "$backup_path/config/access-logging.json" 2>/dev/null || true
    
    # CloudWatch metrics configurations
    aws s3api list-bucket-metrics-configurations --bucket "$bucket_name" \
        > "$backup_path/config/metrics.json" 2>/dev/null || true
    
    # Analytics configurations
    aws s3api list-bucket-analytics-configurations --bucket "$bucket_name" \
        > "$backup_path/config/analytics.json" 2>/dev/null || true
    
    # Inventory configurations
    aws s3api list-bucket-inventory-configurations --bucket "$bucket_name" \
        > "$backup_path/config/inventory.json" 2>/dev/null || true
    
    # Notification configurations
    aws s3api get-bucket-notification-configuration --bucket "$bucket_name" \
        > "$backup_path/config/notifications.json" 2>/dev/null || true
    
    # Transfer acceleration status
    aws s3api get-bucket-accelerate-configuration --bucket "$bucket_name" \
        > "$backup_path/config/acceleration.json" 2>/dev/null || true
    
    # Request payment configuration
    aws s3api get-bucket-request-payment --bucket "$bucket_name" \
        > "$backup_path/config/request-payment.json" 2>/dev/null || true
    
    # Tags
    aws s3api get-bucket-tagging --bucket "$bucket_name" \
        > "$backup_path/config/tags.json" 2>/dev/null || true
    
    success "Bucket backup completed: $backup_path"
}

# ============================================================================
# Bucket Destruction Functions
# ============================================================================

delete_bucket_objects() {
    local bucket_name="$1"
    local object_count
    
    log "Deleting all objects from bucket: $bucket_name"
    
    # Get total object count for progress tracking
    object_count=$(aws s3api list-objects-v2 --bucket "$bucket_name" --query 'KeyCount' --output text 2>/dev/null || echo "0")
    
    # Handle AWS CLI returning "None" instead of a number
    if [[ "$object_count" == "None" || "$object_count" == "" ]]; then
        object_count=0
    fi
    
    if [[ "$object_count" -gt 0 ]]; then
        log "Found $object_count current objects to delete..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            warn "[DRY RUN] Would delete $object_count objects from $bucket_name"
        else
            aws s3 rm "s3://$bucket_name" --recursive || warn "Some objects may not have been deleted"
        fi
    fi
}

delete_object_versions() {
    local bucket_name="$1"
    
    log "Deleting all object versions from bucket: $bucket_name"
    
    # Check if versioning is enabled
    local versioning_status
    versioning_status=$(aws s3api get-bucket-versioning --bucket "$bucket_name" --query 'Status' --output text 2>/dev/null || echo "None")
    
    if [[ "$versioning_status" != "Enabled" ]]; then
        log "Versioning not enabled for $bucket_name, skipping version deletion"
        return 0
    fi
    
    # Delete all versions and delete markers
    log "Deleting versioned objects and delete markers..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        local version_count delete_marker_count
        version_count=$(aws s3api list-object-versions --bucket "$bucket_name" --query 'length(Versions)' --output text 2>/dev/null || echo "0")
        delete_marker_count=$(aws s3api list-object-versions --bucket "$bucket_name" --query 'length(DeleteMarkers)' --output text 2>/dev/null || echo "0")
        
        # Handle AWS CLI returning "None" instead of numbers
        if [[ "$version_count" == "None" || "$version_count" == "" ]]; then
            version_count=0
        fi
        if [[ "$delete_marker_count" == "None" || "$delete_marker_count" == "" ]]; then
            delete_marker_count=0
        fi
        warn "[DRY RUN] Would delete $version_count object versions and $delete_marker_count delete markers from $bucket_name"
    else
        # Use AWS CLI to delete all versions
        aws s3api list-object-versions --bucket "$bucket_name" --output text \
            --query 'Versions[].[Key,VersionId]' | \
        while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" && "$key" != "None" && "$version_id" != "None" ]]; then
                aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version_id" >/dev/null || true
            fi
        done
        
        # Delete all delete markers
        aws s3api list-object-versions --bucket "$bucket_name" --output text \
            --query 'DeleteMarkers[].[Key,VersionId]' | \
        while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" && "$key" != "None" && "$version_id" != "None" ]]; then
                aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version_id" >/dev/null || true
            fi
        done
    fi
}

cleanup_enterprise_configurations() {
    local bucket_name="$1"
    
    log "Cleaning up enterprise configurations for bucket: $bucket_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "[DRY RUN] Would clean up enterprise configurations for $bucket_name"
        return 0
    fi
    
    # Remove analytics configurations
    log "  Removing analytics configurations..."
    aws s3api list-bucket-analytics-configurations --bucket "$bucket_name" --output text \
        --query 'AnalyticsConfigurationList[].Id' 2>/dev/null | \
    while read -r config_id; do
        if [[ -n "$config_id" && "$config_id" != "None" ]]; then
            aws s3api delete-bucket-analytics-configuration --bucket "$bucket_name" --id "$config_id" >/dev/null || true
        fi
    done
    
    # Remove inventory configurations
    log " Removing inventory configurations..."
    aws s3api list-bucket-inventory-configurations --bucket "$bucket_name" --output text \
        --query 'InventoryConfigurationList[].Id' 2>/dev/null | \
    while read -r config_id; do
        if [[ -n "$config_id" && "$config_id" != "None" ]]; then
            aws s3api delete-bucket-inventory-configuration --bucket "$bucket_name" --id "$config_id" >/dev/null || true
        fi
    done
    
    # Remove metrics configurations
    log " Removing metrics configurations..."
    aws s3api list-bucket-metrics-configurations --bucket "$bucket_name" --output text \
        --query 'MetricsConfigurationList[].Id' 2>/dev/null | \
    while read -r config_id; do
        if [[ -n "$config_id" && "$config_id" != "None" ]]; then
            aws s3api delete-bucket-metrics-configuration --bucket "$bucket_name" --id "$config_id" >/dev/null || true
        fi
    done
    
    # Remove notification configurations
    log " Removing notification configurations..."
    aws s3api put-bucket-notification-configuration --bucket "$bucket_name" --notification-configuration '{}' >/dev/null 2>&1 || true
    
    # Disable transfer acceleration
    log " Disabling transfer acceleration..."
    aws s3api put-bucket-accelerate-configuration --bucket "$bucket_name" \
        --accelerate-configuration Status=Suspended >/dev/null 2>&1 || true
    
    # Remove replication configuration
    log " Removing replication configuration..."
    aws s3api delete-bucket-replication --bucket "$bucket_name" >/dev/null 2>&1 || true
    
    # Remove lifecycle configuration
    log " Removing lifecycle configuration..."
    aws s3api delete-bucket-lifecycle --bucket "$bucket_name" >/dev/null 2>&1 || true
    
    # Remove access logging configuration
    log " Removing access logging configuration..."
    aws s3api put-bucket-logging --bucket "$bucket_name" --bucket-logging-status '{}' >/dev/null 2>&1 || true
    
    # Remove intelligent tiering configurations
    log " Removing intelligent tiering configurations..."
    aws s3api list-bucket-intelligent-tiering-configurations --bucket "$bucket_name" --output text \
        --query 'IntelligentTieringConfigurationList[].Id' 2>/dev/null | \
    while read -r config_id; do
        if [[ -n "$config_id" && "$config_id" != "None" ]]; then
            aws s3api delete-bucket-intelligent-tiering-configuration --bucket "$bucket_name" --id "$config_id" >/dev/null || true
        fi
    done
    
    # Remove CORS configuration
    log " Removing CORS configuration..."
    aws s3api delete-bucket-cors --bucket "$bucket_name" >/dev/null 2>&1 || true
    
    # Remove website configuration
    log " Removing website configuration..."
    aws s3api delete-bucket-website --bucket "$bucket_name" >/dev/null 2>&1 || true
    
    # Remove request payment configuration
    log " Removing request payment configuration..."
    aws s3api put-bucket-request-payment --bucket "$bucket_name" \
        --request-payment-configuration Payer=BucketOwner >/dev/null 2>&1 || true
    
    log "Enterprise configurations cleanup completed for $bucket_name"
}

handle_versioning_and_mfa_delete() {
    local bucket_name="$1"
    
    log "Handling versioning and MFA delete configurations..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "[DRY RUN] Would handle versioning and MFA delete for $bucket_name"
        return 0
    fi
    
    # Check if versioning is enabled
    local versioning_status
    versioning_status=$(aws s3api get-bucket-versioning --bucket "$bucket_name" --query 'Status' --output text 2>/dev/null || echo "None")
    
    if [[ "$versioning_status" == "Enabled" ]]; then
        log " Versioning is enabled, checking MFA delete status..."
        
        # Check MFA delete status
        local mfa_delete_status
        mfa_delete_status=$(aws s3api get-bucket-versioning --bucket "$bucket_name" --query 'MfaDelete' --output text 2>/dev/null || echo "None")
        
        if [[ "$mfa_delete_status" == "Enabled" ]]; then
            warn "  MFA Delete is ENABLED on bucket: $bucket_name"
            warn "  You may need to disable MFA Delete manually before bucket deletion"
            warn "  Use: aws s3api put-bucket-versioning --bucket $bucket_name --versioning-configuration Status=Enabled,MFADelete=Disabled --mfa 'SERIAL TOKEN'"
            
            # Try to suspend versioning (this might fail if MFA delete is enabled)
            log "  Attempting to suspend versioning..."
            if ! aws s3api put-bucket-versioning --bucket "$bucket_name" \
                --versioning-configuration Status=Suspended >/dev/null 2>&1; then
                warn "  Failed to suspend versioning (likely due to MFA Delete requirement)"
                warn "  Manual intervention required - see warnings above"
                return 1
            else
                success " Versioning suspended successfully"
            fi
        else
            log " MFA Delete not enabled, suspending versioning..."
            aws s3api put-bucket-versioning --bucket "$bucket_name" \
                --versioning-configuration Status=Suspended >/dev/null 2>&1 || warn "Failed to suspend versioning"
        fi
    else
        log "  Versioning not enabled on $bucket_name"
    fi
    
    return 0
}

abort_multipart_uploads() {
    local bucket_name="$1"
    
    log "Aborting incomplete multipart uploads for bucket: $bucket_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        local upload_count
        upload_count=$(aws s3api list-multipart-uploads --bucket "$bucket_name" --query 'length(Uploads)' --output text 2>/dev/null || echo "0")
        
        # Handle AWS CLI returning "None" instead of a number
        if [[ "$upload_count" == "None" || "$upload_count" == "" ]]; then
            upload_count=0
        fi
        warn "[DRY RUN] Would abort $upload_count multipart uploads from $bucket_name"
    else
        aws s3api list-multipart-uploads --bucket "$bucket_name" --output text \
            --query 'Uploads[].[Key,UploadId]' 2>/dev/null | \
        while read -r key upload_id; do
            if [[ -n "$key" && -n "$upload_id" && "$key" != "None" && "$upload_id" != "None" ]]; then
                aws s3api abort-multipart-upload --bucket "$bucket_name" --key "$key" --upload-id "$upload_id" >/dev/null || true
            fi
        done || true
    fi
}

destroy_bucket() {
    local bucket_name="$1"
    
    if ! bucket_exists "$bucket_name"; then
        warn "Bucket does not exist: $bucket_name"
        return 0
    fi
    
    log "=========================================="
    log "Destroying bucket: $bucket_name"
    log "=========================================="
    
    # Backup if requested
    if [[ "$BACKUP_BEFORE_DELETE" == "true" && "$DRY_RUN" != "true" ]]; then
        backup_bucket_contents "$bucket_name"
    fi
    
    # Step 1: Abort multipart uploads
    abort_multipart_uploads "$bucket_name"
    
    # Step 2: Delete all current objects
    delete_bucket_objects "$bucket_name"
    
    # Step 3: Delete all object versions and delete markers
    delete_object_versions "$bucket_name"
    
    # Step 4: Handle versioning and MFA delete configurations
    if ! handle_versioning_and_mfa_delete "$bucket_name"; then
        error "Failed to handle versioning/MFA delete for $bucket_name"
        error "Manual intervention may be required - check warnings above"
        return 1
    fi
    
    # Step 5: Clean up enterprise configurations that might prevent deletion
    cleanup_enterprise_configurations "$bucket_name"
    
    # Step 6: Final check and delete the bucket itself
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "[DRY RUN] Would delete bucket: $bucket_name"
    else
        log "Deleting empty bucket: $bucket_name"
        if aws s3api delete-bucket --bucket "$bucket_name" 2>/dev/null; then
            success "Successfully deleted bucket: $bucket_name"
        else
            error "Failed to delete bucket: $bucket_name"
            error "Possible causes:"
            error "  - MFA Delete enabled (requires manual intervention)"
            error "  - Bucket policy restrictions"
            error "  - Object lock enabled"
            error "  - Objects/versions still present"
            
            # Try to provide helpful diagnostics
            log "Running diagnostics for bucket: $bucket_name"
            local object_count
            object_count=$(aws s3api list-objects-v2 --bucket "$bucket_name" --query 'KeyCount' --output text 2>/dev/null || echo "unknown")
            log "  Current object count: $object_count"
            
            local version_count
            version_count=$(aws s3api list-object-versions --bucket "$bucket_name" --query 'length(Versions)' --output text 2>/dev/null || echo "unknown")
            log "  Object versions count: $version_count"
            
            return 1
        fi
    fi
}

# ============================================================================
# Special Handling for Backend State
# ============================================================================

destroy_backend_state_infrastructure() {
    local project="$1"
    local environment="$2"
    local region="$3"
    
    local bucket_name="${project}-terraform-state-${environment}"
    local region_short=$(echo "$region" | sed 's/-[0-9]*$//')
    local dynamodb_table="terraform-locks-${region_short}"
    
    warn "=========================================="
    warn "DESTROYING BACKEND STATE INFRASTRUCTURE"
    warn "=========================================="
    warn "Bucket: $bucket_name"
    warn "DynamoDB Table: $dynamodb_table"
    warn "Region: $region (short: $region_short)"
    warn ""
    error "CRITICAL WARNING"
    error "This will destroy your Terraform backend state!"
    error "You will lose the ability to manage infrastructure with Terraform!"
    error "Make sure you have exported/backed up your state files!"
    warn ""
    
    if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
        echo -e "${RED}Type 'DELETE-BACKEND-STATE' to confirm:${NC} "
        read -r confirmation
        
        if [[ "$confirmation" != "DELETE-BACKEND-STATE" ]]; then
            log "Backend state destruction cancelled."
            return 0
        fi
    fi
    
    # Backup Terraform state files
    if [[ "$DRY_RUN" != "true" ]]; then
        local state_backup_dir="$BACKUP_DIR/terraform-state"
        mkdir -p "$state_backup_dir"
        
        log "Backing up Terraform state files..."
        aws s3 sync "s3://$bucket_name" "$state_backup_dir/" || warn "Failed to backup some state files"
    fi
    
    # Destroy the bucket
    destroy_bucket "$bucket_name"
    
    # Destroy DynamoDB table
    if aws dynamodb describe-table --table-name "$dynamodb_table" >/dev/null 2>&1; then
        if [[ "$DRY_RUN" == "true" ]]; then
            warn "[DRY RUN] Would delete DynamoDB table: $dynamodb_table"
        else
            log "Deleting DynamoDB table: $dynamodb_table"
            aws dynamodb delete-table --table-name "$dynamodb_table" >/dev/null
            success "Successfully deleted DynamoDB table: $dynamodb_table"
        fi
    else
        warn "DynamoDB table does not exist: $dynamodb_table"
    fi
}

# ============================================================================
# Main Execution Functions
# ============================================================================

discover_and_destroy_access_logs_buckets() {
    local project="$1"
    local region="$2"
    local environment="$3"
    
    log "Discovering access logs buckets created by enterprise features..."
    
    local access_logs_pattern="${project}-${region}-.*-${environment}-access-logs"
    local access_logs_buckets
    
    # Find all access logs buckets matching our pattern
    access_logs_buckets=$(aws s3api list-buckets --query "Buckets[?contains(Name, '${project}') && contains(Name, 'access-logs')].Name" --output text 2>/dev/null || echo "")
    
    if [[ -n "$access_logs_buckets" ]]; then
        log "Found access logs buckets to destroy:"
        echo "$access_logs_buckets" | tr '\t' '\n' | while read -r bucket; do
            if [[ -n "$bucket" ]]; then
                log " $bucket"
            fi
        done
        
        echo "$access_logs_buckets" | tr '\t' '\n' | while read -r bucket; do
            if [[ -n "$bucket" ]]; then
                log "Destroying access logs bucket: $bucket"
                destroy_bucket "$bucket"
            fi
        done
    else
        log "No access logs buckets found matching pattern: $access_logs_pattern"
    fi
}

destroy_buckets_by_type() {
    local bucket_type="$1"
    local project="$2"
    local environment="$3"
    local region="$4"
    
    case "$bucket_type" in
        "logs")
            destroy_bucket "${project}-${region}-logs-${environment}"
            destroy_bucket "${project}-${region}-logs-${environment}-access-logs" 2>/dev/null || true
            ;;
        "traces")
            destroy_bucket "${project}-${region}-traces-${environment}"
            destroy_bucket "${project}-${region}-traces-${environment}-access-logs" 2>/dev/null || true
            ;;
        "backups")
            destroy_bucket "${project}-${region}-backups-${environment}"
            destroy_bucket "${project}-${region}-backups-${environment}-access-logs" 2>/dev/null || true
            ;;
        "metrics")
            destroy_bucket "${project}-${region}-metrics-${environment}"
            destroy_bucket "${project}-${region}-metrics-${environment}-access-logs" 2>/dev/null || true
            ;;
        "audit_logs")
            destroy_bucket "${project}-${region}-audit-logs-${environment}"
            destroy_bucket "${project}-${region}-audit-logs-${environment}-access-logs" 2>/dev/null || true
            ;;
        "backend-state")
            destroy_backend_state_infrastructure "$project" "$environment" "$region"
            ;;
        "access-logs")
            discover_and_destroy_access_logs_buckets "$project" "$region" "$environment"
            ;;
        "all")
            log "Destroying all buckets for project: $project"
            
            # Destroy main buckets first
            destroy_bucket "${project}-${region}-logs-${environment}"
            destroy_bucket "${project}-${region}-traces-${environment}"  
            destroy_bucket "${project}-${region}-backups-${environment}"
            destroy_bucket "${project}-${region}-metrics-${environment}"
            destroy_bucket "${project}-${region}-audit-logs-${environment}"
            
            # Discover and destroy any access logs buckets
            discover_and_destroy_access_logs_buckets "$project" "$region" "$environment"
            
            if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
                echo ""
                warn "Do you also want to destroy the backend state infrastructure? (y/N): "
                read -r destroy_backend
                if [[ "$destroy_backend" =~ ^[Yy]$ ]]; then
                    destroy_backend_state_infrastructure "$project" "$environment" "$region"
                fi
            fi
            ;;
        *)
            fatal "Unknown bucket type: $bucket_type. Use: logs|traces|metrics|audit_logs|backups|backend-state|access-logs|all"
            ;;
    esac
}

main() {
    local region="$DEFAULT_REGION"
    local environment="$DEFAULT_ENVIRONMENT"
    local project="$DEFAULT_PROJECT"
    local bucket_name=""
    local bucket_type=""
    local auto_detect=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--region)
                region="$2"
                shift 2
                ;;
            -e|--environment)
                environment="$2"
                shift 2
                ;;
            -p|--project)
                project="$2"
                shift 2
                ;;
            -b|--bucket)
                bucket_name="$2"
                shift 2
                ;;
            -t|--type)
                bucket_type="$2"
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
            --skip-confirmation)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --backup)
                BACKUP_BEFORE_DELETE=true
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
    
    # Auto-detect project configuration if using defaults
    if [[ "$region" == "$DEFAULT_REGION" && "$environment" == "$DEFAULT_ENVIRONMENT" && "$project" == "$DEFAULT_PROJECT" ]]; then
        log "Auto-detecting project configuration from Terraform files..."
        local detected_config
        detected_config=$(auto_detect_project_config)
        IFS=',' read -r project region environment <<< "$detected_config"
        log "Detected: project=$project, region=$region, environment=$environment"
        auto_detect=true
    fi
    
    # Validate required parameters
    if [[ -z "$bucket_name" && -z "$bucket_type" ]]; then
        error "Either --bucket or --type must be specified"
        show_usage
        exit 1
    fi
    
    log "=========================================="
    log "S3 Bucket Destruction Script"
    log "=========================================="
    log "Region: $region"
    log "Environment: $environment"
    log "Project: $project"
    log "Dry Run: $DRY_RUN"
    log "Backup Before Delete: $BACKUP_BEFORE_DELETE"
    
    if [[ -n "$bucket_name" ]]; then
        log "Target Bucket: $bucket_name"
    fi
    
    if [[ -n "$bucket_type" ]]; then
        log "Target Type: $bucket_type"
    fi
    
    log "=========================================="
    
    # Safety checks
    check_aws_cli
    
    if [[ "$FORCE_DELETE" != "true" && "$SKIP_CONFIRMATION" != "true" ]]; then
        echo ""
        warn "WARNING: This will PERMANENTLY DELETE S3 buckets and ALL their contents!"
        echo -e "${YELLOW}Are you sure you want to continue? (y/N):${NC} "
        read -r confirmation
        
        if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
            log "Operation cancelled."
            exit 0
        fi
    fi
    
    # Execute destruction
    if [[ -n "$bucket_name" ]]; then
        destroy_bucket "$bucket_name"
    elif [[ -n "$bucket_type" ]]; then
        destroy_buckets_by_type "$bucket_type" "$project" "$environment" "$region"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN COMPLETE - No actual changes were made"
    else
        success "Bucket destruction completed successfully!"
        if [[ "$BACKUP_BEFORE_DELETE" == "true" ]]; then
            success "Backups saved to: $BACKUP_DIR"
        fi
    fi
}

# Execute main function with all arguments
main "$@"