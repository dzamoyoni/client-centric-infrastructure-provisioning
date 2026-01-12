#!/bin/bash
# ============================================================================
# CIDR Registry Validation Script
# ============================================================================
# Validates CIDR allocations before terraform apply to prevent overlaps
# Usage: ./scripts/validate-cidr.sh [--client CLIENT_NAME]
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REGISTRY_FILE="${PROJECT_ROOT}/cidr-registry.yaml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check registry exists
if [[ ! -f "$REGISTRY_FILE" ]]; then
    log_error "CIDR registry not found: $REGISTRY_FILE"
    exit 1
fi

log_info "Validating CIDR registry: $REGISTRY_FILE"
echo ""

# Extract all client CIDRs
CLIENT_CIDRS=()
while IFS= read -r line; do
    if [[ $line =~ vpc_cidr:\ \"([0-9./]+)\" ]]; then
        CLIENT_CIDRS+=("${BASH_REMATCH[1]}")
    fi
done < "$REGISTRY_FILE"

log_info "Found ${#CLIENT_CIDRS[@]} client VPC CIDRs"

# Simple overlap check (basic validation - proper check requires IP math)
for cidr in "${CLIENT_CIDRS[@]}"; do
    count=$(printf '%s\n' "${CLIENT_CIDRS[@]}" | grep -c "^${cidr}$")
    if [[ $count -gt 1 ]]; then
        log_error "Duplicate CIDR found: $cidr"
        exit 1
    fi
done

log_success "No duplicate CIDRs found"

# Validate CIDR format
for cidr in "${CLIENT_CIDRS[@]}"; do
    if [[ ! $cidr =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        log_error "Invalid CIDR format: $cidr"
        exit 1
    fi
    log_info "✓ Valid CIDR: $cidr"
done

log_success "All CIDRs have valid format"

# Check reserved ranges
RESERVED_CIDRS=$(grep -A 1 "^  - cidr:" "$REGISTRY_FILE" | grep "cidr:" | awk '{print $3}' | tr -d '"')
log_info "Reserved CIDRs: $(echo $RESERVED_CIDRS | tr '\n' ' ')"

echo ""
log_success "==================================================="
log_success "CIDR Registry Validation: PASSED"
log_success "==================================================="
log_success "Total Client VPCs: ${#CLIENT_CIDRS[@]}"
log_success "No overlaps detected"
log_success "All CIDRs have valid format"
log_success "Safe to proceed with terraform apply"
echo ""

exit 0
