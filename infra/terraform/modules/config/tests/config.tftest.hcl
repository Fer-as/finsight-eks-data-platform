# Provider-free unit tests. All run blocks use plan and create no resources.
run "merge_sections" {
  command = plan
  variables { override_file = "tests/valid.json" }
  assert {
    condition     = output.value.eks.desired_size == 3 && output.value.eks.min_size == 2
    error_message = "Section overrides must retain unspecified defaults."
  }
  assert {
    condition     = output.tags.Project == "finsight" && output.tags.Team == "test"
    error_message = "Reserved tags must take precedence while retaining custom tags."
  }
}
run "reject_missing_account" {
  command = plan
  variables { override_file = "tests/nonexistent.json" }
  expect_failures = [output.value]
}
run "reject_wrong_region" {
  command = plan
  variables { override_file = "tests/wrong-region.json" }
  expect_failures = [output.value]
}
run "reject_shared_state_data_bucket" {
  command = plan
  variables { override_file = "tests/same-bucket.json" }
  expect_failures = [output.value]
}
