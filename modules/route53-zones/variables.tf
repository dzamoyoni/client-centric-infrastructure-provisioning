variable "hosted_zones" {
  description = "Map of hosted zones to create"
  type = map(object({
    comment       = string
    force_destroy = optional(bool, false)
    environment   = string
    client        = string
    vpc_associations = optional(list(object({
      vpc_id     = string
      vpc_region = string
    })))
    tags = optional(map(string), {})
  }))
  default = {}
}

variable "certificate_validations" {
  description = "Map of certificate validation records"
  type = map(object({
    name      = string
    type      = string
    value     = string
    zone_name = string
  }))
  default = {}
}

variable "custom_records" {
  description = "Map of custom DNS records to create"
  type = map(object({
    zone_name = string
    name      = string
    type      = string
    ttl       = number
    records   = list(string)
  }))
  default = {}
}

variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default     = {}
}
