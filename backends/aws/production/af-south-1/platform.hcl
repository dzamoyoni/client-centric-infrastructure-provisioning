# Backend configuration for af-south-1 platform layer
bucket         = "cptwn-terraform-state-ezra"
key            = "regions/af-south-1/layers/02-platform/production/terraform.tfstate"
region         = "af-south-1"
encrypt        = true
dynamodb_table = "terraform-locks-af-south"
