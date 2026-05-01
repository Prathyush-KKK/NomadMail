$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $repoRoot "scripts\nomad-inbox.ps1"
$previousDataDir = $env:NOMADINBOX_DATA_DIR
$tempBase = if ([string]::IsNullOrWhiteSpace($env:TEMP)) { Join-Path $env:USERPROFILE "AppData\Local\Temp" } else { $env:TEMP }
$testRoot = Join-Path $tempBase ("nomadinbox-smoke-" + [guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
$env:NOMADINBOX_DATA_DIR = Join-Path $testRoot "data"

try {
    $doctor = & $cli doctor | ConvertFrom-Json
    if ($doctor.status -ne "ok") { throw "doctor failed" }

    $providers = & $cli providers list | ConvertFrom-Json
    if (@($providers.providers).Count -lt 3) { throw "expected three providers" }

    $accounts = & $cli accounts list | ConvertFrom-Json
    if (@($accounts.accounts).Count -lt 3) { throw "expected account templates" }

    $status = & $cli service status | ConvertFrom-Json
    if ($status.status -ne "ok") { throw "service status failed" }

    $backup = & $cli backup status | ConvertFrom-Json
    if ($backup.status -ne "ok") { throw "backup status failed" }

    $importStatus = & $cli import status | ConvertFrom-Json
    if ($null -eq $importStatus.service) { throw "import status failed" }

    $sample = & $cli sample message | ConvertFrom-Json
    if ($sample.provider -ne "sample") { throw "sample message failed" }

    $emlPath = Join-Path $testRoot "sample.eml"
    @"
From: Example Sender <sender@example.com>
To: Example User <user@example.com>
Subject: Sample archive import
Date: Wed, 15 Apr 2026 10:30:00 +0000
Message-ID: <sample-archive@example.com>

This sample validates archive ingestion without using real mailbox exports.
"@ | Set-Content -LiteralPath $emlPath -Encoding UTF8

    $import = & $cli import eml --path $emlPath --source smoke-test --max-messages 1 | ConvertFrom-Json
    if ($import.status -ne "ok" -or $import.importedMessages -ne 1 -or $import.actionable -ne $false) {
        throw "archive import failed"
    }

    [pscustomobject]@{
        status = "ok"
        tests = @("doctor", "providers list", "accounts list", "service status", "backup status", "import status", "sample message", "import eml")
    } | ConvertTo-Json -Depth 5
} finally {
    if ($null -eq $previousDataDir) {
        Remove-Item Env:\NOMADINBOX_DATA_DIR -ErrorAction SilentlyContinue
    } else {
        $env:NOMADINBOX_DATA_DIR = $previousDataDir
    }
    Set-Location $repoRoot
    try {
        Start-Sleep -Milliseconds 200
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction Stop
    } catch {
    }
}
