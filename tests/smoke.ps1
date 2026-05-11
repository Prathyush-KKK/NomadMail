$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $repoRoot "scripts\nomad-inbox.ps1"
$previousDataDir = $env:NOMADINBOX_DATA_DIR
$previousUserCulture = $env:NOMADINBOX_USER_CULTURE
$previousUserLocale = $env:NOMADINBOX_USER_LOCALE
$previousUserTimeZone = $env:NOMADINBOX_USER_TIME_ZONE
$previousUserTimeZoneIana = $env:NOMADINBOX_USER_TIME_ZONE_IANA
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

    $installRoot = Join-Path $testRoot "agent-helper"
    $install = & $cli install windows-helper --data-dir $env:NOMADINBOX_DATA_DIR --install-root $installRoot --skip-user-env | ConvertFrom-Json
    if ($install.status -ne "ok" -or -not (Test-Path -LiteralPath $install.helperPath) -or -not (Test-Path -LiteralPath $install.statusPath) -or $install.startup.registered -ne $false) {
        throw "windows helper install failed"
    }
    if ($install.environment.registered -ne $false -or $install.environment.skipped -ne $true) {
        throw "windows helper test install should skip user environment registration"
    }
    $envStatus = & $cli env status | ConvertFrom-Json
    if ($envStatus.status -ne "ok" -or -not $envStatus.bootstrap.httpHandoffUrl) {
        throw "environment status failed"
    }

    $trayStatus = & $cli tray status | ConvertFrom-Json
    if ($trayStatus.status -ne "ok" -or $trayStatus.trayClient -ne "compiled" -or -not $trayStatus.installedExePath) {
        throw "tray status failed"
    }

    $nodeInstallRoot = Join-Path $testRoot "agent-helper-node"
    $nodeInstall = & node (Join-Path $repoRoot "service\nomadmail-service.mjs") install-windows-helper --data-dir $env:NOMADINBOX_DATA_DIR --install-root $nodeInstallRoot --skip-user-env | ConvertFrom-Json
    if ($nodeInstall.status -ne "ok" -or -not (Test-Path -LiteralPath $nodeInstall.helperPath) -or -not (Test-Path -LiteralPath $nodeInstall.statusPath) -or $nodeInstall.startup.registered -ne $false) {
        throw "node helper install command failed"
    }

    $singleSync = & $cli sync once --account-id personal-gmail | ConvertFrom-Json
    if ($singleSync.status -ne "ok" -or $singleSync.accountCount -ne 1) { throw "account-scoped sync failed" }

    $status = & $cli service status | ConvertFrom-Json
    if ($status.status -ne "ok") { throw "service status failed" }

    $backup = & $cli backup status | ConvertFrom-Json
    if ($backup.status -ne "ok" -or -not $backup.providerRawPath -or $null -eq $backup.providerRawSnapshots) { throw "backup status failed" }

    $importStatus = & $cli import status | ConvertFrom-Json
    if ($null -eq $importStatus.service) { throw "import status failed" }

    $sample = & $cli sample message | ConvertFrom-Json
    if ($sample.provider -ne "sample") { throw "sample message failed" }

    $syntheticOutlookId = "outlook-desktop:desktop-outlook:synthetic-open"
    $syntheticOutlookMessage = [pscustomobject]@{
        schemaVersion = 2
        id = $syntheticOutlookId
        accountId = "desktop-outlook"
        provider = "outlook-desktop"
        providerMessageId = "synthetic-outlook-entry-id"
        conversationId = "synthetic-conversation"
        threadKey = "synthetic-conversation"
        folder = "Inbox"
        subject = "Synthetic Outlook open target"
        from = [pscustomobject]@{ name = "Example Sender"; email = "sender@example.com" }
        to = @([pscustomobject]@{ name = "Example User"; email = "user@example.com" })
        cc = @()
        receivedAt = "2026-04-15T10:30:00.000Z"
        sentAt = $null
        snippet = "Synthetic navigation target for dry-run open tests."
        bodyText = $null
        bodyHtml = $null
        bodyTextAvailable = $false
        bodyHtmlAvailable = $false
        headers = @{}
        unread = $false
        flagged = $false
        importance = $null
        categories = @()
        attachments = @()
        capabilities = @("openInClient", "reply", "replyAll")
        sourceType = "live-sync"
        sourceProvider = "outlook-desktop"
        actionable = $true
    }
    New-Item -ItemType Directory -Force -Path $env:NOMADINBOX_DATA_DIR | Out-Null
    $syntheticOutlookMessage | ConvertTo-Json -Depth 30 -Compress | Set-Content -LiteralPath (Join-Path $env:NOMADINBOX_DATA_DIR "messages.jsonl") -Encoding UTF8
    $openDryRun = & $cli message open --id $syntheticOutlookId --dry-run | ConvertFrom-Json
    if ($openDryRun.status -ne "dryRun" -or $openDryRun.providerMessageId -ne "synthetic-outlook-entry-id" -or $openDryRun.opened -ne $false) {
        throw "Outlook message dry-run open failed"
    }
    $openThreadDryRun = & $cli message open --conversation-id "synthetic-conversation" --latest-in-thread --dry-run | ConvertFrom-Json
    if ($openThreadDryRun.status -ne "dryRun" -or $openThreadDryRun.id -ne $syntheticOutlookId) {
        throw "Outlook conversation dry-run open failed"
    }
    $draftReplyDryRun = & $cli message action --action draft-reply --id $syntheticOutlookId --body "Acknowledged." --dry-run | ConvertFrom-Json
    if ($draftReplyDryRun.status -ne "dryRun" -or $draftReplyDryRun.action -ne "draft-reply" -or $draftReplyDryRun.executed -ne $false) {
        throw "Outlook draft reply dry-run failed"
    }
    $draftNewDryRun = & $cli message action --action draft-new --to user@example.com --subject "Synthetic draft" --body "Body" --dry-run | ConvertFrom-Json
    if ($draftNewDryRun.status -ne "dryRun" -or $draftNewDryRun.action -ne "draft-new") {
        throw "Outlook draft new dry-run failed"
    }
    $markPending = & $cli message action --action mark-read --id $syntheticOutlookId | ConvertFrom-Json
    if ($markPending.status -ne "pendingConfirmation" -or $markPending.confirmationRequirement -ne "single" -or $markPending.requiredFlag -ne "--confirm-action") {
        throw "Outlook mark-read confirmation gate failed"
    }
    $trashPending = & $cli message action --action trash --id $syntheticOutlookId | ConvertFrom-Json
    if ($trashPending.status -ne "pendingConfirmation" -or $trashPending.confirmationRequirement -ne "double" -or $trashPending.requiredPhrase -ne "trash:$syntheticOutlookId") {
        throw "Outlook trash double-confirmation gate failed"
    }
    $sendDraftDryRun = & $cli message action --action send-draft --draft-entry-id "synthetic-draft-entry-id" --dry-run | ConvertFrom-Json
    if ($sendDraftDryRun.status -ne "dryRun" -or $sendDraftDryRun.action -ne "send-draft" -or $sendDraftDryRun.draftEntryId -ne "synthetic-draft-entry-id") {
        throw "Outlook send draft dry-run failed"
    }

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

    $env:NOMADINBOX_USER_CULTURE = "en-IN"
    Remove-Item Env:\NOMADINBOX_USER_LOCALE -ErrorAction SilentlyContinue
    Remove-Item Env:\NOMADINBOX_USER_TIME_ZONE_IANA -ErrorAction SilentlyContinue
    $env:NOMADINBOX_USER_TIME_ZONE = "UTC"
    $localeJsonlPath = Join-Path $testRoot "locale-date.jsonl"
    [pscustomobject]@{
        id = "locale-date-1"
        providerMessageId = "locale-date-1"
        subject = "Locale date parse"
        from = [pscustomobject]@{ email = "sender@example.com" }
        receivedAt = "05/06/2026 15:30"
        snippet = "Locale-specific date parsing check."
    } | ConvertTo-Json -Compress | Set-Content -LiteralPath $localeJsonlPath -Encoding UTF8

    $localeImport = & $cli import jsonl --path $localeJsonlPath --source smoke-locale --max-messages 1 | ConvertFrom-Json
    if ($localeImport.status -ne "ok" -or -not $localeImport.timeContext -or $localeImport.timeContext.cultureName -ne "en-IN") {
        throw "locale-aware import status failed"
    }
    $localeRecord = [System.IO.File]::ReadAllLines((Join-Path $env:NOMADINBOX_DATA_DIR "archive-messages.jsonl")) |
        ForEach-Object { $_ | ConvertFrom-Json } |
        Where-Object { $_.subject -eq "Locale date parse" } |
        Select-Object -First 1
    if ($null -eq $localeRecord -or $localeRecord.receivedAt -notlike "2026-06-05T15:30*Z") {
        throw "locale-aware date parsing failed"
    }

    $env:NOMADINBOX_USER_TIME_ZONE = "India Standard Time"
    $localeIndiaJsonlPath = Join-Path $testRoot "locale-india-date.jsonl"
    [pscustomobject]@{
        id = "locale-india-date-1"
        providerMessageId = "locale-india-date-1"
        subject = "Locale India time zone parse"
        from = [pscustomobject]@{ email = "sender@example.com" }
        receivedAt = "05/06/2026 15:30"
        snippet = "Locale-specific time zone conversion check."
    } | ConvertTo-Json -Compress | Set-Content -LiteralPath $localeIndiaJsonlPath -Encoding UTF8

    $localeIndiaImport = & $cli import jsonl --path $localeIndiaJsonlPath --source smoke-locale-india --max-messages 1 | ConvertFrom-Json
    if ($localeIndiaImport.status -ne "ok" -or -not $localeIndiaImport.timeContext -or $localeIndiaImport.timeContext.timeZoneId -notin @("India Standard Time", "Asia/Kolkata", "Asia/Calcutta")) {
        throw "locale-aware time zone import status failed"
    }
    $localeIndiaRecord = [System.IO.File]::ReadAllLines((Join-Path $env:NOMADINBOX_DATA_DIR "archive-messages.jsonl")) |
        ForEach-Object { $_ | ConvertFrom-Json } |
        Where-Object { $_.subject -eq "Locale India time zone parse" } |
        Select-Object -First 1
    if ($null -eq $localeIndiaRecord -or $localeIndiaRecord.receivedAt -notlike "2026-06-05T10:00*Z") {
        throw "locale-aware time zone conversion failed"
    }

    $agentService = & node (Join-Path $repoRoot "service\nomadmail-service.mjs") self-test | ConvertFrom-Json
    if ($agentService.status -ne "ok" -or $agentService.toolCount -lt 10 -or $agentService.agentGuideStatus -ne "ok" -or $agentService.agentUserFlowStatus -ne "ok" -or $agentService.crossChatHandoffStatus -ne "ok" -or $agentService.agentEventsStatus -ne "ok" -or -not $agentService.latestMessageStatus -or $agentService.messageActionsStatus -ne "ok" -or -not $agentService.openMessageStatus -or $agentService.executeMessageActionStatus -ne "dryRun") {
        throw "agent service self-test failed"
    }

    $tools = & node (Join-Path $repoRoot "service\nomadmail-service.mjs") tools | ConvertFrom-Json
    if (@($tools.tools | Where-Object { $_.name -eq "nomadmail_get_latest_message" }).Count -ne 1) {
        throw "latest message tool missing"
    }
    if (@($tools.tools | Where-Object { $_.name -eq "nomadmail_get_message_actions" }).Count -ne 1) {
        throw "message actions tool missing"
    }
    if (@($tools.tools | Where-Object { $_.name -eq "nomadmail_open_message" }).Count -ne 1) {
        throw "open message tool missing"
    }
    if (@($tools.tools | Where-Object { $_.name -eq "nomadmail_execute_message_action" }).Count -ne 1) {
        throw "execute message action tool missing"
    }
    if (@($tools.tools | Where-Object { $_.name -eq "nomadmail_get_agent_user_flow" }).Count -ne 1) {
        throw "agent user flow tool missing"
    }
    if (@($tools.tools | Where-Object { $_.name -eq "nomadmail_get_cross_chat_handoff" }).Count -ne 1) {
        throw "cross-chat handoff tool missing"
    }
    if (@($tools.tools | Where-Object { $_.name -eq "nomadmail_run_agent_automation_cycle" }).Count -ne 1) {
        throw "agent automation cycle tool missing"
    }
    if (@($tools.tools | Where-Object { $_.name -eq "nomadmail_list_agent_events" }).Count -ne 1) {
        throw "agent events list tool missing"
    }
    if (@($tools.tools | Where-Object { $_.name -eq "nomadmail_ack_agent_event" }).Count -ne 1) {
        throw "agent event ack tool missing"
    }

    $automation = & node (Join-Path $repoRoot "service\nomadmail-service.mjs") agent-automation-cycle --assigned-agent codex --limit 5 | ConvertFrom-Json
    if ($automation.status -ne "ok" -or $automation.assignedAgent -ne "codex" -or $automation.createdCount -lt 1 -or $automation.safety -notlike "*do not imply approval*") {
        throw "agent automation cycle did not create a local event"
    }
    $events = & node (Join-Path $repoRoot "service\nomadmail-service.mjs") agent-events --assigned-agent codex --status pending | ConvertFrom-Json
    if ($events.status -ne "ok" -or $events.count -lt 1 -or @($events.events)[0].messageRefs[0].id -ne $syntheticOutlookId) {
        throw "agent event listing failed"
    }
    $eventId = @($events.events)[0].eventId
    $ack = & node (Join-Path $repoRoot "service\nomadmail-service.mjs") ack-agent-event --event-id $eventId --acknowledged-by codex | ConvertFrom-Json
    if ($ack.status -ne "ok" -or $ack.event.status -ne "acknowledged" -or $ack.event.acknowledgedBy -ne "codex") {
        throw "agent event acknowledgement failed"
    }

    $agentGuide = & node (Join-Path $repoRoot "service\nomadmail-service.mjs") agent-guide | ConvertFrom-Json
    if ($agentGuide.status -ne "ok" -or -not $agentGuide.storageBoundary.rule -or -not $agentGuide.storageBoundary.rawProviderStore -or $agentGuide.storageBoundary.normalizationRule -notlike "*provider-raw.jsonl*" -or -not $agentGuide.agentAutomation -or $agentGuide.agentAutomation.codexPattern -notlike "*Codex MCP server*" -or -not $agentGuide.startupSystemPrompt.text -or -not $agentGuide.workspaceState.text -or -not $agentGuide.agentUserFlow.text -or $agentGuide.agentUserFlow.text -notlike "*Daily Mail Query Menu*" -or -not $agentGuide.crossChatHandoff.text -or $agentGuide.crossChatHandoff.text -notlike "*nomadmail_get_cross_chat_handoff*" -or -not $agentGuide.timeHandling.parsingRule -or $agentGuide.timeHandling.timeZone -notin @("Asia/Kolkata", "Asia/Calcutta") -or (($agentGuide.liveSyncGuidance -join " ") -notlike "*nomadmail_get_latest_message*") -or -not $agentGuide.generatedReportNaming -or $agentGuide.generatedReportNaming.rule -notlike "*date or time range*" -or -not $agentGuide.mailActionGuidance -or $agentGuide.mailActionGuidance.permissionModel.deleteApproval -notlike "*two explicit confirmations*" -or $agentGuide.mailActionGuidance.implementationNote -notlike "*execute Outlook Desktop draft*") {
        throw "agent guide failed"
    }

    $systemPrompt = & node (Join-Path $repoRoot "service\nomadmail-service.mjs") system-prompt | ConvertFrom-Json
    if ($systemPrompt.status -ne "ok" -or $systemPrompt.promptType -ne "system" -or $systemPrompt.text -notlike "*docs/runbooks/agent-user-flow.md*" -or $systemPrompt.text -notlike "*Your first response must show*" -or $systemPrompt.text -notlike "*Windows helper and tray status*" -or $systemPrompt.text -notlike "*runtime/agent-scratch*" -or $systemPrompt.text -notlike "*MCP stdio tools are launched by each calling agent*" -or $systemPrompt.text -notlike "*Do not dump endpoint lists*" -or $systemPrompt.text -notlike "*user's locale and time zone*" -or $systemPrompt.text -notlike "*latest email*" -or $systemPrompt.text -notlike "*Trash/delete requires double explicit approval*" -or $systemPrompt.text -notlike "*unread-outlook-2026-04-29-to-2026-05-06.md*" -or $systemPrompt.text -notlike "*--register-startup --show-popup*") {
        throw "startup system prompt failed"
    }

    $agentUserFlow = & node (Join-Path $repoRoot "service\nomadmail-service.mjs") agent-user-flow | ConvertFrom-Json
    if ($agentUserFlow.status -ne "ok" -or $agentUserFlow.text -notlike "*Flow 1: First Prompt*" -or $agentUserFlow.text -notlike "*Flow 5: Daily Mail Query Menu*") {
        throw "agent user flow failed"
    }

    $crossChatHandoff = & node (Join-Path $repoRoot "service\nomadmail-service.mjs") cross-chat-handoff | ConvertFrom-Json
    if ($crossChatHandoff.status -ne "ok" -or $crossChatHandoff.text -notlike "*Prompt To Give Another Agent*" -or $crossChatHandoff.text -notlike "*nomadmail_get_cross_chat_handoff*") {
        throw "cross-chat handoff failed"
    }

    $workspaceState = & node (Join-Path $repoRoot "service\nomadmail-service.mjs") workspace-state | ConvertFrom-Json
    if ($workspaceState.status -ne "ok" -or $workspaceState.text -notlike "*NomadInbox Workspace State*" -or $workspaceState.text -notlike "*Resume Rules For Agents*") {
        throw "workspace state failed"
    }

    $releaseOutputDir = Join-Path $testRoot "dist"
    $release = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\build-windows-installer.ps1") -Version "0.0.0-smoke" -OutputDir $releaseOutputDir -AllowDirty | ConvertFrom-Json
    if ($release.status -ne "ok" -or -not (Test-Path -LiteralPath $release.packagePath) -or -not (Test-Path -LiteralPath $release.manifestPath) -or $release.includedFileCount -lt 10) {
        throw "versioned installer package failed"
    }

    [pscustomobject]@{
        status = "ok"
        tests = @("doctor", "providers list", "accounts list", "install windows helper", "environment status", "tray status", "node install windows helper", "sync account", "service status", "backup status", "import status", "sample message", "outlook message dry-run open", "outlook conversation dry-run open", "outlook action dry-runs", "outlook action confirmation gates", "import eml", "locale date import", "locale time zone import", "agent service self-test", "latest message tool", "message actions tool", "open message tool", "execute message action tool", "agent user flow tool", "cross-chat handoff tool", "agent automation event tools", "agent automation cycle", "agent event acknowledgement", "agent guide", "startup system prompt", "agent user flow", "cross-chat handoff", "workspace state", "versioned installer package")
    } | ConvertTo-Json -Depth 5
} finally {
    if ($null -eq $previousDataDir) {
        Remove-Item Env:\NOMADINBOX_DATA_DIR -ErrorAction SilentlyContinue
    } else {
        $env:NOMADINBOX_DATA_DIR = $previousDataDir
    }
    if ($null -eq $previousUserCulture) {
        Remove-Item Env:\NOMADINBOX_USER_CULTURE -ErrorAction SilentlyContinue
    } else {
        $env:NOMADINBOX_USER_CULTURE = $previousUserCulture
    }
    if ($null -eq $previousUserLocale) {
        Remove-Item Env:\NOMADINBOX_USER_LOCALE -ErrorAction SilentlyContinue
    } else {
        $env:NOMADINBOX_USER_LOCALE = $previousUserLocale
    }
    if ($null -eq $previousUserTimeZone) {
        Remove-Item Env:\NOMADINBOX_USER_TIME_ZONE -ErrorAction SilentlyContinue
    } else {
        $env:NOMADINBOX_USER_TIME_ZONE = $previousUserTimeZone
    }
    if ($null -eq $previousUserTimeZoneIana) {
        Remove-Item Env:\NOMADINBOX_USER_TIME_ZONE_IANA -ErrorAction SilentlyContinue
    } else {
        $env:NOMADINBOX_USER_TIME_ZONE_IANA = $previousUserTimeZoneIana
    }
    Set-Location $repoRoot
    try {
        Start-Sleep -Milliseconds 200
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction Stop
    } catch {
    }
}
