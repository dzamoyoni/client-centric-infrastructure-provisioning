# Backend configuration for af-south-1 observability layer
bucket         = "cptwn-terraform-state-ezra"
key            = "providers/aws/regions/af-south-1/layers/03.5-observability/production/terraform.tfstate"
region         = "af-south-1"
encrypt        = true
dynamodb_table = "terraform-locks-af-south"
