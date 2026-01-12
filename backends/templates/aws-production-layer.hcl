# Template for AWS production layer backend
# Replace REGION and LAYER with actual values
bucket         = "terraform-state-REGION-production"
key            = "providers/aws/regions/REGION/layers/LAYER/production/terraform.tfstate"
region         = "REGION"
encrypt        = true
dynamodb_table = "terraform-locks-REGION"
