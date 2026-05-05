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
  .\scripts\nomad-inbox.ps1 install windows-helper

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
  .\scripts\nomad-inbox.ps1 tray status

This bootstrap does not ship mailbox data, token caches, or secrets.
"@
}

function Get-NomadInboxTrayProcess {
    param(
        [string[]]$Identifiers
    )

    $processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    return @($processes | Where-Object {
        $commandLine = [string]$_.CommandLine
        if ([string]::IsNullOrWhiteSpace($commandLine)) { return $false }
        foreach ($identifier in $Identifiers) {
            if (-not [string]::IsNullOrWhiteSpace($identifier) -and $commandLine.IndexOf($identifier, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                return $true
            }
        }
        return $false
    })
}

function Test-NomadInboxTrayBuildStale {
    param([string]$ExePath, [string[]]$SourcePaths)

    if (-not (Test-Path -LiteralPath $ExePath)) { return $true }
    $exeTime = (Get-Item -LiteralPath $ExePath).LastWriteTimeUtc
    foreach ($path in $SourcePaths) {
        if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).LastWriteTimeUtc -gt $exeTime) {
            return $true
        }
    }
    return $false
}

function Get-NomadInboxDefaultInstalledTrayPath {
    $localAppData = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        Join-Path $env:USERPROFILE "AppData\Local"
    } else {
        $env:LOCALAPPDATA
    }
    return (Join-Path $localAppData "NomadInbox\agent-helper\NomadInboxTray.exe")
}

function Get-NomadInboxTrayStatus {
    if (-not $IsWindows -and $PSVersionTable.PSEdition -eq "Core") {
        return [pscustomobject]@{
            status = "unsupportedPlatform"
            service = "NomadInbox"
            tray = "unsupported"
            trayClient = "compiled"
            platform = $PSVersionTable.Platform
            message = "The compiled system tray client is Windows-only. Use the platform-independent NomadMail MCP server on this OS."
        }
    }

    $repoTrayPath = Join-Path $repoRoot "target\NomadInboxTray\NomadInboxTray.exe"
    $installedTrayPath = Get-NomadInboxDefaultInstalledTrayPath
    $envTrayPath = if ([string]::IsNullOrWhiteSpace($env:NOMADINBOX_TRAY_EXE)) { "" } else { [System.IO.Path]::GetFullPath($env:NOMADINBOX_TRAY_EXE) }
    $candidateTrayPaths = @($envTrayPath, $installedTrayPath, $repoTrayPath) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique

    $runningTrayProcesses = @(Get-NomadInboxTrayProcess -Identifiers @($candidateTrayPaths + @($repoRoot)) | Where-Object { $_.Name -eq "NomadInboxTray.exe" })
    $trayProcess = @($runningTrayProcesses | Select-Object -First 1)
    $trayRunning = $trayProcess.Count -gt 0

    $helperStatusPath = Join-Path (Split-Path -Parent $installedTrayPath) "status.json"
    $helperStatus = $null
    if (Test-Path -LiteralPath $helperStatusPath) {
        try {
            $helperStatus = Get-Content -LiteralPath $helperStatusPath -Raw | ConvertFrom-Json
        } catch {
            $helperStatus = [pscustomobject]@{
                status = "error"
                error = [string]$_
            }
        }
    }

    $httpStatus = [pscustomobject]@{
        status = "unreachable"
        url = "http://127.0.0.1:8791"
        error = $null
    }
    try {
        $health = Invoke-RestMethod -Uri "http://127.0.0.1:8791/health" -TimeoutSec 2
        $httpStatus = [pscustomobject]@{
            status = $health.status
            url = "http://127.0.0.1:8791"
            service = $health.service
            version = $health.version
            worker = $health.worker
        }
    } catch {
        $httpStatus.error = $_.Exception.Message
    }

    $serviceStatus = $null
    try {
        $serviceStatus = Get-NomadInboxServiceStatus
    } catch {
        $serviceStatus = [pscustomobject]@{
            status = "error"
            error = [string]$_
        }
    }
    $dataDir = if ([string]::IsNullOrWhiteSpace($env:NOMADINBOX_DATA_DIR)) {
        Join-Path $repoRoot "data"
    } else {
        $env:NOMADINBOX_DATA_DIR
    }
    $helperSummary = if ($null -ne $helperStatus) {
        [pscustomobject]@{
            status = $helperStatus.status
            installedAt = $helperStatus.installedAt
            dataDir = $helperStatus.dataDir
            helperPath = $helperStatus.helperPath
            trayExePath = $helperStatus.trayExePath
        }
    } else {
        $null
    }
    $syncAccounts = @()
    if ($null -ne $serviceStatus -and $null -ne $serviceStatus.syncStatus -and $null -ne $serviceStatus.syncStatus.accounts) {
        $syncAccounts = @($serviceStatus.syncStatus.accounts | ForEach-Object {
            [pscustomobject]@{
                accountId = $_.accountId
                displayName = $_.displayName
                provider = $_.provider
                status = $_.status
                reason = $_.reason
                synced = $_.synced
                finishedAt = $_.finishedAt
            }
        })
    }
    $backupSummary = if ($null -ne $serviceStatus -and $null -ne $serviceStatus.backupStatus) {
        [pscustomobject]@{
            liveSyncedMessages = $serviceStatus.backupStatus.liveSyncedMessages
            archiveImportedMessages = $serviceStatus.backupStatus.archiveImportedMessages
            totalBackedUpMessages = $serviceStatus.backupStatus.totalBackedUpMessages
        }
    } else {
        $null
    }

    return [pscustomobject]@{
        status = "ok"
        service = "NomadInbox"
        tray = if ($trayRunning) { "running" } else { "stopped" }
        trayClient = "compiled"
        pid = if ($trayRunning) { $trayProcess[0].ProcessId } else { $null }
        processCount = $runningTrayProcesses.Count
        exePath = if ($trayRunning) { $trayProcess[0].ExecutablePath } else { $null }
        installedExePath = $installedTrayPath
        repoExePath = $repoTrayPath
        installedExeExists = Test-Path -LiteralPath $installedTrayPath
        repoExeExists = Test-Path -LiteralPath $repoTrayPath
        helperInstalled = Test-Path -LiteralPath $helperStatusPath
        helperStatusPath = $helperStatusPath
        helper = $helperSummary
        dataDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($dataDir)
        http = $httpStatus
        worker = if ($null -ne $serviceStatus) { $serviceStatus.worker } else { $null }
        lastRunAt = if ($null -ne $serviceStatus -and $null -ne $serviceStatus.syncStatus) { $serviceStatus.syncStatus.lastRunAt } else { $null }
        nextRunAt = if ($null -ne $serviceStatus -and $null -ne $serviceStatus.syncStatus) { $serviceStatus.syncStatus.nextRunAt } else { $null }
        accounts = $syncAccounts
        backup = $backupSummary
        message = if ($trayRunning) {
            "NomadMail is available from the compiled NomadInbox system tray app."
        } else {
            "NomadInbox tray is not running. Start it with tray start on Windows."
        }
    }
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
        "install" {
            if ($Subcommand -ne "windows-helper") { throw "Unsupported install subcommand. Use: install windows-helper" }
            $options = ConvertTo-NomadInboxOptions -Tokens $RemainingArgs
            $installer = Join-Path $repoRoot "scripts\install-windows-agent-helper.ps1"
            $installerArgs = @()
            $dataDir = Get-NomadInboxOption $options "data-dir" ""
            if (-not [string]::IsNullOrWhiteSpace($dataDir)) { $installerArgs += @("-DataDir", $dataDir) }
            $installRoot = Get-NomadInboxOption $options "install-root" ""
            if (-not [string]::IsNullOrWhiteSpace($installRoot)) { $installerArgs += @("-InstallRoot", $installRoot) }
            if ($options.ContainsKey("start-tray")) { $installerArgs += "-StartTray" }
            & $installer @installerArgs
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
            switch ($Subcommand) {
                "start" {
                    $options = ConvertTo-NomadInboxOptions -Tokens $RemainingArgs
                    $trayLauncher = Join-Path $repoRoot "scripts\nomad-inbox-tray.ps1"
                    $compiledTray = if ([string]::IsNullOrWhiteSpace($env:NOMADINBOX_TRAY_EXE)) {
                        Join-Path $repoRoot "target\NomadInboxTray\NomadInboxTray.exe"
                    } else {
                        [System.IO.Path]::GetFullPath($env:NOMADINBOX_TRAY_EXE)
                    }

                    $existingCompiledTray = @(Get-NomadInboxTrayProcess -Identifiers @($compiledTray) | Select-Object -First 1)
                    if ($existingCompiledTray.Count -gt 0) {
                        [pscustomobject]@{
                            status = "ok"
                            service = "NomadInbox"
                            tray = "compiledAlreadyRunning"
                            trayClient = "compiled"
                            pid = $existingCompiledTray[0].ProcessId
                            message = "NomadMail is available from the compiled NomadInbox system tray app. Open the Windows notification overflow if the icon is hidden."
                        } | ConvertTo-Json -Depth 10
                        break
                    }

                    $launcherArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $trayLauncher)
                    $dataDir = Get-NomadInboxOption $options "data-dir" ""
                    if (-not [string]::IsNullOrWhiteSpace($dataDir)) { $launcherArgs += @("-DataDir", $dataDir) }
                    $trayStartText = & powershell.exe @launcherArgs
                    if ([string]::IsNullOrWhiteSpace(($trayStartText | Out-String))) {
                        throw "Compiled tray launcher did not return a status."
                    }
                    $trayStartText
                }
                "status" {
                    Get-NomadInboxTrayStatus | ConvertTo-Json -Depth 60
                }
                default { throw "Unsupported tray subcommand. Use: tray start|status" }
            }
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
