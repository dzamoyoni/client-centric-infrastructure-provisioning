#!/bin/bash
# ============================================================================
# Client Metadata Consistency Validator
# ============================================================================
# Purpose: Validates that client metadata is consistent across all layers
# Usage: ./scripts/validate-client-metadata.sh <client-name>
# Example: ./scripts/validate-client-metadata.sh acme-corp
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CLIENT_NAME="$1"
REGION="us-east-2"
ENVIRONMENT="production"

if [ -z "$CLIENT_NAME" ]; then
  echo -e "${RED}Error: Client name required${NC}"
  echo "Usage: $0 <client-name>"
  echo "Example: $0 acme-corp"
  exit 1
fi

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}Client Metadata Consistency Check${NC}"
echo -e "${BLUE}Client: ${CLIENT_NAME}${NC}"
echo -e "${BLUE}==================================================${NC}"
echo

# Array of layers
LAYERS=(
  "01-foundation"
  "02-platform"
  "03-database"
  "04-standalone-compute"
  "05-cluster-services"
  "06-observability"
)

# Function to extract metadata from clients.auto.tfvars
extract_metadata() {
  local layer=$1
  local file="providers/aws/regions/${REGION}/layers/${layer}/${ENVIRONMENT}/clients.auto.tfvars"
  
  if [ ! -f "$file" ]; then
    echo "FILE_NOT_FOUND"
    return
  fi
  
  # Check if client exists in file
  if ! grep -q "\"${CLIENT_NAME}\"" "$file" && ! grep -q "${CLIENT_NAME} = {" "$file"; then
    echo "CLIENT_NOT_FOUND"
    return
  fi
  
  # Extract metadata block (simplified - assumes standard formatting)
  awk "/\"${CLIENT_NAME}\"|${CLIENT_NAME} = {/,/^  }/" "$file" | \
    awk '/metadata = {/,/^    }/' | \
    grep -E "(full_name|industry|contact_email|compliance|cost_center|business_unit)" | \
    sed 's/^[[:space:]]*//' | \
    sort
}

# Store metadata from each layer
declare -A layer_metadata

echo -e "${YELLOW}📋 Extracting metadata from all layers...${NC}"
echo

for layer in "${LAYERS[@]}"; do
  metadata=$(extract_metadata "$layer")
  
  if [ "$metadata" = "FILE_NOT_FOUND" ]; then
    echo -e "${RED}❌ ${layer}: clients.auto.tfvars not found${NC}"
    layer_metadata[$layer]="NOT_FOUND"
  elif [ "$metadata" = "CLIENT_NOT_FOUND" ]; then
    echo -e "${YELLOW}⚠️  ${layer}: Client '${CLIENT_NAME}' not defined${NC}"
    layer_metadata[$layer]="NOT_DEFINED"
  else
    echo -e "${GREEN}✅ ${layer}: Metadata found${NC}"
    layer_metadata[$layer]="$metadata"
  fi
done

echo
echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}Consistency Check${NC}"
echo -e "${BLUE}==================================================${NC}"
echo

# Find first valid metadata to use as reference
reference_metadata=""
reference_layer=""

for layer in "${LAYERS[@]}"; do
  if [ "${layer_metadata[$layer]}" != "NOT_FOUND" ] && [ "${layer_metadata[$layer]}" != "NOT_DEFINED" ]; then
    reference_metadata="${layer_metadata[$layer]}"
    reference_layer="$layer"
    break
  fi
done

if [ -z "$reference_metadata" ]; then
  echo -e "${RED}❌ ERROR: No valid metadata found in any layer${NC}"
  exit 1
fi

echo -e "${BLUE}Using ${reference_layer} as reference${NC}"
echo

# Compare all layers against reference
inconsistent=0
for layer in "${LAYERS[@]}"; do
  if [ "${layer_metadata[$layer]}" = "NOT_FOUND" ] || [ "${layer_metadata[$layer]}" = "NOT_DEFINED" ]; then
    continue
  fi
  
  if [ "${layer_metadata[$layer]}" = "$reference_metadata" ]; then
    echo -e "${GREEN}✅ ${layer}: Metadata matches reference${NC}"
  else
    echo -e "${RED}❌ ${layer}: Metadata DIFFERS from reference${NC}"
    inconsistent=1
    
    echo -e "${YELLOW}   Differences:${NC}"
    diff <(echo "$reference_metadata") <(echo "${layer_metadata[$layer]}") | head -20 || true
    echo
  fi
done

echo
echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}==================================================${NC}"
echo

if [ $inconsistent -eq 0 ]; then
  echo -e "${GREEN}✅ SUCCESS: All metadata is consistent across layers${NC}"
  exit 0
else
  echo -e "${RED}❌ FAILURE: Metadata inconsistencies detected${NC}"
  echo -e "${YELLOW}Action Required: Update metadata in inconsistent layers to match${NC}"
  exit 1
fi
