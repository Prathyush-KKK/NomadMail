param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Argv
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot "config\nomad-inbox.ps1"
if (Test-Path -LiteralPath $configPath) {
    . $configPath
}

Import-Module (Join-Path $repoRoot "src\NomadInbox\NomadInbox.psm1") -Force -DisableNameChecking

if ($null -eq $Argv) { $Argv = @() }

function Write-Usage {
    @"
NomadInbox CLI

Setup:
  .\scripts\nomad-inbox.ps1 setup
  .\scripts\nomad-inbox.ps1 doctor
  .\scripts\nomad-inbox.ps1 config status

Discovery:
  .\scripts\nomad-inbox.ps1 providers list
  .\scripts\nomad-inbox.ps1 schemas list
  .\scripts\nomad-inbox.ps1 sample message

This bootstrap does not ship mailbox data, token caches, or secrets.
"@
}

$Command = if ($Argv.Count -gt 0) { $Argv[0] } else { $null }
$Subcommand = if ($Argv.Count -gt 1) { $Argv[1] } else { $null }

try {
    if ([string]::IsNullOrWhiteSpace($Command) -or $Command -in @("-h", "--help", "help")) {
        Write-Usage
        exit 0
    }

    switch ($Command) {
        "setup" {
            Initialize-NomadInbox | ConvertTo-Json -Depth 20
        }
        "doctor" {
            Test-NomadInbox | ConvertTo-Json -Depth 20
        }
        "providers" {
            if ($Subcommand -ne "list") { throw "Unsupported providers subcommand. Use: providers list" }
            Get-NomadInboxProviders | ConvertTo-Json -Depth 20
        }
        "config" {
            if ($Subcommand -ne "status") { throw "Unsupported config subcommand. Use: config status" }
            Get-NomadInboxConfigStatus | ConvertTo-Json -Depth 20
        }
        "schemas" {
            if ($Subcommand -ne "list") { throw "Unsupported schemas subcommand. Use: schemas list" }
            Get-NomadInboxSchemas | ConvertTo-Json -Depth 20
        }
        "sample" {
            if ($Subcommand -ne "message") { throw "Unsupported sample subcommand. Use: sample message" }
            New-NomadInboxSampleMessage | ConvertTo-Json -Depth 30
        }
        default {
            throw "Unknown command: $Command"
        }
    }
} catch {
    [pscustomobject]@{
        status = "error"
        service = "NomadInbox"
        command = $Command
        subcommand = $Subcommand
        error = [string]$_
    } | ConvertTo-Json -Depth 10
    exit 1
}

