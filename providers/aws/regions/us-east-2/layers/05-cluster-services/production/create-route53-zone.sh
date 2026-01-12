#!/bin/bash
# Script to create Route 53 hosted zone for external-dns
# Usage: ./create-route53-zone.sh <domain-name>

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <domain-name>"
  echo "Example: $0 example.com"
  exit 1
fi

DOMAIN_NAME=$1
CALLER_REFERENCE="ohio-01-eks-$(date +%s)"
PROJECT_NAME="ohio-01-eks"
ENVIRONMENT="production"
REGION="us-east-2"

echo "Creating Route 53 hosted zone for domain: $DOMAIN_NAME"

# Create the hosted zone
ZONE_OUTPUT=$(aws route53 create-hosted-zone \
  --name "$DOMAIN_NAME" \
  --caller-reference "$CALLER_REFERENCE" \
  --hosted-zone-config Comment="Hosted zone for $PROJECT_NAME $ENVIRONMENT" \
  --output json)

# Extract zone ID
ZONE_ID=$(echo "$ZONE_OUTPUT" | jq -r '.HostedZone.Id' | sed 's|/hostedzone/||')

# Tag the hosted zone
aws route53 change-tags-for-resource \
  --resource-type hostedzone \
  --resource-id "$ZONE_ID" \
  --add-tags \
    Key=Name,Value="$DOMAIN_NAME" \
    Key=Project,Value="$PROJECT_NAME" \
    Key=Environment,Value="$ENVIRONMENT" \
    Key=ManagedBy,Value="Terraform" \
    Key=Region,Value="$REGION" \
    Key=Layer,Value="SharedServices"

echo ""
echo "Route 53 Hosted Zone Created Successfully!"
echo "=============================================="
echo "Domain: $DOMAIN_NAME"
echo "Zone ID: $ZONE_ID"
echo ""
echo "Name Servers:"
echo "$ZONE_OUTPUT" | jq -r '.DelegationSet.NameServers[]' | sed 's/^/  - /'
echo ""
echo "Next Steps:"
echo "1. Update your domain registrar with the name servers listed above"
echo "2. Add the Zone ID to terraform.tfvars:"
echo "   dns_zone_ids = [\"$ZONE_ID\"]"
echo "3. Add domain filters to terraform.tfvars:"
echo "   external_dns_domain_filters = [\"$DOMAIN_NAME\"]"
echo "4. Run terraform plan and apply to deploy external-dns"
