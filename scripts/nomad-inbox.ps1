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
  .\scripts\nomad-inbox.ps1 accounts init
  .\scripts\nomad-inbox.ps1 accounts list
  .\scripts\nomad-inbox.ps1 backup status
  .\scripts\nomad-inbox.ps1 schemas list
  .\scripts\nomad-inbox.ps1 sample message

Archive context import:
  .\scripts\nomad-inbox.ps1 import status
  .\scripts\nomad-inbox.ps1 import eml --path .\mail-export --source outlook-export
  .\scripts\nomad-inbox.ps1 import mbox --path .\takeout\Mail.mbox --source gmail-takeout
  .\scripts\nomad-inbox.ps1 import jsonl --path .\messages.jsonl --source nomadinbox-export
  Add --include-bodies only when the user explicitly wants full archive body storage.

Background sync:
  .\scripts\nomad-inbox.ps1 sync once
  .\scripts\nomad-inbox.ps1 sync once --account-id personal-gmail
  .\scripts\nomad-inbox.ps1 service start
  .\scripts\nomad-inbox.ps1 service start --interval-seconds 300
  .\scripts\nomad-inbox.ps1 service status
  .\scripts\nomad-inbox.ps1 service stop
  .\scripts\nomad-inbox.ps1 tray start

This bootstrap does not ship mailbox data, token caches, or secrets.
"@
}

$Command = if ($Argv.Count -gt 0) { $Argv[0] } else { $null }
$Subcommand = if ($Argv.Count -gt 1) { $Argv[1] } else { $null }
$RemainingArgs = if ($Argv.Count -gt 2) { @($Argv[2..($Argv.Count - 1)]) } else { @() }

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
        "accounts" {
            switch ($Subcommand) {
                "init" { Initialize-NomadInboxAccountsConfig | ConvertTo-Json -Depth 20 }
                "list" { Get-NomadInboxAccounts | ConvertTo-Json -Depth 30 }
                default { throw "Unsupported accounts subcommand. Use: accounts init|list" }
            }
        }
        "backup" {
            if ($Subcommand -ne "status") { throw "Unsupported backup subcommand. Use: backup status" }
            Get-NomadInboxBackupStatus | ConvertTo-Json -Depth 60
        }
        "import" {
            switch ($Subcommand) {
                "status" { Read-NomadInboxImportStatus | ConvertTo-Json -Depth 40 }
                "eml" {
                    $options = ConvertTo-NomadInboxOptions -Tokens $RemainingArgs
                    Import-NomadInboxArchive -Format "eml" -Path (Require-NomadInboxOption $options "path") -Source (Get-NomadInboxOption $options "source" "eml-export") -MaxMessages ([int](Get-NomadInboxOption $options "max-messages" "0")) -IncludeBodies:($options.ContainsKey("include-bodies")) -DryRun:($options.ContainsKey("dry-run")) | ConvertTo-Json -Depth 50
                }
                "mbox" {
                    $options = ConvertTo-NomadInboxOptions -Tokens $RemainingArgs
                    Import-NomadInboxArchive -Format "mbox" -Path (Require-NomadInboxOption $options "path") -Source (Get-NomadInboxOption $options "source" "gmail-takeout") -MaxMessages ([int](Get-NomadInboxOption $options "max-messages" "0")) -IncludeBodies:($options.ContainsKey("include-bodies")) -DryRun:($options.ContainsKey("dry-run")) | ConvertTo-Json -Depth 50
                }
                "jsonl" {
                    $options = ConvertTo-NomadInboxOptions -Tokens $RemainingArgs
                    Import-NomadInboxArchive -Format "jsonl" -Path (Require-NomadInboxOption $options "path") -Source (Get-NomadInboxOption $options "source" "nomadinbox-export") -MaxMessages ([int](Get-NomadInboxOption $options "max-messages" "0")) -IncludeBodies:($options.ContainsKey("include-bodies")) -DryRun:($options.ContainsKey("dry-run")) | ConvertTo-Json -Depth 50
                }
                "pst" { throw "PST import is planned but not implemented in this bootstrap. Use eml, mbox, or jsonl now." }
                "msg" { throw "MSG import is planned but not implemented in this bootstrap. Use eml, mbox, or jsonl now." }
                default { throw "Unsupported import subcommand. Use: import status|eml|mbox|jsonl" }
            }
        }
        "sync" {
            if ($Subcommand -ne "once") { throw "Unsupported sync subcommand. Use: sync once" }
            $options = ConvertTo-NomadInboxOptions -Tokens $RemainingArgs
            $accountId = Get-NomadInboxOption $options "account-id" ""
            Invoke-NomadInboxSyncOnce -AccountId $accountId | ConvertTo-Json -Depth 40
        }
        "service" {
            switch ($Subcommand) {
                "start" {
                    $options = ConvertTo-NomadInboxOptions -Tokens $RemainingArgs
                    Start-NomadInboxService -IntervalSeconds ([int](Get-NomadInboxOption $options "interval-seconds" "0")) | ConvertTo-Json -Depth 50
                }
                "stop" { Stop-NomadInboxService | ConvertTo-Json -Depth 30 }
                "restart" {
                    Stop-NomadInboxService | Out-Null
                    Start-NomadInboxService | ConvertTo-Json -Depth 50
                }
                "status" { Get-NomadInboxServiceStatus | ConvertTo-Json -Depth 50 }
                default { throw "Unsupported service subcommand. Use: service start|stop|restart|status" }
            }
        }
        "tray" {
            if ($Subcommand -ne "start") { throw "Unsupported tray subcommand. Use: tray start" }
            $tray = Join-Path $repoRoot "scripts\nomad-inbox-tray.ps1"
            Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $tray) -WorkingDirectory $repoRoot | Out-Null
            [pscustomobject]@{ status = "ok"; service = "NomadInbox"; tray = "started" } | ConvertTo-Json -Depth 10
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
