variable "zone_id" {
  description = "Existing public hosted zone ID, without the /hostedzone/ prefix."
  type        = string
  validation {
    condition     = can(regex("^Z[A-Z0-9]+$", var.zone_id))
    error_message = "Supply the hosted zone ID without the /hostedzone/ prefix."
  }
}
variable "hostname" {
  description = "Application hostname managed in the zone, lowercase, without a trailing dot."
  type        = string
  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,63}$", var.hostname))
    error_message = "Use a lowercase fully qualified hostname without a trailing dot."
  }
}
locals {
  zone_arn = "arn:aws:route53:::hostedzone/${var.zone_id}"
  # The hostname carries the A/AAAA alias record. ExternalDNS (verified against v0.23.0) names
  # its TXT ownership records by prefixing the first label with the lowercase record type.
  # Record and TXT changes go in one Route 53 batch, so names and types share one statement.
  external_dns_names = [var.hostname, "a-${var.hostname}", "aaaa-${var.hostname}"]
  acme_challenge     = "_acme-challenge.${var.hostname}"
}
output "external_dns" {
  description = "ExternalDNS policy: change only the application A/AAAA alias and its TXT ownership records in one zone."
  value = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid = "ChangeApplicationRecords", Effect = "Allow", Action = "route53:ChangeResourceRecordSets", Resource = local.zone_arn,
        Condition = {
          "ForAllValues:StringEquals" = {
            "route53:ChangeResourceRecordSetsNormalizedRecordNames" = local.external_dns_names
            "route53:ChangeResourceRecordSetsRecordTypes"           = ["A", "AAAA", "TXT"]
          }
        }
      },
      { Sid = "ReadZoneRecords", Effect = "Allow", Action = "route53:ListResourceRecordSets", Resource = local.zone_arn },
      # ListHostedZones does not support resource-level scoping; it returns zone metadata only.
      { Sid = "DiscoverZones", Effect = "Allow", Action = "route53:ListHostedZones", Resource = "*" }
    ]
  })
}
output "cert_manager" {
  description = "cert-manager DNS-01 policy: manage only the hostname's _acme-challenge TXT record in one zone."
  value = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid = "ChangeAcmeChallenge", Effect = "Allow", Action = "route53:ChangeResourceRecordSets", Resource = local.zone_arn,
        Condition = {
          "ForAllValues:StringEquals" = {
            "route53:ChangeResourceRecordSetsNormalizedRecordNames" = [local.acme_challenge]
            "route53:ChangeResourceRecordSetsRecordTypes"           = ["TXT"]
          }
        }
      },
      { Sid = "ReadZoneRecords", Effect = "Allow", Action = "route53:ListResourceRecordSets", Resource = local.zone_arn },
      # Change IDs are not known in advance; GetChange only reports propagation status.
      { Sid = "PollChanges", Effect = "Allow", Action = "route53:GetChange", Resource = "arn:aws:route53:::change/*" }
    ]
  })
}
output "external_dns_record_names" {
  description = "Record names ExternalDNS may change; configure the controller to stay within them."
  value       = local.external_dns_names
}
output "acme_challenge_record" {
  description = "The only record name cert-manager may change."
  value       = local.acme_challenge
}
