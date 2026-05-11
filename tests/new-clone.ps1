param(
    [switch]$ExpectedCleanClone,
    [switch]$IncludeSmoke,
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $repoRoot "scripts\nomad-inbox.ps1"
$service = Join-Path $repoRoot "service\nomadmail-service.mjs"
$validate = Join-Path $repoRoot "scripts\validate.ps1"
$smoke = Join-Path $repoRoot "tests\smoke.ps1"

$previousDataDir = $env:NOMADINBOX_DATA_DIR
$previousHttpPort = $env:NOMADMAIL_HTTP_PORT
$previousHttpHost = $env:NOMADMAIL_HTTP_HOST
$tempBase = if ([string]::IsNullOrWhiteSpace($env:TEMP)) { Join-Path $env:USERPROFILE "AppData\Local\Temp" } else { $env:TEMP }
$testRoot = Join-Path $tempBase ("nomadinbox-new-clone-" + [guid]::NewGuid().ToString("n"))
$server = $null
$checks = [System.Collections.ArrayList]::new()

function Add-Check {
    param(
        [string]$Name,
        [string]$Status,
        [object]$Details = $null
    )
    [void]$script:checks.Add([pscustomobject]@{
        name = $Name
        status = $Status
        details = $Details
    })
}

function Invoke-Check {
    param(
        [string]$Name,
        [scriptblock]$Script
    )
    try {
        $details = & $Script
        Add-Check -Name $Name -Status "ok" -Details $details
    } catch {
        Add-Check -Name $Name -Status "failed" -Details $_.Exception.Message
    }
}

function Assert-NewClone {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

function Get-HttpStartupDiagnostics {
    param(
        [object]$Process,
        [string]$OutLog,
        [string]$ErrLog,
        [int]$Port,
        [string]$LastError
    )

    function Get-SharedLogText {
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path)) { return "missing" }
        try {
            $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                $reader = New-Object System.IO.StreamReader($stream)
                try {
                    return $reader.ReadToEnd().Trim()
                } finally {
                    $reader.Dispose()
                }
            } finally {
                $stream.Dispose()
            }
        } catch {
            return "unreadable: $($_.Exception.Message)"
        }
    }

    $listener = $null
    try {
        $listener = Get-NetTCPConnection -LocalAddress "127.0.0.1" -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
            Select-Object -First 1 LocalAddress, LocalPort, OwningProcess
    } catch {
    }

    return [pscustomobject]@{
        port = $Port
        processId = $Process.Id
        processExited = $Process.HasExited
        exitCode = if ($Process.HasExited) { $Process.ExitCode } else { $null }
        lastRequestError = $LastError
        listener = $listener
        stdout = Get-SharedLogText -Path $OutLog
        stderr = Get-SharedLogText -Path $ErrLog
    }
}

try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    $env:NOMADINBOX_DATA_DIR = Join-Path $testRoot "data"
    $env:NOMADMAIL_HTTP_HOST = "127.0.0.1"
    $port = Get-Random -Minimum 19100 -Maximum 19900
    $env:NOMADMAIL_HTTP_PORT = [string]$port
    $baseUri = "http://127.0.0.1:$port"

    Invoke-Check "environment" {
        $nodeVersion = (& node --version)
        [pscustomobject]@{
            powershellVersion = $PSVersionTable.PSVersion.ToString()
            nodeVersion = $nodeVersion
            os = [System.Environment]::OSVersion.VersionString
            repoRoot = $repoRoot
            tempDataDir = $env:NOMADINBOX_DATA_DIR
        }
    }

    Invoke-Check "clean clone preconditions" {
        $accountsConfig = Join-Path $repoRoot "config\accounts.json"
        $repoDataDir = Join-Path $repoRoot "data"
        $accountsConfigExists = Test-Path -LiteralPath $accountsConfig
        $repoDataDirExists = Test-Path -LiteralPath $repoDataDir
        if ($ExpectedCleanClone) {
            Assert-NewClone (-not $accountsConfigExists) "config/accounts.json exists; this is not a clean cloned workspace."
        }
        [pscustomobject]@{
            expectedCleanClone = [bool]$ExpectedCleanClone
            accountsConfigExists = $accountsConfigExists
            repoDataDirExists = $repoDataDirExists
            note = if ($ExpectedCleanClone) { "Local account config must be absent before setup." } else { "Existing local config is allowed for current-workspace compatibility." }
        }
    }

    Invoke-Check "repository validation" {
        & $validate | ConvertFrom-Json
    }

    Invoke-Check "service syntax" {
        & node --check $service | Out-Null
        [pscustomobject]@{ status = "ok" }
    }

    Invoke-Check "runtime setup" {
        $setup = & $cli setup | ConvertFrom-Json
        Assert-NewClone ($setup.status -eq "ok") "setup did not return ok"
        $setup
    }

    Invoke-Check "git ignore boundary" {
        $paths = @(
            "data\messages.jsonl",
            "data\provider-raw.jsonl",
            "data\sync-status.json",
            "config\accounts.json",
            "runtime\agent-scratch"
        )
        $ignored = @()
        if (Get-Command git -ErrorAction SilentlyContinue) {
            foreach ($path in $paths) {
                $line = git -C $repoRoot check-ignore -v $path 2>$null
                if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($line)) {
                    throw "Path is not ignored: $path"
                }
                $ignored += $path
            }
        }
        [pscustomobject]@{ ignored = $ignored }
    }

    Invoke-Check "account defaults" {
        $accounts = & $cli accounts list | ConvertFrom-Json
        Assert-NewClone ($accounts.status -eq "ok") "accounts list failed"
        if ($ExpectedCleanClone) {
            Assert-NewClone ($accounts.configExists -eq $false) "clean clone should read account templates, not local config/accounts.json"
            $enabled = @($accounts.accounts | Where-Object { $_.enabled })
            Assert-NewClone ($enabled.Count -eq 0) "clean clone should not have enabled accounts by default"
        }
        [pscustomobject]@{
            configExists = $accounts.configExists
            accountCount = @($accounts.accounts).Count
            enabledCount = @($accounts.accounts | Where-Object { $_.enabled }).Count
        }
    }

    Invoke-Check "tools and context surfaces" {
        $tools = & node $service tools | ConvertFrom-Json
        $prompt = & node $service system-prompt | ConvertFrom-Json
        $flow = & node $service agent-user-flow | ConvertFrom-Json
        $handoff = & node $service cross-chat-handoff | ConvertFrom-Json
        $guide = & node $service agent-guide | ConvertFrom-Json
        $requiredTools = @(
            "nomadmail_get_agent_guide",
            "nomadmail_get_startup_system_prompt",
            "nomadmail_get_workspace_state",
            "nomadmail_get_agent_user_flow",
            "nomadmail_get_cross_chat_handoff",
            "nomadmail_search_messages",
            "nomadmail_get_latest_message",
            "nomadmail_get_message_actions",
            "nomadmail_run_agent_automation_cycle",
            "nomadmail_list_agent_events",
            "nomadmail_ack_agent_event",
            "nomadmail_import_archive"
        )
        $toolNames = @($tools.tools | ForEach-Object { $_.name })
        foreach ($tool in $requiredTools) {
            Assert-NewClone ($toolNames -contains $tool) "Missing tool: $tool"
        }
        Assert-NewClone ($prompt.text -like "*docs/runbooks/agent-user-flow.md*") "startup prompt does not reference agent-user-flow"
        Assert-NewClone ($flow.text -like "*Daily Mail Query Menu*") "agent user flow does not include daily mail choices"
        Assert-NewClone ($handoff.text -like "*Prompt To Give Another Agent*") "cross-chat handoff does not include agent handoff prompt"
        Assert-NewClone ($guide.agentUserFlow.text -like "*Daily Mail Query Menu*") "agent guide does not embed user flow"
        Assert-NewClone ($guide.crossChatHandoff.text -like "*Prompt To Give Another Agent*") "agent guide does not embed cross-chat handoff"
        [pscustomobject]@{
            toolCount = @($tools.tools).Count
            startupPrompt = $prompt.status
            agentUserFlow = $flow.status
            crossChatHandoff = $handoff.status
            agentGuide = $guide.status
        }
    }

    Invoke-Check "synthetic archive import and search" {
        $emlPath = Join-Path $testRoot "new-clone-sample.eml"
        @"
From: New Clone Sender <sender@example.com>
To: New Clone User <user@example.com>
Subject: New clone validation mail
Date: Wed, 06 May 2026 11:30:00 +0530
Message-ID: <new-clone-validation@example.com>

This validates that a brand new clone can import and search read-only archive context without live mailbox access.
"@ | Set-Content -LiteralPath $emlPath -Encoding UTF8

        $dryRun = & $cli import eml --path $emlPath --source new-clone-test --max-messages 1 --dry-run | ConvertFrom-Json
        Assert-NewClone ($dryRun.status -eq "dryRun" -and $dryRun.importedMessages -eq 1) "archive dry-run failed"
        $import = & $cli import eml --path $emlPath --source new-clone-test --max-messages 1 | ConvertFrom-Json
        Assert-NewClone ($import.status -eq "ok" -and $import.importedMessages -eq 1 -and $import.actionable -eq $false) "archive import failed"
        [pscustomobject]@{
            dryRunStatus = $dryRun.status
            importedMessages = $import.importedMessages
            actionable = $import.actionable
        }
    }

    Invoke-Check "http service surfaces" {
        $outLog = Join-Path $testRoot "nomadmail-http.out.log"
        $errLog = Join-Path $testRoot "nomadmail-http.err.log"
        $script:server = Start-Process -FilePath "node" -ArgumentList @($service, "http", "--port", [string]$port, "--host", "127.0.0.1") -WorkingDirectory $repoRoot -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru

        $health = $null
        $lastHealthError = $null
        for ($attempt = 0; $attempt -lt 40; $attempt++) {
            try {
                $health = Invoke-RestMethod -Uri "$baseUri/health" -TimeoutSec 5
                break
            } catch {
                $lastHealthError = $_.Exception.Message
                Start-Sleep -Milliseconds 250
            }
        }
        if ($null -eq $health -or $health.status -ne "ok") {
            throw ((Get-HttpStartupDiagnostics -Process $script:server -OutLog $outLog -ErrLog $errLog -Port $port -LastError $lastHealthError) | ConvertTo-Json -Depth 4 -Compress)
        }
        $flow = Invoke-RestMethod -Uri "$baseUri/agent-user-flow" -TimeoutSec 5
        Assert-NewClone ($flow.status -eq "ok" -and $flow.text -like "*Flow End State*") "HTTP agent user flow failed"
        $search = Invoke-RestMethod -Uri "$baseUri/messages?query=new%20clone&limit=5" -TimeoutSec 5
        Assert-NewClone ($search.status -eq "ok" -and $search.count -ge 1) "HTTP search failed"
        $message = @($search.results)[0]
        $actions = Invoke-RestMethod -Uri ("$baseUri/message-actions?id=" + [uri]::EscapeDataString($message.id)) -TimeoutSec 5
        Assert-NewClone ($actions.actionGuide.actionable -eq $false) "archive message should be non-actionable"
        $latest = Invoke-RestMethod -Method Post -Uri "$baseUri/messages/latest" -Body (@{ syncFirst = $false; requireContent = $true } | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 5
        Assert-NewClone ($latest.freshnessRule -like "*one-shot live sync first*") "latest freshness rule missing"
        $syntheticLiveId = "outlook-desktop:desktop-outlook:new-clone-event"
        [pscustomobject]@{
            schemaVersion = 2
            id = $syntheticLiveId
            accountId = "desktop-outlook"
            provider = "outlook-desktop"
            providerMessageId = "new-clone-entry-id"
            subject = "New clone automation event"
            from = [pscustomobject]@{ email = "sender@example.com" }
            receivedAt = "2026-05-06T10:15:00.000Z"
            unread = $true
            sourceType = "live-sync"
            actionable = $true
        } | ConvertTo-Json -Depth 20 -Compress | Set-Content -LiteralPath (Join-Path $env:NOMADINBOX_DATA_DIR "messages.jsonl") -Encoding UTF8
        $automation = Invoke-RestMethod -Method Post -Uri "$baseUri/agent-events/automation-cycle" -Body (@{ assignedAgent = "codex"; limit = 5 } | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 5
        Assert-NewClone ($automation.status -eq "ok" -and $automation.createdCount -eq 1) "agent automation event creation failed"
        $events = Invoke-RestMethod -Uri "$baseUri/agent-events?assignedAgent=codex&status=pending" -TimeoutSec 5
        $eventMessageId = @($events.events)[0].messageRefs[0].id
        Assert-NewClone ($events.status -eq "ok" -and $events.count -eq 1 -and $eventMessageId -eq $syntheticLiveId) "agent event listing failed"
        [pscustomobject]@{
            port = $port
            health = $health.status
            flow = $flow.status
            searchCount = $search.count
            archiveActionable = $actions.actionGuide.actionable
            latestStatus = $latest.status
            agentEvents = $events.count
        }
    }

    if ($IsWindows -or [System.Environment]::OSVersion.Platform -eq "Win32NT") {
        Invoke-Check "windows helper install dry bootstrap" {
            $installRoot = Join-Path $testRoot "agent-helper"
            $install = & $cli install windows-helper --data-dir $env:NOMADINBOX_DATA_DIR --install-root $installRoot --skip-user-env | ConvertFrom-Json
            Assert-NewClone ($install.status -eq "ok") "windows helper install failed"
            Assert-NewClone (Test-Path -LiteralPath $install.helperPath) "helper launcher missing"
            Assert-NewClone (Test-Path -LiteralPath $install.statusPath) "helper status missing"
            Assert-NewClone ($install.environment.skipped -eq $true) "test helper install should skip user environment registration"
            [pscustomobject]@{
                status = $install.status
                platform = $install.platform
                trayStarted = $install.trayStarted
                userEnvironmentSkipped = $install.environment.skipped
            }
        }
    } else {
        Invoke-Check "non-windows platform boundary" {
            $install = & node $service install-windows-helper | ConvertFrom-Json
            Assert-NewClone ($install.status -eq "unsupportedPlatform") "non-Windows should not install Windows helper"
            $install
        }
    }

    if ($IncludeSmoke) {
        Invoke-Check "full smoke suite" {
            & $smoke | ConvertFrom-Json
        }
    }

    $failed = @($checks | Where-Object { $_.status -ne "ok" })
    $result = [pscustomobject]@{
        status = if ($failed.Count -eq 0) { "ok" } else { "failed" }
        service = "NomadMail"
        purpose = "New clone bootstrap validation"
        expectedCleanClone = [bool]$ExpectedCleanClone
        includeSmoke = [bool]$IncludeSmoke
        repoRoot = $repoRoot
        tempDataDir = $env:NOMADINBOX_DATA_DIR
        checks = $checks
    }

    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $resolvedOutput = if ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $repoRoot $OutputPath }
        $parent = Split-Path -Parent $resolvedOutput
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
        $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resolvedOutput -Encoding UTF8
    }

    $result | ConvertTo-Json -Depth 12
    if ($result.status -ne "ok") {
        exit 1
    }
} finally {
    if ($null -ne $server -and -not $server.HasExited) {
        Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
        try {
            Wait-Process -Id $server.Id -Timeout 5 -ErrorAction SilentlyContinue
        } catch {
        }
    }
    if ($null -eq $previousDataDir) {
        Remove-Item Env:\NOMADINBOX_DATA_DIR -ErrorAction SilentlyContinue
    } else {
        $env:NOMADINBOX_DATA_DIR = $previousDataDir
    }
    if ($null -eq $previousHttpPort) {
        Remove-Item Env:\NOMADMAIL_HTTP_PORT -ErrorAction SilentlyContinue
    } else {
        $env:NOMADMAIL_HTTP_PORT = $previousHttpPort
    }
    if ($null -eq $previousHttpHost) {
        Remove-Item Env:\NOMADMAIL_HTTP_HOST -ErrorAction SilentlyContinue
    } else {
        $env:NOMADMAIL_HTTP_HOST = $previousHttpHost
    }
    Set-Location $repoRoot
    Start-Sleep -Milliseconds 200
    try {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction Stop
    } catch {
    }
}
