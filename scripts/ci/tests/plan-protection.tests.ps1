#Requires -Version 7
# Synthetic security regression tests for the issue #11 plan protection scripts. No AWS, no
# Terraform, no GitHub: synthetic `terraform show -json` fixtures, a random "plan" file and
# throwaway age keys generated here. Requires PowerShell 7 on Linux and `age`/`age-keygen` on PATH
# (CI installs them with .github/actions/install-age). Exits 1 if any check fails.
$ErrorActionPreference = "Stop"
$pass = 0; $fail = 0; $log = [Text.StringBuilder]::new()
function Check($name, $cond) { if ($cond) { $script:pass++; "PASS $name" } else { $script:fail++; "FAIL $name" } }
function Throws($name, [scriptblock]$sb, $pattern) {
    try { $o = & $sb *>&1 | Out-String; [void]$log.Append($o); Check "$name (expected refusal)" $false }
    catch { [void]$log.Append($_.Exception.Message); Check "$name -> refused" ($_.Exception.Message -match $pattern) }
}
function Run([scriptblock]$sb) { $o = & $sb *>&1 | Out-String; [void]$log.Append($o); $o }

$ci = Split-Path -Parent $PSScriptRoot
$P = Join-Path $ci "protect-terraform-plan.ps1"; $U = Join-Path $ci "unprotect-terraform-plan.ps1"; $S = Join-Path $ci "summarize-terraform-plan.ps1"
$T = Join-Path ([IO.Path]::GetTempPath()) ("plan-protection-tests-" + [guid]::NewGuid().ToString("N")); New-Item -ItemType Directory -Force $T | Out-Null
$savedEnv = @{}; foreach ($k in "GITHUB_REPOSITORY", "GITHUB_SHA", "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT", "RUNNER_TEMP", "GITHUB_OUTPUT", "GITHUB_STEP_SUMMARY") { $savedEnv[$k] = [Environment]::GetEnvironmentVariable($k) }
try {
    # Throwaway keys.
    foreach ($n in "ci", "reviewer", "other") { age-keygen -o "$T/$n.key" 2>$null; if ($LASTEXITCODE -ne 0) { throw "age-keygen failed" } }
    $ciRec = (age-keygen -y "$T/ci.key").Trim(); $revRec = (age-keygen -y "$T/reviewer.key").Trim()
    $ciId = (Get-Content "$T/ci.key" | Where-Object { $_ -like "AGE-SECRET-KEY-*" }).Trim(); $otherId = (Get-Content "$T/other.key" | Where-Object { $_ -like "AGE-SECRET-KEY-*" }).Trim()

    # Fake platform root, private config and plan.
    $root = "$T/w/infra/terraform/environments/dev/platform"; New-Item -ItemType Directory -Force $root, "$T/rt" | Out-Null
    "bucket = `"fake-state`"`nkey = `"dev/platform/terraform.tfstate`"`nregion = `"eu-west-2`"" | Set-Content "$root/backend.hcl"
    'provider "registry.terraform.io/hashicorp/aws" { version = "6.59.0" }' | Set-Content "$root/.terraform.lock.hcl"
    $cfg = "$T/local.json"; '{"account_id":"123456789012","eks":{"compatibility_verified":true}}' | Set-Content $cfg
    $bytes = [byte[]]::new(4096); [Random]::new(7).NextBytes($bytes); [IO.File]::WriteAllBytes("$root/platform.tfplan", $bytes)
    $marker = "SENSITIVE-PLAN-VALUE-123456789012"; "  # aws_route.internet will be updated`n  ~ cidr = `"$marker`"" | Set-Content "$T/review.txt"
    function PlanJson([object[]]$changes) {
        @{ format_version = "1.2"; terraform_version = "1.16.2"; output_changes = @{}; resource_changes = @($changes | ForEach-Object {
            $ch = @{ actions = $_.actions; after = @{ cidr_block = $marker } }; if ($_.importing) { $ch.importing = @{ id = "x" } }
            @{ address = $_.address; mode = "managed"; type = $_.type; change = $ch } }) } | ConvertTo-Json -Depth 10
    }
    function C($address, $type, [string[]]$actions, [switch]$Import) { @{ address = $address; type = $type; actions = $actions; importing = [bool]$Import } }
    $route = 'module.network.aws_route.internet'; $vpc = 'module.network.aws_vpc.this'; $eks = 'module.eks.aws_eks_cluster.this'
    PlanJson @((C $route aws_route update), (C 'module.eks.aws_eks_addon.workload["coredns"]' aws_eks_addon create)) | Set-Content "$T/safe.json"
    PlanJson @((C $route aws_route delete)) | Set-Content "$T/destroy.json"
    PlanJson @((C 'module.network.aws_subnet.private["eu-west-2a"]' aws_subnet delete, create)) | Set-Content "$T/replace.json"
    PlanJson @((C 'module.network.aws_subnet.private["eu-west-2a"]' aws_subnet create, delete)) | Set-Content "$T/replace2.json"
    PlanJson @((C $route aws_route forget)) | Set-Content "$T/forget.json"
    PlanJson @((C $route aws_route frobnicate)) | Set-Content "$T/unknown.json"
    PlanJson @((C $route aws_route no-op -Import)) | Set-Content "$T/import.json"
    PlanJson @((C $vpc aws_vpc create)) | Set-Content "$T/vpc.json"
    PlanJson @((C $vpc aws_vpc create, delete)) | Set-Content "$T/vpcreplace.json"
    PlanJson @((C $vpc aws_vpc delete)) | Set-Content "$T/vpcdelete.json"
    PlanJson @((C $vpc aws_vpc forget)) | Set-Content "$T/vpcforget.json"
    PlanJson @((C $vpc aws_vpc update)) | Set-Content "$T/vpcupdate.json"
    PlanJson @((C $eks aws_eks_cluster create)) | Set-Content "$T/ekscreate.json"
    PlanJson @((C $eks aws_eks_cluster delete)) | Set-Content "$T/eksdelete.json"
    PlanJson @((C 'module.eks.aws_eks_node_group.this' aws_eks_node_group delete, create)) | Set-Content "$T/ngreplace.json"
    @{ format_version = "1.2"; terraform_version = "1.16.2"; output_changes = @{}; resource_changes = @() } | ConvertTo-Json | Set-Content "$T/none.json"
    $sj = Get-Content -Raw "$T/safe.json" | ConvertFrom-Json
    Check "fixture sanity: safe plan has update + create" ((@($sj.resource_changes).Count -eq 2) -and (($sj.resource_changes.change.actions) -join ",") -eq "update,create")

    $env:GITHUB_REPOSITORY = "example/finsight"; $env:GITHUB_SHA = "1" * 40; $env:GITHUB_RUN_ID = "424242"; $env:GITHUB_RUN_ATTEMPT = "1"; $env:RUNNER_TEMP = "$T/rt"
    function Prot($json, $out, $allow = "false") { & $P -Root $root -OutDir $out -AllowDestroy $allow -PlanJsonPath $json -ReviewTextPath "$T/review.txt" -ConfigPath $cfg }

    # Plan side: keys and separation.
    $env:PLAN_ENCRYPTION_RECIPIENT = ""; $env:PLAN_REVIEW_RECIPIENT = $revRec
    Throws "missing CI recipient" { & $P -Root $root -OutDir "$T/o" -CheckOnly } "PLAN_ENCRYPTION_RECIPIENT is missing"
    $env:PLAN_ENCRYPTION_RECIPIENT = $ciRec; $env:PLAN_REVIEW_RECIPIENT = "age1notvalid"
    Throws "malformed reviewer recipient" { & $P -Root $root -OutDir "$T/o" -CheckOnly } "PLAN_REVIEW_RECIPIENT is missing"
    $env:PLAN_REVIEW_RECIPIENT = $ciRec
    Throws "same key for CI and reviewer" { & $P -Root $root -OutDir "$T/o" -CheckOnly } "must be different"
    $env:PLAN_REVIEW_RECIPIENT = $revRec; $env:DECRYPTION_IDENTITY_VISIBLE = $ciId
    Throws "decryption key visible to the plan job" { & $P -Root $root -OutDir "$T/o" -CheckOnly } "visible to the plan job"
    $env:DECRYPTION_IDENTITY_VISIBLE = ""
    Check "valid recipients pass the check" ((Run { & $P -Root $root -OutDir "$T/o" -CheckOnly }) -match "configured")

    # Gates across every plan action.
    Throws "delete without allow_destroy" { Prot "$T/destroy.json" "$T/o1" } "deletes, replaces or forgets"
    Throws "replace (delete,create) without allow_destroy" { Prot "$T/replace.json" "$T/o1" } "deletes, replaces or forgets"
    Throws "replace (create,delete) without allow_destroy" { Prot "$T/replace2.json" "$T/o1" } "deletes, replaces or forgets"
    Throws "forget without allow_destroy" { Prot "$T/forget.json" "$T/o1" } "deletes, replaces or forgets"
    Throws "unrecognised action without allow_destroy" { Prot "$T/unknown.json" "$T/o1" } "deletes, replaces or forgets"
    Throws "import, even with allow_destroy" { Prot "$T/import.json" "$T/o1" "true" } "import aws_route"
    Throws "VPC creation, even with allow_destroy" { Prot "$T/vpc.json" "$T/o1" "true" } "create aws_vpc"
    Throws "VPC replacement, even with allow_destroy" { Prot "$T/vpcreplace.json" "$T/o1" "true" } "replace aws_vpc"
    Throws "VPC deletion, even with allow_destroy" { Prot "$T/vpcdelete.json" "$T/o1" "true" } "delete aws_vpc"
    Throws "VPC forget, even with allow_destroy" { Prot "$T/vpcforget.json" "$T/o1" "true" } "forget aws_vpc"
    Throws "EKS cluster creation, even with allow_destroy" { Prot "$T/ekscreate.json" "$T/o1" "true" } "create aws_eks_cluster"
    Throws "EKS cluster deletion, even with allow_destroy" { Prot "$T/eksdelete.json" "$T/o1" "true" } "delete aws_eks_cluster"
    $env:GITHUB_OUTPUT = "$T/out-vu"; Run { Prot "$T/vpcupdate.json" "$T/ovu" } | Out-Null
    Check "in-place VPC update allowed" ((Get-Content "$T/out-vu") -contains "has_changes=true")
    $env:GITHUB_OUTPUT = "$T/out-ng"; Run { Prot "$T/ngreplace.json" "$T/ong" "true" } | Out-Null
    Check "node group replacement allowed with allow_destroy, flagged destructive" ((Get-Content "$T/out-ng") -contains "destructive=true")
    $env:GITHUB_OUTPUT = "$T/out-none"; Run { Prot "$T/none.json" "$T/onone" } | Out-Null
    Check "no-change plan: nothing encrypted" (((Get-Content "$T/out-none") -contains "has_changes=false") -and -not (Test-Path "$T/onone/platform.tfplan.age"))

    # Safe plan: identity, encryption and review copy.
    $env:GITHUB_OUTPUT = "$T/out-safe"; $env:GITHUB_STEP_SUMMARY = "$T/sum-safe"; Run { Prot "$T/safe.json" "$T/os" } | Out-Null
    $o = @{}; Get-Content "$T/out-safe" | ForEach-Object { $k, $v = $_ -split "=", 2; $o[$k] = $v }
    Check "identity outputs complete" ((@("commit", "run_id", "run_attempt", "state_key", "backend_sha256", "config_sha256", "terraform_version", "lock_file_sha256", "plan_sha256", "changes_sha256", "plan_ciphertext_sha256", "review_ciphertext_sha256", "ci_recipient", "allow_destroy") | Where-Object { -not $o[$_] }).Count -eq 0)
    Check "backend and config digests are of the files" (($o.backend_sha256 -eq (Get-FileHash "$root/backend.hcl" -Algorithm SHA256).Hash.ToLower()) -and ($o.config_sha256 -eq (Get-FileHash $cfg -Algorithm SHA256).Hash.ToLower()))
    Check "plan ciphertext is age, not plaintext" ([Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes("$T/os/platform.tfplan.age"), 0, 21) -eq "age-encryption.org/v1")
    Check "review ciphertext hides plan values" (-not ([IO.File]::ReadAllText("$T/os/platform-plan-review.txt.age")).Contains($marker))
    age --decrypt --identity "$T/reviewer.key" --output "$T/rev.out" "$T/os/platform-plan-review.txt.age"; $rev = Get-Content -Raw "$T/rev.out"
    Check "review copy header binds run, commit, state and digests" (($rev -match "workflow run:\s+424242 attempt 1") -and ($rev -match [regex]::Escape($o.commit)) -and ($rev -match "plan SHA-256:\s+$($o.plan_sha256)") -and ($rev -match "changes SHA-256:\s+$($o.changes_sha256)") -and ($rev -match "dev/platform/terraform.tfstate") -and ($rev -match $marker))
    $sum = Get-Content -Raw "$T/sum-safe"
    Check "summary shows the identity, without values" (($sum -match $o.plan_sha256) -and ($sum -match $o.review_ciphertext_sha256) -and -not ($sum -match "SENSITIVE"))
    age --decrypt --identity "$T/ci.key" --output "$T/x" "$T/os/platform-plan-review.txt.age" 2>$null; Check "CI key cannot decrypt the review copy" ($LASTEXITCODE -ne 0)
    age --decrypt --identity "$T/reviewer.key" --output "$T/x" "$T/os/platform.tfplan.age" 2>$null; Check "reviewer key cannot decrypt the plan" ($LASTEXITCODE -ne 0)
    Check "no plaintext review copy left behind" ((Get-ChildItem "$T/rt" -Filter "review-*").Count -eq 0)

    # Apply side.
    function global:git { $global:planProtectionTestHead }
    function SetExpected() {
        $env:EXPECTED_COMMIT = $o.commit; $env:EXPECTED_RUN_ID = $o.run_id; $env:EXPECTED_RUN_ATTEMPT = $o.run_attempt; $env:EXPECTED_STATE_KEY = $o.state_key
        $env:EXPECTED_BACKEND_SHA256 = $o.backend_sha256; $env:EXPECTED_CONFIG_SHA256 = $o.config_sha256; $env:EXPECTED_LOCK_SHA256 = $o.lock_file_sha256
        $env:EXPECTED_TF_VERSION = $o.terraform_version; $env:EXPECTED_PLAN_CIPHERTEXT_SHA256 = $o.plan_ciphertext_sha256; $env:EXPECTED_CI_RECIPIENT = $o.ci_recipient
        $env:EXPECTED_PLAN_SHA256 = $o.plan_sha256; $env:EXPECTED_CHANGES_SHA256 = $o.changes_sha256; $env:EXPECTED_ALLOW_DESTROY = $o.allow_destroy
        $env:GITHUB_SHA = $o.commit; $env:GITHUB_RUN_ID = $o.run_id; $env:GITHUB_RUN_ATTEMPT = "1"; $env:PLAN_DECRYPTION_IDENTITY = $ciId; $global:planProtectionTestHead = $o.commit
    }
    function Unp($cipher = "$T/os/platform.tfplan.age", $json = "$T/safe.json") { & $U -Root $root -EncryptedPlan $cipher -PlanFile approved.tfplan -PlanJsonPath $json -TerraformVersion "1.16.2" -ConfigPath $cfg }
    Remove-Item "$root/platform.tfplan"; $env:GITHUB_STEP_SUMMARY = "$T/sum-apply"
    SetExpected; $r = Run { Unp }
    Check "happy path verifies and decrypts the exact plan" (($r -match "Verified:") -and ((Get-FileHash "$root/approved.tfplan" -Algorithm SHA256).Hash.ToLower() -eq $o.plan_sha256))
    Check "no identity file is ever written" ((Get-ChildItem "$T/rt" -Filter "identity-*").Count -eq 0); Remove-Item "$root/approved.tfplan"
    SetExpected; $env:GITHUB_SHA = "2" * 40; Throws "wrong commit" { Unp } "Commit does not match"
    SetExpected; $global:planProtectionTestHead = "3" * 40; Throws "wrong checked-out commit" { Unp } "Checked-out commit"
    SetExpected; $env:GITHUB_RUN_ID = "999"; Throws "plan from another workflow run" { Unp } "Workflow run"
    SetExpected; $env:EXPECTED_RUN_ATTEMPT = "2"; Throws "plan from a later attempt" { Unp } "later run attempt"
    SetExpected; $env:EXPECTED_STATE_KEY = "dev/foundation/terraform.tfstate"; Throws "different state key" { Unp } "State key"
    SetExpected; $env:EXPECTED_BACKEND_SHA256 = "0" * 64; Throws "different state backend" { Unp } "State backend"
    SetExpected; $env:EXPECTED_CONFIG_SHA256 = "0" * 64; Throws "different private configuration" { Unp } "Private configuration"
    SetExpected; $env:EXPECTED_LOCK_SHA256 = "0" * 64; Throws "changed dependency lock" { Unp } "Dependency lock"
    SetExpected; $env:EXPECTED_TF_VERSION = "1.16.1"; Throws "different Terraform version" { Unp } "Terraform version"
    SetExpected; $env:EXPECTED_CHANGES_SHA256 = ""; Throws "missing expected value" { Unp } "Missing EXPECTED_CHANGES_SHA256"
    $evil = [byte[]]::new(4096); [Random]::new(9).NextBytes($evil); [IO.File]::WriteAllBytes("$T/evil.tfplan", $evil); age --encrypt --recipient $ciRec --output "$T/evil.age" "$T/evil.tfplan"
    SetExpected; Throws "substituted plan (artifact digest)" { Unp "$T/evil.age" } "Encrypted plan digest"
    SetExpected; $env:EXPECTED_PLAN_CIPHERTEXT_SHA256 = (Get-FileHash "$T/evil.age" -Algorithm SHA256).Hash.ToLower(); Throws "substituted plan with matching artifact digest" { Unp "$T/evil.age" } "Plan digest"
    Check "rejected substituted plan deleted" (-not (Test-Path "$root/approved.tfplan"))
    $c = [IO.File]::ReadAllBytes("$T/os/platform.tfplan.age"); $c[$c.Length - 10] = $c[$c.Length - 10] -bxor 0xFF; [IO.File]::WriteAllBytes("$T/corrupt.age", $c)
    SetExpected; Throws "corrupted artifact (digest)" { Unp "$T/corrupt.age" } "Encrypted plan digest"
    SetExpected; $env:EXPECTED_PLAN_CIPHERTEXT_SHA256 = (Get-FileHash "$T/corrupt.age" -Algorithm SHA256).Hash.ToLower(); Throws "corrupted artifact with matching digest (age authentication)" { Unp "$T/corrupt.age" } "Decrypting the plan failed"
    Check "partial output of failed decryption deleted" (-not (Test-Path "$root/approved.tfplan"))
    SetExpected; Throws "missing artifact" { Unp "$T/nope.age" } "not found"
    SetExpected; $env:PLAN_DECRYPTION_IDENTITY = ""; Throws "missing decryption key" { Unp } "PLAN_DECRYPTION_IDENTITY is missing"
    SetExpected; $env:PLAN_DECRYPTION_IDENTITY = "AGE-SECRET-KEY-1nope"; Throws "malformed decryption key" { Unp } "malformed"
    SetExpected; $env:PLAN_DECRYPTION_IDENTITY = $otherId; Throws "wrong decryption key" { Unp } "Encryption recipient"
    SetExpected; Throws "changes digest mismatch" { Unp -json "$T/replace.json" } "Changes digest"
    Check "plan failing the changes digest deleted" (-not (Test-Path "$root/approved.tfplan"))

    # Destructive plan: the apply side must still require allow_destroy.
    $env:GITHUB_OUTPUT = "$T/out-d2"; $env:GITHUB_SHA = $o.commit; $env:GITHUB_RUN_ID = "424242"; [IO.File]::WriteAllBytes("$root/platform.tfplan", $bytes)
    Run { Prot "$T/destroy.json" "$T/od2" "true" } | Out-Null
    $o = @{}; Get-Content "$T/out-d2" | ForEach-Object { $k, $v = $_ -split "=", 2; $o[$k] = $v }; Remove-Item "$root/platform.tfplan"
    SetExpected; $env:EXPECTED_ALLOW_DESTROY = "false"; Throws "destructive plan without allow_destroy at apply" { Unp "$T/od2/platform.tfplan.age" "$T/destroy.json" } "without allow_destroy"
    SetExpected; $r = Run { Unp "$T/od2/platform.tfplan.age" "$T/destroy.json" }; Check "destructive plan with allow_destroy verifies" ($r -match "Verified:"); Remove-Item "$root/approved.tfplan"

    # Summariser regression for the pull-request workflow.
    [IO.File]::WriteAllBytes("$root/platform.tfplan", $bytes); $env:GITHUB_OUTPUT = "$T/out-sum"; $env:GITHUB_STEP_SUMMARY = "$T/sum-pr"
    & $S -Root $root -PlanFile platform.tfplan -PlanJsonPath "$T/safe.json" *>&1 | Out-Null
    Check "summariser pull-request outputs" (((Get-Content "$T/out-sum") -contains "create=1") -and ((Get-Content "$T/out-sum") -contains "human_only=false") -and ((Get-Content -Raw "$T/sum-pr") -match "## Terraform plan: "))
    $env:GITHUB_OUTPUT = "$T/out-sum2"; & $S -Root $root -PlanFile platform.tfplan -PlanJsonPath "$T/vpc.json" -NoOutputs *>&1 | Out-Null
    Check "summariser -NoOutputs, and human-only flag in summary" ((-not (Test-Path "$T/out-sum2")) -and ((Get-Content -Raw "$T/sum-pr") -match "Human-run apply required"))

    # Nothing secret or plan-valued reaches any output.
    $all = $log.ToString() + (Get-Content -Raw "$T/sum-safe") + (Get-Content -Raw "$T/sum-apply") + ((Get-ChildItem "$T/out-*" | Get-Content) -join "`n")
    Check "no secret key, plan value or account ID in any output" (-not ($all -match "AGE-SECRET-KEY-1[0-9A-Z]{20}") -and -not $all.Contains($marker) -and -not ($all -match '\b123456789012\b'))
}
finally {
    Remove-Item -Recurse -Force -LiteralPath $T -ErrorAction SilentlyContinue
    Remove-Item function:global:git -ErrorAction SilentlyContinue
    foreach ($k in $savedEnv.Keys) { [Environment]::SetEnvironmentVariable($k, $savedEnv[$k]) }
    foreach ($k in "PLAN_ENCRYPTION_RECIPIENT", "PLAN_REVIEW_RECIPIENT", "DECRYPTION_IDENTITY_VISIBLE", "PLAN_DECRYPTION_IDENTITY") { [Environment]::SetEnvironmentVariable($k, $null) }
    Get-ChildItem env: | Where-Object Name -like "EXPECTED_*" | ForEach-Object { [Environment]::SetEnvironmentVariable($_.Name, $null) }
}
"RESULT: $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
