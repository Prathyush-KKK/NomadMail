$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $repoRoot "scripts\nomad-inbox.ps1"
$service = Join-Path $repoRoot "service\nomadmail-service.mjs"

$previousDataDir = $env:NOMADINBOX_DATA_DIR
$previousHttpPort = $env:NOMADMAIL_HTTP_PORT
$previousHttpHost = $env:NOMADMAIL_HTTP_HOST
$tempBase = if ([string]::IsNullOrWhiteSpace($env:TEMP)) { Join-Path $env:USERPROFILE "AppData\Local\Temp" } else { $env:TEMP }
$testRoot = Join-Path $tempBase ("nomadinbox-agent-flow-" + [guid]::NewGuid().ToString("n"))
$server = $null

function Assert-Flow {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

function Add-Scenario {
    param(
        [System.Collections.ArrayList]$Scenarios,
        [string]$Name,
        [string]$ExpectedOutput
    )
    [void]$Scenarios.Add([pscustomobject]@{
        name = $Name
        status = "ok"
        expectedUserOutput = $ExpectedOutput
    })
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

    return (@(
        "HTTP service did not become healthy on 127.0.0.1:$Port.",
        "Process: pid=$($Process.Id), exited=$($Process.HasExited), exitCode=$(if ($Process.HasExited) { $Process.ExitCode } else { "running" }).",
        "Last request error: $LastError",
        "Listener: $(if ($listener) { ($listener | ConvertTo-Json -Compress) } else { "none" })",
        "stdout: $(Get-SharedLogText -Path $OutLog)",
        "stderr: $(Get-SharedLogText -Path $ErrLog)"
    ) -join " ")
}

try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    $env:NOMADINBOX_DATA_DIR = Join-Path $testRoot "data"
    $env:NOMADMAIL_HTTP_HOST = "127.0.0.1"
    $port = Get-Random -Minimum 18100 -Maximum 18900
    $env:NOMADMAIL_HTTP_PORT = [string]$port
    $baseUri = "http://127.0.0.1:$port"

    & node --check $service | Out-Null
    $setup = & $cli setup | ConvertFrom-Json
    Assert-Flow ($setup.status -eq "ok") "setup did not initialize temp runtime"

    $emlPath = Join-Path $testRoot "daily-flow-scenario.eml"
    @"
From: Daily Flow Sender <sender@example.com>
To: Example User <user@example.com>
Subject: Daily mail flow archive scenario
Date: Wed, 06 May 2026 09:15:00 +0530
Message-ID: <daily-flow-scenario@example.com>

This archive-only message validates the daily mail query path, read-only action menu, and report naming guidance.
"@ | Set-Content -LiteralPath $emlPath -Encoding UTF8

    $dryRun = & $cli import eml --path $emlPath --source agent-flow-test --max-messages 1 --dry-run | ConvertFrom-Json
    Assert-Flow ($dryRun.status -eq "dryRun" -and $dryRun.importedMessages -eq 1) "archive import dry-run did not report one message"

    $import = & $cli import eml --path $emlPath --source agent-flow-test --max-messages 1 | ConvertFrom-Json
    Assert-Flow ($import.status -eq "ok" -and $import.importedMessages -eq 1 -and $import.actionable -eq $false) "archive import did not create one read-only message"

    $outLog = Join-Path $testRoot "nomadmail-http.out.log"
    $errLog = Join-Path $testRoot "nomadmail-http.err.log"
    $server = Start-Process -FilePath "node" -ArgumentList @($service, "http", "--port", [string]$port, "--host", "127.0.0.1") -WorkingDirectory $repoRoot -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru

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
        throw (Get-HttpStartupDiagnostics -Process $server -OutLog $outLog -ErrLog $errLog -Port $port -LastError $lastHealthError)
    }

    $scenarios = [System.Collections.ArrayList]::new()

    $tools = & node $service tools | ConvertFrom-Json
    Assert-Flow ((@($tools.tools | Where-Object { $_.name -eq "nomadmail_get_agent_user_flow" }).Count) -eq 1) "agent user flow tool is missing"
    Assert-Flow ((@($tools.tools | Where-Object { $_.name -eq "nomadmail_get_cross_chat_handoff" }).Count) -eq 1) "cross-chat handoff tool is missing"
    Assert-Flow ((@($tools.tools | Where-Object { $_.name -eq "nomadmail_execute_message_action" }).Count) -eq 1) "execute message action tool is missing"
    Assert-Flow ((@($tools.tools | Where-Object { $_.name -eq "nomadmail_run_agent_automation_cycle" }).Count) -eq 1) "agent automation cycle tool is missing"
    Assert-Flow ((@($tools.tools | Where-Object { $_.name -eq "nomadmail_list_agent_events" }).Count) -eq 1) "agent event listing tool is missing"

    $flowCli = & node $service agent-user-flow | ConvertFrom-Json
    Assert-Flow ($flowCli.status -eq "ok" -and $flowCli.text -like "*Flow 1: First Prompt*" -and $flowCli.text -like "*Flow 5: Daily Mail Query Menu*") "agent user flow CLI output is incomplete"

    $handoffCli = & node $service cross-chat-handoff | ConvertFrom-Json
    Assert-Flow ($handoffCli.status -eq "ok" -and $handoffCli.text -like "*Prompt To Give Another Agent*") "cross-chat handoff CLI output is incomplete"
    Add-Scenario $scenarios "first prompt in fresh workspace" "Show capabilities, storage boundary, helper/tray/MCP state, approval gates, and ask the user to choose one source and one scope."

    Assert-Flow ($flowCli.text -like "*I will set up <source> for <scope>*" -and $flowCli.text -like "*I will not send, delete, move, or save attachments*") "source approval output is missing safety wording"
    Add-Scenario $scenarios "source and scope approval" "Confirm source/scope, say what will be stored locally, and ask before proceeding."

    Assert-Flow ($flowCli.text -like "*Sync/import completed*" -and $flowCli.text -like "*Auto sync is off*") "sync/import completion output is missing"
    Add-Scenario $scenarios "first sync or import" "Report local live/archive counts, last sync/import time, and keep auto sync off."

    Assert-Flow ($flowCli.text -like "*NomadMail is running from the NomadInbox system tray*" -and $flowCli.text -like "*Auto sync is still off until you enable it*") "service/tray output is missing compact status wording"
    Add-Scenario $scenarios "service and tray setup" "Tell the user NomadMail is available from the tray; do not dump endpoints or raw JSON."

    Assert-Flow ($flowCli.text -like "*Show my latest email with content*" -and $flowCli.text -like "*Summarize unread mail from today*" -and $flowCli.text -like "*Find mail that needs my action*" -and $flowCli.text -like "*Draft a reply or new email*" -and $flowCli.text -like "*Open a selected Outlook Desktop message or thread in Outlook*") "daily mail query menu is incomplete"
    Add-Scenario $scenarios "daily mail query choices" "Present latest, unread today/week, needs-action, search-by-topic/sender/date/attachment, low-priority, draft, and Outlook Desktop open options."

    Assert-Flow ($flowCli.text -like "*run one request-scoped live sync*" -and $flowCli.text -like "*the latest email cannot be confirmed*") "latest-email freshness output is missing"
    Add-Scenario $scenarios "latest email freshness" "Sync first for enabled live accounts; if sync fails, say the latest email cannot be confirmed."

    Assert-Flow ($flowCli.text -like "*runtime/agent-scratch*" -and $flowCli.text -like "*source and date range*" -and $flowCli.text -like "*Which group should I open first?*") "broad range report output is missing"
    Add-Scenario $scenarios "broad daily digest or range report" "Resolve the absolute date range, group results, save a range-aware report, and ask which group to open."

    Assert-Flow ($flowCli.text -like "*nomadmail_open_message*" -and $flowCli.text -like "*nomadmail_execute_message_action*" -and $flowCli.text -like "*Approve sending this exact draft?*" -and $flowCli.text -like "*Final confirmation required*") "mail action confirmation output is missing"
    Add-Scenario $scenarios "mail action follow-up" "Open Outlook Desktop messages by EntryID when requested; draft before send; require exact approval for send and double confirmation for trash/delete."

    $prompt = & node $service system-prompt | ConvertFrom-Json
    Assert-Flow ($prompt.status -eq "ok" -and $prompt.text -like "*docs/runbooks/agent-user-flow.md*" -and $prompt.text -like "*Your first response must show*") "startup prompt does not require the user flow"

    $state = & node $service workspace-state | ConvertFrom-Json
    Assert-Flow ($state.status -eq "ok" -and $state.text -like "*agent-user-flow.md*") "workspace state does not mention agent-user-flow"

    $guide = & node $service agent-guide | ConvertFrom-Json
    Assert-Flow ($guide.status -eq "ok" -and $guide.agentUserFlow.text -like "*Daily Mail Query Menu*" -and $guide.crossChatHandoff.text -like "*Prompt To Give Another Agent*" -and (($guide.startupGuidance -join " ") -like "*agentUserFlow.text*") -and (($guide.startupGuidance -join " ") -like "*crossChatHandoff.text*")) "agent guide does not expose user flow and cross-chat handoff"

    $flowHttp = Invoke-RestMethod -Uri "$baseUri/agent-user-flow" -TimeoutSec 5
    Assert-Flow ($flowHttp.status -eq "ok" -and $flowHttp.text -like "*Flow End State*") "HTTP /agent-user-flow output is incomplete"

    $handoffHttp = Invoke-RestMethod -Uri "$baseUri/cross-chat-handoff" -TimeoutSec 5
    Assert-Flow ($handoffHttp.status -eq "ok" -and $handoffHttp.text -like "*Prompt To Give Another Agent*") "HTTP /cross-chat-handoff output is incomplete"

    $guideHttp = Invoke-RestMethod -Uri "$baseUri/agent-guide" -TimeoutSec 5
    Assert-Flow ($guideHttp.status -eq "ok" -and $guideHttp.agentUserFlow.text -like "*Daily Mail Query Menu*" -and $guideHttp.crossChatHandoff.text -like "*Prompt To Give Another Agent*") "HTTP /agent-guide does not embed user flow and cross-chat handoff"

    $search = Invoke-RestMethod -Uri "$baseUri/messages?query=daily%20flow&limit=5" -TimeoutSec 5
    Assert-Flow ($search.status -eq "ok" -and $search.count -ge 1) "archive search did not return imported scenario message"
    $message = @($search.results)[0]
    Assert-Flow ($message.sourceType -eq "archive-import" -and $message.actionMenu.available -eq $false) "archive search result did not expose read-only action menu"
    Assert-Flow ((($message.actionMenu.quickActions -join " ") -like "*summarize*") -and (($message.actionMenu.quickActions -join " ") -like "*find matching live message*")) "archive action menu did not expose read-only choices"

    $messageActions = Invoke-RestMethod -Uri ("$baseUri/message-actions?id=" + [uri]::EscapeDataString($message.id)) -TimeoutSec 5
    Assert-Flow ($messageActions.status -eq "ok" -and $messageActions.actionGuide.actionable -eq $false -and $messageActions.actionGuide.userPrompt -like "*summarize*") "message action guide did not block archive mutation"

    $actionDryRunBody = @{ action = "draft-new"; to = "agent-flow@example.invalid"; subject = "Dry run"; body = "Body"; dryRun = $true } | ConvertTo-Json
    $actionDryRun = Invoke-RestMethod -Method Post -Uri "$baseUri/messages/action" -Body $actionDryRunBody -ContentType "application/json" -TimeoutSec 5
    Assert-Flow ($actionDryRun.status -eq "dryRun" -and $actionDryRun.action -eq "draft-new" -and $actionDryRun.executed -eq $false) "HTTP message action dry-run failed"

    $latestBody = @{ syncFirst = $false; requireContent = $true } | ConvertTo-Json
    $latest = Invoke-RestMethod -Method Post -Uri "$baseUri/messages/latest" -Body $latestBody -ContentType "application/json" -TimeoutSec 5
    Assert-Flow ($latest.status -eq "notFound" -and $latest.freshnessRule -like "*one-shot live sync first*") "latest-email diagnostic read did not preserve freshness guidance"

    $syntheticLiveId = "outlook-desktop:desktop-outlook:agent-flow-live"
    [pscustomobject]@{
        schemaVersion = 2
        id = $syntheticLiveId
        accountId = "desktop-outlook"
        provider = "outlook-desktop"
        providerMessageId = "agent-flow-entry-id"
        conversationId = "agent-flow-conversation"
        folder = "Inbox"
        subject = "Agent automation flow live mail"
        from = [pscustomobject]@{ name = "Flow Sender"; email = "sender@example.com" }
        to = @([pscustomobject]@{ name = "Example User"; email = "user@example.com" })
        receivedAt = "2026-05-06T10:15:00.000Z"
        snippet = "Synthetic live message for assigned-agent automation."
        unread = $true
        flagged = $false
        attachments = @()
        capabilities = @("openInClient", "reply", "replyAll")
        sourceType = "live-sync"
        actionable = $true
    } | ConvertTo-Json -Depth 30 -Compress | Set-Content -LiteralPath (Join-Path $env:NOMADINBOX_DATA_DIR "messages.jsonl") -Encoding UTF8

    $automationBody = @{ assignedAgent = "codex"; limit = 5; syncFirst = $false } | ConvertTo-Json
    $automation = Invoke-RestMethod -Method Post -Uri "$baseUri/agent-events/automation-cycle" -Body $automationBody -ContentType "application/json" -TimeoutSec 5
    Assert-Flow ($automation.status -eq "ok" -and $automation.assignedAgent -eq "codex" -and $automation.createdCount -eq 1 -and $automation.safety -like "*do not imply approval*") "HTTP agent automation cycle did not create a bounded event"
    $pendingEvents = Invoke-RestMethod -Uri "$baseUri/agent-events?assignedAgent=codex&status=pending" -TimeoutSec 5
    Assert-Flow ($pendingEvents.status -eq "ok" -and $pendingEvents.count -eq 1 -and @($pendingEvents.events)[0].messageRefs[0].id -eq $syntheticLiveId) "HTTP agent event listing failed"
    $ackBody = @{ acknowledgedBy = "codex" } | ConvertTo-Json
    $ack = Invoke-RestMethod -Method Post -Uri ("$baseUri/agent-events/" + [uri]::EscapeDataString(@($pendingEvents.events)[0].eventId) + "/ack") -Body $ackBody -ContentType "application/json" -TimeoutSec 5
    Assert-Flow ($ack.status -eq "ok" -and $ack.event.status -eq "acknowledged") "HTTP agent event acknowledgement failed"
    Add-Scenario $scenarios "assigned-agent automation" "NomadInbox queues bounded local mail events for Codex or another assigned agent; the agent pulls and acknowledges them through MCP/HTTP without treating them as action approval."

    $selfTest = & node $service self-test | ConvertFrom-Json
    Assert-Flow ($selfTest.status -eq "ok" -and $selfTest.agentUserFlowStatus -eq "ok") "self-test did not validate agent user flow"

    [pscustomobject]@{
        status = "ok"
        service = "NomadMail"
        dataDir = $env:NOMADINBOX_DATA_DIR
        http = @{
            port = $port
            health = $health.status
            agentUserFlow = $flowHttp.status
            searchCount = $search.count
            latestDiagnosticNoLiveData = $latest.status
        }
        scenarios = $scenarios
    } | ConvertTo-Json -Depth 8
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
