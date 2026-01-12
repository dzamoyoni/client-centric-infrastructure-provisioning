# Route53 Hosted Zones Module
# Creates and manages DNS zones for different clients and environments

resource "aws_route53_zone" "zones" {
  for_each = var.hosted_zones

  name          = each.key
  comment       = each.value.comment
  force_destroy = each.value.force_destroy

  dynamic "vpc" {
    for_each = each.value.vpc_associations != null ? each.value.vpc_associations : []
    content {
      vpc_id     = vpc.value.vpc_id
      vpc_region = vpc.value.vpc_region
    }
  }

  tags = merge(
    var.tags,
    each.value.tags,
    {
      Name        = each.key
      Environment = each.value.environment
      Client      = each.value.client
    }
  )
}

# Optional: Create certificate validation records for ACM certificates
resource "aws_route53_record" "cert_validation" {
  for_each = var.certificate_validations

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.value]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.zones[each.value.zone_name].zone_id
}

# Optional: Create custom DNS records
resource "aws_route53_record" "custom_records" {
  for_each = var.custom_records

  zone_id = aws_route53_zone.zones[each.value.zone_name].zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.records

  depends_on = [aws_route53_zone.zones]
}
