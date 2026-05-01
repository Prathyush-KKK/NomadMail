$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $repoRoot "scripts\nomad-inbox.ps1"

$doctor = & $cli doctor | ConvertFrom-Json
if ($doctor.status -ne "ok") { throw "doctor failed" }

$providers = & $cli providers list | ConvertFrom-Json
if (@($providers.providers).Count -lt 3) { throw "expected three providers" }

$accounts = & $cli accounts list | ConvertFrom-Json
if (@($accounts.accounts).Count -lt 3) { throw "expected account templates" }

$status = & $cli service status | ConvertFrom-Json
if ($status.status -ne "ok") { throw "service status failed" }

$sample = & $cli sample message | ConvertFrom-Json
if ($sample.provider -ne "sample") { throw "sample message failed" }

[pscustomobject]@{
    status = "ok"
    tests = @("doctor", "providers list", "accounts list", "service status", "sample message")
} | ConvertTo-Json -Depth 5
