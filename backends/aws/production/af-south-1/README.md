# Backend Configuration for af-south-1 Production

## ⚠️ IMPORTANT: Customize These Files

The .hcl files in this directory contain placeholder values that need to be updated:

1. **Update bucket names**: Replace "your-terraform-state-bucket" with your actual S3 bucket
2. **Update DynamoDB table**: Replace "terraform-state-lock" with your actual table name

## Files to Update:
- foundation.hcl
- platform.hcl  
- databases.hcl
- observability.hcl

## Usage:
```bash
terraform init -backend-config=../../../../../../backends/aws/production/af-south-1/platform.hcl
```
