# Backend configuration for ${key_path}
# Generated automatically by terraform-backend-state module
bucket         = "${bucket_name}"
key            = "${key_path}"
region         = "${region}"
encrypt        = true
dynamodb_table = "${dynamodb_table}"