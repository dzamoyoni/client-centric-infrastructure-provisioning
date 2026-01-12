#!/bin/bash

# ============================================================================
# S3 Security Verification Script
# ============================================================================
# This script verifies that S3 buckets created by our system are properly
# secured and private.
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

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

log_header() {
    echo -e "${CYAN}╭─ $1${NC}"
}

# Check if AWS CLI is available
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed or not in PATH"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured or invalid"
    exit 1
fi

log_header "S3 Bucket Security Verification"

# Find buckets related to our infrastructure
log_info "Finding S3 buckets related to our infrastructure..."

# Get all buckets and filter for our patterns
BUCKETS=$(aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | grep -E '(terraform-state|logs|traces|metrics|audit)' || true)

if [[ -z "$BUCKETS" ]]; then
    log_warning "No S3 buckets found matching our infrastructure patterns"
    log_info "Patterns checked: terraform-state, logs, traces, metrics, audit"
    echo
    log_info "All buckets in your account:"
    aws s3api list-buckets --query 'Buckets[].Name' --output table
    exit 0
fi

echo
log_success "Found $(echo "$BUCKETS" | wc -l) bucket(s) to verify:"
echo "$BUCKETS" | while read bucket; do
    echo " $bucket"
done

echo

# Verify each bucket
TOTAL_BUCKETS=0
SECURE_BUCKETS=0
ISSUES_FOUND=0

echo "$BUCKETS" | while read BUCKET_NAME; do
    if [[ -n "$BUCKET_NAME" ]]; then
        TOTAL_BUCKETS=$((TOTAL_BUCKETS + 1))
        
        log_header "Verifying bucket: $BUCKET_NAME"
        
        BUCKET_SECURE=true
        
        # 1. Check Public Access Block
        log_info "Checking Public Access Block..."
        PAB_STATUS=$(aws s3api get-public-access-block --bucket "$BUCKET_NAME" --query 'PublicAccessBlockConfiguration' --output json 2>/dev/null || echo "{}")
        
        BLOCK_PUBLIC_ACLS=$(echo "$PAB_STATUS" | jq -r '.BlockPublicAcls // false')
        BLOCK_PUBLIC_POLICY=$(echo "$PAB_STATUS" | jq -r '.BlockPublicPolicy // false')
        IGNORE_PUBLIC_ACLS=$(echo "$PAB_STATUS" | jq -r '.IgnorePublicAcls // false')
        RESTRICT_PUBLIC_BUCKETS=$(echo "$PAB_STATUS" | jq -r '.RestrictPublicBuckets // false')
        
        if [[ "$BLOCK_PUBLIC_ACLS" == "true" && "$BLOCK_PUBLIC_POLICY" == "true" && "$IGNORE_PUBLIC_ACLS" == "true" && "$RESTRICT_PUBLIC_BUCKETS" == "true" ]]; then
            log_success " Public Access Block: ENABLED (All 4 settings active)"
        else
            log_error "     Public Access Block: PARTIALLY ENABLED"
            log_error "     BlockPublicAcls: $BLOCK_PUBLIC_ACLS"
            log_error "     BlockPublicPolicy: $BLOCK_PUBLIC_POLICY" 
            log_error "     IgnorePublicAcls: $IGNORE_PUBLIC_ACLS"
            log_error "     RestrictPublicBuckets: $RESTRICT_PUBLIC_BUCKETS"
            BUCKET_SECURE=false
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
        
        # 2. Check Server-Side Encryption
        log_info "Checking Server-Side Encryption..."
        ENCRYPTION=$(aws s3api get-bucket-encryption --bucket "$BUCKET_NAME" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault' --output json 2>/dev/null || echo "{}")
        
        SSE_ALGORITHM=$(echo "$ENCRYPTION" | jq -r '.SSEAlgorithm // "none"')
        
        if [[ "$SSE_ALGORITHM" == "AES256" || "$SSE_ALGORITHM" == "aws:kms" ]]; then
            log_success " Server-Side Encryption: ENABLED ($SSE_ALGORITHM)"
        else
            log_error "  Server-Side Encryption: NOT ENABLED"
            BUCKET_SECURE=false
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
        
        # 3. Check Versioning
        log_info "Checking Versioning..."
        VERSIONING=$(aws s3api get-bucket-versioning --bucket "$BUCKET_NAME" --query 'Status' --output text 2>/dev/null || echo "Suspended")
        
        if [[ "$VERSIONING" == "Enabled" ]]; then
            log_success " Versioning: ENABLED"
        else
            log_warning "  ⚠️  Versioning: $VERSIONING (May be intentional for non-critical buckets)"
        fi
        
        # 4. Check Bucket Policy for public access
        log_info "Checking Bucket Policy..."
        BUCKET_POLICY=$(aws s3api get-bucket-policy --bucket "$BUCKET_NAME" --output text --query 'Policy' 2>/dev/null || echo "")
        
        if [[ -n "$BUCKET_POLICY" ]]; then
            # Check if policy contains public access
            if echo "$BUCKET_POLICY" | jq -r '.Statement[].Principal' 2>/dev/null | grep -q '"*"'; then
                log_error "  Bucket Policy: CONTAINS PUBLIC ACCESS"
                BUCKET_SECURE=false
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
            else
                log_success " Bucket Policy: NO PUBLIC ACCESS DETECTED"
            fi
        else
            log_info " Bucket Policy: NOT SET (Default private access)"
        fi
        
        # 5. Check Object Ownership Controls
        log_info " Checking Object Ownership Controls..."
        OWNERSHIP=$(aws s3api get-bucket-ownership-controls --bucket "$BUCKET_NAME" --query 'OwnershipControls.Rules[0].ObjectOwnership' --output text 2>/dev/null || echo "ObjectWriter")
        
        if [[ "$OWNERSHIP" == "BucketOwnerEnforced" ]]; then
            log_success " Object Ownership: BUCKET OWNER ENFORCED (Enhanced security)"
        elif [[ "$OWNERSHIP" == "BucketOwnerPreferred" ]]; then
            log_warning "   Object Ownership: BUCKET OWNER PREFERRED (Consider enforced for better security)"
        else
            log_warning "  Object Ownership: OBJECT WRITER (Default legacy mode)"
        fi
        
        # 6. Check Access Logging
        log_info "Checking Access Logging..."
        LOGGING=$(aws s3api get-bucket-logging --bucket "$BUCKET_NAME" --query 'LoggingEnabled.TargetBucket' --output text 2>/dev/null || echo "")
        
        if [[ -n "$LOGGING" && "$LOGGING" != "None" ]]; then
            log_success " Access Logging: ENABLED (Target: $LOGGING)"
        else
            log_info "  Access Logging: NOT ENABLED (Consider enabling for audit trails)"
        fi
        
        # 7. Check ACL for public access  
        log_info "Checking Access Control List (ACL)..."
        ACL=$(aws s3api get-bucket-acl --bucket "$BUCKET_NAME" --output json 2>/dev/null || echo "{}")
        
        PUBLIC_READ=$(echo "$ACL" | jq -r '.Grants[] | select(.Grantee.URI == "http://acs.amazonaws.com/groups/global/AllUsers" or .Grantee.URI == "http://acs.amazonaws.com/groups/global/AuthenticatedUsers") | .Permission' 2>/dev/null || echo "")
        
        if [[ -n "$PUBLIC_READ" ]]; then
            log_error " ACL: PUBLIC ACCESS DETECTED ($PUBLIC_READ)"
            BUCKET_SECURE=false
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        else
            log_success " ACL: NO PUBLIC ACCESS"
        fi
        
        # 8. Check CloudWatch Metrics
        log_info "Checking CloudWatch Metrics..."
        METRICS=$(aws s3api list-bucket-metrics-configurations --bucket "$BUCKET_NAME" --query 'MetricsConfigurationList[0].Id' --output text 2>/dev/null || echo "")
        
        if [[ -n "$METRICS" && "$METRICS" != "None" ]]; then
            log_success "CloudWatch Metrics: ENABLED ($METRICS)"
        else
            log_info "CloudWatch Metrics: NOT ENABLED (Consider enabling for monitoring)"
        fi
        
        # Summary for this bucket
        echo
        if [[ "$BUCKET_SECURE" == "true" ]]; then
            log_success "BUCKET SECURE: $BUCKET_NAME is properly private and secure"
            SECURE_BUCKETS=$((SECURE_BUCKETS + 1))
        else
            log_error "BUCKET INSECURE: $BUCKET_NAME has security issues that need attention"
        fi
        echo "─────────────────────────────────────────────────────────────────"
        echo
    fi
done

# Overall Summary
log_header "Security Verification Summary"

if [[ $ISSUES_FOUND -eq 0 ]]; then
    log_success "ALL BUCKETS ARE SECURE!"
    log_success "   $SECURE_BUCKETS/$TOTAL_BUCKETS buckets passed all security checks"
    log_success "   No public access detected"
    log_success "   Encryption enabled on all buckets"
    log_success "   Public access blocks properly configured"
else
    log_error "!!! SECURITY ISSUES DETECTED !!!"
    log_error "   $ISSUES_FOUND security issue(s) found"
    log_error "   Please review and fix the issues above"
    echo
    log_warning "To fix public access issues:"
    echo "   aws s3api put-public-access-block --bucket BUCKET_NAME --public-access-block-configuration 'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'"
    echo
    log_warning "To enable server-side encryption:"
    echo "   aws s3api put-bucket-encryption --bucket BUCKET_NAME --server-side-encryption-configuration '{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"AES256\"}}]}'"
fi

echo
log_info "For detailed security best practices, see: AWS S3 Security Best Practices"
log_info "Our security settings are defined in: modules/s3-bucket-management/main.tf"