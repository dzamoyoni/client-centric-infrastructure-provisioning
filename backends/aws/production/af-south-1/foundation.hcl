# Backend configuration for af-south-1 foundation layer
bucket         = "cptwn-terraform-state-ezra"
key            = "providers/aws/regions/af-south-1/layers/01-foundation/production/terraform.tfstate"
region         = "af-south-1"
encrypt        = true
dynamodb_table = "terraform-locks-af-south"
