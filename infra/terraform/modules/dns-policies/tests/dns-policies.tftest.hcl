# Provider-free unit tests. All run blocks use plan and create no resources.
variables {
  zone_id  = "Z0123456789TESTZONE"
  hostname = "eks.example.com"
}
run "external_dns_scoped_to_zone_and_names" {
  command = plan
  assert {
    condition     = jsondecode(output.external_dns).Statement[0].Resource == "arn:aws:route53:::hostedzone/Z0123456789TESTZONE"
    error_message = "ExternalDNS may change records only in the one hosted zone."
  }
  assert {
    condition = jsondecode(output.external_dns).Statement[0].Condition["ForAllValues:StringEquals"]["route53:ChangeResourceRecordSetsNormalizedRecordNames"] == [
      "eks.example.com", "a-eks.example.com", "aaaa-eks.example.com"
    ]
    error_message = "ExternalDNS record names must be the hostname and its TXT ownership names only."
  }
  assert {
    condition     = jsondecode(output.external_dns).Statement[0].Condition["ForAllValues:StringEquals"]["route53:ChangeResourceRecordSetsRecordTypes"] == ["A", "AAAA", "TXT"]
    error_message = "ExternalDNS may change only A, AAAA and TXT records."
  }
  assert {
    condition = alltrue([
      for s in jsondecode(output.external_dns).Statement : s.Resource != "*" if s.Action != "route53:ListHostedZones"
    ])
    error_message = "Only the unscopable ListHostedZones action may use a wildcard resource."
  }
}
run "cert_manager_limited_to_acme_challenge" {
  command = plan
  assert {
    condition = (
      jsondecode(output.cert_manager).Statement[0].Resource == "arn:aws:route53:::hostedzone/Z0123456789TESTZONE" &&
      jsondecode(output.cert_manager).Statement[0].Condition["ForAllValues:StringEquals"]["route53:ChangeResourceRecordSetsNormalizedRecordNames"] == ["_acme-challenge.eks.example.com"] &&
      jsondecode(output.cert_manager).Statement[0].Condition["ForAllValues:StringEquals"]["route53:ChangeResourceRecordSetsRecordTypes"] == ["TXT"]
    )
    error_message = "cert-manager may change only the _acme-challenge TXT record in the one zone."
  }
  assert {
    condition     = jsondecode(output.cert_manager).Statement[2].Resource == "arn:aws:route53:::change/*"
    error_message = "GetChange must be limited to change resources."
  }
  assert {
    condition     = !strcontains(output.cert_manager, "ListHostedZones")
    error_message = "cert-manager must use a fixed hostedZoneID instead of zone discovery."
  }
}
run "policies_do_not_overlap" {
  command = plan
  assert {
    condition     = length(setintersection(output.external_dns_record_names, [output.acme_challenge_record])) == 0
    error_message = "ExternalDNS and cert-manager must not be able to change each other's records."
  }
}
run "reject_prefixed_zone_id" {
  command = plan
  variables { zone_id = "/hostedzone/Z0123456789TESTZONE" }
  expect_failures = [var.zone_id]
}
run "reject_trailing_dot_hostname" {
  command = plan
  variables { hostname = "eks.example.com." }
  expect_failures = [var.hostname]
}
run "reject_uppercase_hostname" {
  command = plan
  variables { hostname = "EKS.example.com" }
  expect_failures = [var.hostname]
}
