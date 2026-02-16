# ============================================================================
# Shared Configuration Module - Variables
# ============================================================================

variable "layer_id" {
  description = "Layer identifier (e.g., '01-foundation', '02-platform')"
  type        = string
  
  validation {
    condition = contains([
      "00-bootstrap",
      "01-foundation",
      "01.5-transit-gateway",
      "02-platform",
      "03-database",
      "04-standalone-compute",
      "05-cluster-services",
      "06-observability"
    ], var.layer_id)
    error_message = "Layer ID must be a valid infrastructure layer."
  }
}
