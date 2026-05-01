$script:ServiceName = "NomadInbox"
$script:Version = "0.1.0"

function Get-NomadInboxRoot {
    Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

function Resolve-NomadInboxPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    return $resolved
}

function New-NomadInboxDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)
    $resolved = Resolve-NomadInboxPath $Path
    New-Item -ItemType Directory -Force -Path $resolved | Out-Null
    return $resolved
}

function Get-NomadInboxDataDir {
    if (-not [string]::IsNullOrWhiteSpace($env:NOMADINBOX_DATA_DIR)) {
        return (New-NomadInboxDirectory $env:NOMADINBOX_DATA_DIR)
    }
    return (New-NomadInboxDirectory (Join-Path (Get-NomadInboxRoot) "data"))
}

function Get-NomadInboxMessagesPath { Join-Path (Get-NomadInboxDataDir) "messages.jsonl" }
function Get-NomadInboxActionsPath { Join-Path (Get-NomadInboxDataDir) "actions.jsonl" }
function Get-NomadInboxStatusPath { Join-Path (Get-NomadInboxDataDir) "sync-status.json" }
function Get-NomadInboxPidPath { Join-Path (Get-NomadInboxDataDir) "sync-worker.pid" }
function Get-NomadInboxWorkerLogPath { Join-Path (Get-NomadInboxDataDir) "sync-worker.log" }
function Get-NomadInboxAccountsConfigPath { Join-Path (Get-NomadInboxRoot) "config\accounts.json" }
function Get-NomadInboxAccountsExamplePath { Join-Path (Get-NomadInboxRoot) "config\accounts.example.json" }

function Initialize-NomadInbox {
    $dataDir = Get-NomadInboxDataDir
    $attachmentsDir = New-NomadInboxDirectory (Join-Path $dataDir "attachments")
    foreach ($file in @((Get-NomadInboxMessagesPath), (Get-NomadInboxActionsPath))) {
        if (-not (Test-Path -LiteralPath $file)) {
            New-Item -ItemType File -Path $file | Out-Null
        }
    }
    [pscustomobject]@{
        status = "ok"
        service = $script:ServiceName
        version = $script:Version
        dataDir = $dataDir
        messagesPath = Get-NomadInboxMessagesPath
        actionsPath = Get-NomadInboxActionsPath
        attachmentsDir = $attachmentsDir
    }
}

function Initialize-NomadInboxAccountsConfig {
    $configPath = Get-NomadInboxAccountsConfigPath
    $created = $false
    if (-not (Test-Path -LiteralPath $configPath)) {
        Copy-Item -LiteralPath (Get-NomadInboxAccountsExamplePath) -Destination $configPath
        $created = $true
    }
    [pscustomobject]@{
        status = "ok"
        service = $script:ServiceName
        accountsConfigPath = $configPath
        created = $created
        note = "Local account sync config is ignored by git. Enable only the accounts you want background sync to poll."
    }
}

function Read-NomadInboxAccountsConfig {
    $configPath = Get-NomadInboxAccountsConfigPath
    if (-not (Test-Path -LiteralPath $configPath)) {
        return (Get-Content -LiteralPath (Get-NomadInboxAccountsExamplePath) -Raw | ConvertFrom-Json)
    }
    return (Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json)
}

function Get-NomadInboxAccounts {
    $config = Read-NomadInboxAccountsConfig
    $accounts = @($config.accounts | ForEach-Object {
        [pscustomobject]@{
            id = $_.id
            displayName = $_.displayName
            provider = $_.provider
            enabled = [bool]$_.enabled
            folder = $_.folder
            queryConfigured = -not [string]::IsNullOrWhiteSpace($_.query)
            limit = $_.limit
            intervalSeconds = if ($_.intervalSeconds) { $_.intervalSeconds } else { $config.defaultIntervalSeconds }
        }
    })
    [pscustomobject]@{
        status = "ok"
        service = $script:ServiceName
        configPath = Get-NomadInboxAccountsConfigPath
        configExists = Test-Path -LiteralPath (Get-NomadInboxAccountsConfigPath)
        defaultIntervalSeconds = $config.defaultIntervalSeconds
        accounts = $accounts
    }
}

function Get-NomadInboxProviders {
    $providers = @(
        [pscustomobject]@{
            id = "gmail-api"
            name = "Gmail API"
            runtime = "Google Gmail REST API"
            auth = "OAuth Desktop client or Workspace delegation"
            status = if ([string]::IsNullOrWhiteSpace($env:NOMADINBOX_GMAIL_CLIENT_SECRET_JSON)) { "unconfigured" } else { "configured" }
            defaultScopes = "gmail.readonly"
            capabilities = @("sync", "search", "get", "attachments", "draft", "send-confirmed", "mark-read", "star", "move")
        },
        [pscustomobject]@{
            id = "outlook-graph"
            name = "Outlook Graph"
            runtime = "Microsoft Graph Mail API"
            auth = "Microsoft OAuth device-code or delegated OAuth"
            status = if ([string]::IsNullOrWhiteSpace($env:NOMADINBOX_GRAPH_CLIENT_ID)) { "unconfigured" } else { "configured" }
            defaultScopes = "User.Read Mail.Read Mail.ReadWrite Mail.Send"
            capabilities = @("sync", "search", "get", "attachments", "draft", "send-confirmed", "mark-read", "flag", "move")
        },
        [pscustomobject]@{
            id = "outlook-desktop"
            name = "Outlook Desktop"
            runtime = "Windows Outlook COM"
            auth = "Local signed-in Outlook profile"
            status = "profile-dependent"
            defaultScopes = "local-profile"
            capabilities = @("sync", "search", "get", "attachments", "draft", "send-confirmed", "mark-read", "flag", "move")
        }
    )
    [pscustomobject]@{
        status = "ok"
        service = $script:ServiceName
        providers = $providers
    }
}

function Get-NomadInboxConfigStatus {
    [pscustomobject]@{
        status = "ok"
        service = $script:ServiceName
        dataDirConfigured = -not [string]::IsNullOrWhiteSpace($env:NOMADINBOX_DATA_DIR)
        defaultProvider = if ([string]::IsNullOrWhiteSpace($env:NOMADINBOX_DEFAULT_PROVIDER)) { "gmail-api" } else { $env:NOMADINBOX_DEFAULT_PROVIDER }
        gmailClientConfigured = -not [string]::IsNullOrWhiteSpace($env:NOMADINBOX_GMAIL_CLIENT_SECRET_JSON)
        graphClientConfigured = -not [string]::IsNullOrWhiteSpace($env:NOMADINBOX_GRAPH_CLIENT_ID)
        outlookDesktopProfile = if ([string]::IsNullOrWhiteSpace($env:NOMADINBOX_OUTLOOK_DESKTOP_PROFILE)) { "default" } else { $env:NOMADINBOX_OUTLOOK_DESKTOP_PROFILE }
        localConfigExpected = Join-Path (Get-NomadInboxRoot) "config\nomad-inbox.ps1"
        localConfigExists = Test-Path -LiteralPath (Join-Path (Get-NomadInboxRoot) "config\nomad-inbox.ps1")
    }
}

function Read-NomadInboxSyncStatus {
    $path = Get-NomadInboxStatusPath
    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{
            service = $script:ServiceName
            worker = "stopped"
            lastRunAt = $null
            nextRunAt = $null
            accounts = @()
            updatedAt = (Get-Date).ToUniversalTime().ToString("o")
        }
    }
    $raw = Get-Content -LiteralPath $path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-NomadInboxSyncStatus {
    param($Status)
    Initialize-NomadInbox | Out-Null
    $Status | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath (Get-NomadInboxStatusPath) -Encoding UTF8
    return $Status
}

function Write-NomadInboxActionRecord {
    param(
        [string]$ActionType,
        [string]$Status,
        [hashtable]$InputObject,
        [hashtable]$ResultObject,
        [string]$ErrorMessage
    )
    Initialize-NomadInbox | Out-Null
    $provider = if ($InputObject.ContainsKey("provider")) { $InputObject.provider } else { "sample" }
    $record = [pscustomobject]@{
        actionId = [guid]::NewGuid().ToString()
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        provider = $provider
        messageId = $null
        draftId = $null
        actionType = $ActionType
        requiresUserConfirmation = $false
        confirmedByUser = $false
        status = $Status
        input = $InputObject
        result = $ResultObject
        error = $ErrorMessage
    }
    ($record | ConvertTo-Json -Depth 50 -Compress) | Add-Content -LiteralPath (Get-NomadInboxActionsPath)
    return $record
}

function Invoke-NomadInboxAccountSync {
    param($Account)
    $startedAt = (Get-Date).ToUniversalTime()
    if (-not [bool]$Account.enabled) {
        return [pscustomobject]@{
            accountId = $Account.id
            displayName = $Account.displayName
            provider = $Account.provider
            status = "skipped"
            reason = "accountDisabled"
            synced = 0
            startedAt = $startedAt.ToString("o")
            finishedAt = (Get-Date).ToUniversalTime().ToString("o")
        }
    }

    if ($Account.provider -eq "sample") {
        $sample = New-NomadInboxSampleMessage
        $sample.id = "sample:" + $Account.id + ":" + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")
        ($sample | ConvertTo-Json -Depth 50 -Compress) | Add-Content -LiteralPath (Get-NomadInboxMessagesPath)
        Write-NomadInboxActionRecord -ActionType "sync" -Status "success" -InputObject @{ accountId = $Account.id; provider = $Account.provider } -ResultObject @{ synced = 1 } -ErrorMessage $null | Out-Null
        return [pscustomobject]@{
            accountId = $Account.id
            displayName = $Account.displayName
            provider = $Account.provider
            status = "ok"
            reason = $null
            synced = 1
            startedAt = $startedAt.ToString("o")
            finishedAt = (Get-Date).ToUniversalTime().ToString("o")
        }
    }

    Write-NomadInboxActionRecord -ActionType "sync" -Status "dryRun" -InputObject @{ accountId = $Account.id; provider = $Account.provider; folder = $Account.folder; limit = $Account.limit } -ResultObject @{ synced = 0; reason = "providerAdapterNotInstalled" } -ErrorMessage $null | Out-Null
    [pscustomobject]@{
        accountId = $Account.id
        displayName = $Account.displayName
        provider = $Account.provider
        status = "pendingProviderAdapter"
        reason = "Provider adapter is declared but not installed in this clean bootstrap yet."
        synced = 0
        startedAt = $startedAt.ToString("o")
        finishedAt = (Get-Date).ToUniversalTime().ToString("o")
    }
}

function Test-NomadInboxWorkerRunning {
    $pidPath = Get-NomadInboxPidPath
    if (-not (Test-Path -LiteralPath $pidPath)) { return $false }
    $pidText = (Get-Content -LiteralPath $pidPath -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($pidText)) { return $false }
    try {
        $process = Get-Process -Id ([int]$pidText) -ErrorAction Stop
        return -not $process.HasExited
    } catch {
        return $false
    }
}

function Invoke-NomadInboxSyncOnce {
    param(
        [string]$AccountId = "",
        [switch]$WorkerRunning
    )
    Initialize-NomadInbox | Out-Null
    $config = Read-NomadInboxAccountsConfig
    $accounts = @($config.accounts)
    if (-not [string]::IsNullOrWhiteSpace($AccountId)) {
        $accounts = @($accounts | Where-Object { $_.id -eq $AccountId })
        if ($accounts.Count -eq 0) { throw "Account not found: $AccountId" }
    }
    $results = @($accounts | ForEach-Object { Invoke-NomadInboxAccountSync $_ })
    $now = (Get-Date).ToUniversalTime()
    $enabledIntervals = @($accounts | Where-Object { [bool]$_.enabled } | ForEach-Object { if ($_.intervalSeconds) { [int]$_.intervalSeconds } elseif ($config.defaultIntervalSeconds) { [int]$config.defaultIntervalSeconds } else { 300 } })
    $interval = if ($enabledIntervals.Count -gt 0) { ($enabledIntervals | Measure-Object -Minimum).Minimum } elseif ($config.defaultIntervalSeconds) { [int]$config.defaultIntervalSeconds } else { 300 }
    $status = [pscustomobject]@{
        service = $script:ServiceName
        worker = if ($WorkerRunning -or (Test-NomadInboxWorkerRunning)) { "running" } else { "stopped" }
        lastRunAt = $now.ToString("o")
        nextRunAt = $now.AddSeconds($interval).ToString("o")
        accounts = $results
        updatedAt = $now.ToString("o")
    }
    Write-NomadInboxSyncStatus $status | Out-Null
    [pscustomobject]@{
        status = "ok"
        service = $script:ServiceName
        accountCount = $results.Count
        results = $results
        statusPath = Get-NomadInboxStatusPath
    }
}

function Get-NomadInboxServiceStatus {
    $pidPath = Get-NomadInboxPidPath
    $pidValue = $null
    if (Test-Path -LiteralPath $pidPath) {
        $pidText = (Get-Content -LiteralPath $pidPath -Raw).Trim()
        if (-not [string]::IsNullOrWhiteSpace($pidText)) { $pidValue = [int]$pidText }
    }
    [pscustomobject]@{
        status = "ok"
        service = $script:ServiceName
        worker = if (Test-NomadInboxWorkerRunning) { "running" } else { "stopped" }
        pid = $pidValue
        pidPath = $pidPath
        statusPath = Get-NomadInboxStatusPath
        logPath = Get-NomadInboxWorkerLogPath
        syncStatus = Read-NomadInboxSyncStatus
    }
}

function Start-NomadInboxService {
    param([int]$IntervalSeconds = 0)
    Initialize-NomadInbox | Out-Null
    Initialize-NomadInboxAccountsConfig | Out-Null
    if (Test-NomadInboxWorkerRunning) {
        return Get-NomadInboxServiceStatus
    }
    $worker = Join-Path (Get-NomadInboxRoot) "scripts\nomad-inbox-worker.ps1"
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $worker)
    if ($IntervalSeconds -gt 0) { $args += @("-IntervalSeconds", [string]$IntervalSeconds) }
    $logPath = Get-NomadInboxWorkerLogPath
    $errPath = Join-Path (Get-NomadInboxDataDir) "sync-worker.err.log"
    $process = Start-Process -FilePath "powershell.exe" -ArgumentList $args -WorkingDirectory (Get-NomadInboxRoot) -WindowStyle Hidden -RedirectStandardOutput $logPath -RedirectStandardError $errPath -PassThru
    $process.Id | Set-Content -LiteralPath (Get-NomadInboxPidPath) -Encoding ASCII
    for ($i = 0; $i -lt 10; $i++) {
        $status = Read-NomadInboxSyncStatus
        if ($null -ne $status -and $status.worker -eq "running") { break }
        Start-Sleep -Milliseconds 300
    }
    Get-NomadInboxServiceStatus
}

function Stop-NomadInboxService {
    $pidPath = Get-NomadInboxPidPath
    $stopped = $false
    if (Test-Path -LiteralPath $pidPath) {
        $pidText = (Get-Content -LiteralPath $pidPath -Raw).Trim()
        if (-not [string]::IsNullOrWhiteSpace($pidText)) {
            try {
                Stop-Process -Id ([int]$pidText) -Force -ErrorAction Stop
                $stopped = $true
            } catch {
            }
        }
        Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    }
    $status = Read-NomadInboxSyncStatus
    if ($null -ne $status) {
        $status.worker = "stopped"
        $status.updatedAt = (Get-Date).ToUniversalTime().ToString("o")
        Write-NomadInboxSyncStatus $status | Out-Null
    }
    [pscustomobject]@{
        status = "ok"
        service = $script:ServiceName
        stopped = $stopped
        worker = "stopped"
    }
}

function Test-NomadInbox {
    $root = Get-NomadInboxRoot
    $required = @(
        "README.md",
        "schemas\message.v1.json",
        "schemas\action.v1.json",
        "config\nomad-inbox.example.ps1",
        "config\accounts.example.json",
        "docs\ARCHITECTURE.md",
        "docs\PRODUCT_SPEC.md"
    )
    $missing = @()
    foreach ($path in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $path))) {
            $missing += $path
        }
    }
    [pscustomobject]@{
        status = if ($missing.Count -eq 0) { "ok" } else { "missing" }
        service = $script:ServiceName
        version = $script:Version
        root = $root
        missing = $missing
        config = Get-NomadInboxConfigStatus
    }
}

function Get-NomadInboxSchemas {
    $root = Get-NomadInboxRoot
    [pscustomobject]@{
        status = "ok"
        schemas = @(
            [pscustomobject]@{ name = "message.v1"; path = Join-Path $root "schemas\message.v1.json" },
            [pscustomobject]@{ name = "action.v1"; path = Join-Path $root "schemas\action.v1.json" }
        )
    }
}

function New-NomadInboxSampleMessage {
    [pscustomobject]@{
        id = "sample:message-001"
        provider = "sample"
        providerMessageId = "message-001"
        conversationId = "thread-001"
        folder = "Inbox"
        subject = "Welcome to NomadInbox"
        from = [pscustomobject]@{ name = "NomadInbox"; email = "hello@example.com" }
        to = @([pscustomobject]@{ name = "Example User"; email = "user@example.com" })
        cc = @()
        receivedAt = (Get-Date).ToUniversalTime().ToString("o")
        sentAt = $null
        snippet = "This is a redacted sample message for schema testing."
        bodyText = "This sample proves the agent-readable message contract without using real mailbox data."
        bodyHtml = $null
        headers = @{}
        unread = $true
        flagged = $false
        importance = $null
        categories = @("sample")
        attachments = @()
        capabilities = @("reply", "replyAll", "markRead", "markUnread")
    }
}

Export-ModuleMember -Function `
    Initialize-NomadInbox, Get-NomadInboxProviders, Get-NomadInboxConfigStatus, `
    Test-NomadInbox, Get-NomadInboxSchemas, New-NomadInboxSampleMessage, `
    Initialize-NomadInboxAccountsConfig, Get-NomadInboxAccounts, Invoke-NomadInboxSyncOnce, `
    Get-NomadInboxServiceStatus, Start-NomadInboxService, Stop-NomadInboxService, `
    Read-NomadInboxSyncStatus, Test-NomadInboxWorkerRunning, Get-NomadInboxWorkerLogPath
