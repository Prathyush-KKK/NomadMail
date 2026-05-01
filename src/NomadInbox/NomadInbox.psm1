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
function Get-NomadInboxArchiveMessagesPath { Join-Path (Get-NomadInboxDataDir) "archive-messages.jsonl" }
function Get-NomadInboxArchiveIndexPath { Join-Path (Get-NomadInboxDataDir) "archive-index.jsonl" }
function Get-NomadInboxImportStatusPath { Join-Path (Get-NomadInboxDataDir) "import-status.json" }

function Initialize-NomadInbox {
    $dataDir = Get-NomadInboxDataDir
    $attachmentsDir = New-NomadInboxDirectory (Join-Path $dataDir "attachments")
    foreach ($file in @((Get-NomadInboxMessagesPath), (Get-NomadInboxActionsPath), (Get-NomadInboxArchiveMessagesPath), (Get-NomadInboxArchiveIndexPath))) {
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
        archiveMessagesPath = Get-NomadInboxArchiveMessagesPath
        archiveIndexPath = Get-NomadInboxArchiveIndexPath
        importStatusPath = Get-NomadInboxImportStatusPath
        actionsPath = Get-NomadInboxActionsPath
        attachmentsDir = $attachmentsDir
    }
}

function ConvertTo-NomadInboxOptions {
    param([string[]]$Tokens)
    $options = @{}
    if ($null -eq $Tokens) { return $options }
    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        $token = $Tokens[$i]
        if (-not $token.StartsWith("--")) { throw "Unexpected argument: $token" }
        $key = $token.Substring(2)
        if ($key -in @("include-bodies", "dry-run")) {
            $options[$key] = "true"
            continue
        }
        if ($i + 1 -ge $Tokens.Count) { throw "Missing value for option --$key" }
        $options[$key] = $Tokens[$i + 1]
        $i++
    }
    return $options
}

function Get-NomadInboxOption {
    param(
        [hashtable]$Options,
        [string]$Name,
        [string]$DefaultValue = ""
    )
    if ($Options.ContainsKey($Name) -and -not [string]::IsNullOrWhiteSpace($Options[$Name])) {
        return $Options[$Name]
    }
    return $DefaultValue
}

function Require-NomadInboxOption {
    param([hashtable]$Options, [string]$Name)
    if (-not $Options.ContainsKey($Name) -or [string]::IsNullOrWhiteSpace($Options[$Name])) {
        throw "Missing required option --$Name"
    }
    return $Options[$Name]
}

function ConvertTo-NomadInboxHash {
    param([string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Value)
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally {
        $sha.Dispose()
    }
}

function ConvertTo-NomadInboxSearchText {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    return (($Value -replace '<[^>]+>', ' ') -replace '[^\p{L}\p{Nd}@._+-]+', ' ').ToLowerInvariant().Trim()
}

function ConvertTo-NomadInboxSnippet {
    param([string]$Value, [int]$MaxLength = 240)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $clean = (($Value -replace '\s+', ' ').Trim())
    if ($clean.Length -le $MaxLength) { return $clean }
    return $clean.Substring(0, $MaxLength)
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
        backupStatus = Get-NomadInboxBackupStatus
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

function Get-NomadInboxJsonlCount {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    $count = 0
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        if (-not [string]::IsNullOrWhiteSpace($line)) { $count++ }
    }
    return $count
}

function Read-NomadInboxImportStatus {
    $path = Get-NomadInboxImportStatusPath
    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{
            service = $script:ServiceName
            status = "notStarted"
            lastImportAt = $null
            lastBatchId = $null
            lastSource = $null
            lastFormat = $null
            importedMessages = 0
            skippedMessages = 0
            warnings = @()
            updatedAt = (Get-Date).ToUniversalTime().ToString("o")
        }
    }
    $raw = Get-Content -LiteralPath $path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-NomadInboxImportStatus {
    param($Status)
    Initialize-NomadInbox | Out-Null
    $Status | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath (Get-NomadInboxImportStatusPath) -Encoding UTF8
    return $Status
}

function Get-NomadInboxBackupStatus {
    Initialize-NomadInbox | Out-Null
    $liveCount = Get-NomadInboxJsonlCount (Get-NomadInboxMessagesPath)
    $archiveCount = Get-NomadInboxJsonlCount (Get-NomadInboxArchiveMessagesPath)
    $indexCount = Get-NomadInboxJsonlCount (Get-NomadInboxArchiveIndexPath)
    $syncStatus = Read-NomadInboxSyncStatus
    $importStatus = Read-NomadInboxImportStatus
    $prompts = @()

    if ($liveCount -gt 0 -or $archiveCount -gt 0) {
        $prompts += "NomadInbox currently has $liveCount live synced messages and $archiveCount imported archive messages available for local context."
    } else {
        $prompts += "NomadInbox has not backed up any mail context yet. Connect a live account for sync, or import an email export when you are ready."
    }
    if ($archiveCount -eq 0) {
        $prompts += "You can enrich long-term context by importing Gmail Takeout .mbox files, folders of .eml files, or an existing NomadInbox JSONL export."
    } else {
        $prompts += "Imported archive mail is read-only by design. It can improve search and summaries, but actions still require a live synced provider message."
    }
    if ($null -ne $syncStatus -and $syncStatus.lastRunAt) {
        $prompts += "Last live sync ran at $($syncStatus.lastRunAt). Run 'sync once' or enable background sync to keep this fresher."
    }
    if ($null -ne $importStatus -and $importStatus.lastImportAt) {
        $prompts += "Last archive import ran at $($importStatus.lastImportAt) from $($importStatus.lastSource). Re-run import when you export more historical mail."
    }

    [pscustomobject]@{
        status = "ok"
        service = $script:ServiceName
        liveSyncedMessages = $liveCount
        archiveImportedMessages = $archiveCount
        archiveIndexedMessages = $indexCount
        totalBackedUpMessages = $liveCount + $archiveCount
        messagesPath = Get-NomadInboxMessagesPath
        archiveMessagesPath = Get-NomadInboxArchiveMessagesPath
        archiveIndexPath = Get-NomadInboxArchiveIndexPath
        syncStatus = $syncStatus
        importStatus = $importStatus
        userPrompts = $prompts
        updatedAt = (Get-Date).ToUniversalTime().ToString("o")
    }
}

function ConvertFrom-NomadInboxHeaderBlock {
    param([string]$HeaderBlock)
    $headers = @{}
    $currentName = $null
    foreach ($line in ($HeaderBlock -split '\r?\n')) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if (($line.StartsWith(" ") -or $line.StartsWith("`t")) -and $currentName) {
            $headers[$currentName] = ($headers[$currentName] + " " + $line.Trim()).Trim()
            continue
        }
        $idx = $line.IndexOf(":")
        if ($idx -le 0) { continue }
        $currentName = $line.Substring(0, $idx).Trim()
        $headers[$currentName] = $line.Substring($idx + 1).Trim()
    }
    return $headers
}

function Get-NomadInboxHeader {
    param([hashtable]$Headers, [string]$Name)
    foreach ($key in $Headers.Keys) {
        if ($key -ieq $Name) { return [string]$Headers[$key] }
    }
    return ""
}

function ConvertTo-NomadInboxAddress {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return [pscustomobject]@{ name = $null; email = "unknown@example.invalid" }
    }
    $email = $null
    $match = [regex]::Match($Value, '[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) { $email = $match.Value } else { $email = $Value.Trim() }
    $name = ($Value -replace '<[^>]+>', '').Trim().Trim('"')
    if ($name -eq $email) { $name = $null }
    [pscustomobject]@{ name = $name; email = $email }
}

function ConvertTo-NomadInboxAddressList {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
    return @($Value -split ',' | ForEach-Object { ConvertTo-NomadInboxAddress $_ })
}

function ConvertTo-NomadInboxIsoDate {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return (Get-Date).ToUniversalTime().ToString("o")
    }
    try {
        return ([datetimeoffset]::Parse($Value)).UtcDateTime.ToString("o")
    } catch {
        return (Get-Date).ToUniversalTime().ToString("o")
    }
}

function ConvertFrom-NomadInboxRfc822Message {
    param(
        [string]$RawMessage,
        [string]$SourceProvider,
        [string]$SourcePathHash,
        [string]$ImportBatchId,
        [bool]$IncludeBodies
    )
    $parts = [regex]::Split($RawMessage, '\r?\n\r?\n', 2)
    $headerBlock = if ($parts.Count -gt 0) { $parts[0] } else { "" }
    $body = if ($parts.Count -gt 1) { $parts[1] } else { "" }
    $headers = ConvertFrom-NomadInboxHeaderBlock $headerBlock
    $messageId = Get-NomadInboxHeader $headers "Message-ID"
    if ([string]::IsNullOrWhiteSpace($messageId)) {
        $messageId = ConvertTo-NomadInboxHash ($RawMessage.Substring(0, [Math]::Min($RawMessage.Length, 4096)))
    }
    $subject = Get-NomadInboxHeader $headers "Subject"
    if ([string]::IsNullOrWhiteSpace($subject)) { $subject = "(no subject)" }
    $date = ConvertTo-NomadInboxIsoDate (Get-NomadInboxHeader $headers "Date")
    $idSeed = "$SourceProvider|$messageId|$date|$subject"
    $id = "archive:" + (ConvertTo-NomadInboxHash $idSeed).Substring(0, 32)
    $bodyText = if ($IncludeBodies) { $body } else { $null }
    $snippet = ConvertTo-NomadInboxSnippet $body
    $searchText = ConvertTo-NomadInboxSearchText ($subject + " " + (Get-NomadInboxHeader $headers "From") + " " + (Get-NomadInboxHeader $headers "To") + " " + $body)

    [pscustomobject]@{
        id = $id
        provider = "archive-import"
        providerMessageId = $messageId
        conversationId = Get-NomadInboxHeader $headers "Thread-Index"
        folder = "Archive Import"
        subject = $subject
        from = ConvertTo-NomadInboxAddress (Get-NomadInboxHeader $headers "From")
        to = ConvertTo-NomadInboxAddressList (Get-NomadInboxHeader $headers "To")
        cc = ConvertTo-NomadInboxAddressList (Get-NomadInboxHeader $headers "Cc")
        receivedAt = $date
        sentAt = $date
        snippet = $snippet
        bodyText = $bodyText
        bodyHtml = $null
        headers = $headers
        unread = $false
        flagged = $false
        importance = $null
        categories = @("archive-import", $SourceProvider)
        attachments = @()
        capabilities = @()
        sourceType = "archive-import"
        sourceProvider = $SourceProvider
        sourcePathHash = $SourcePathHash
        importBatchId = $ImportBatchId
        actionable = $false
        importedAt = (Get-Date).ToUniversalTime().ToString("o")
        searchableText = $searchText
    }
}

function ConvertTo-NomadInboxArchiveRecordFromObject {
    param(
        $InputObject,
        [string]$SourceProvider,
        [string]$SourcePathHash,
        [string]$ImportBatchId,
        [bool]$IncludeBodies
    )
    $subject = if ($InputObject.subject) { [string]$InputObject.subject } else { "(no subject)" }
    $providerMessageId = if ($InputObject.providerMessageId) { [string]$InputObject.providerMessageId } elseif ($InputObject.id) { [string]$InputObject.id } else { ConvertTo-NomadInboxHash ($InputObject | ConvertTo-Json -Depth 20 -Compress) }
    $receivedAt = if ($InputObject.receivedAt) { ConvertTo-NomadInboxIsoDate ([string]$InputObject.receivedAt) } else { (Get-Date).ToUniversalTime().ToString("o") }
    $body = if ($InputObject.bodyText) { [string]$InputObject.bodyText } elseif ($InputObject.snippet) { [string]$InputObject.snippet } else { "" }
    $id = "archive:" + (ConvertTo-NomadInboxHash "$SourceProvider|$providerMessageId|$receivedAt|$subject").Substring(0, 32)

    [pscustomobject]@{
        id = $id
        provider = "archive-import"
        providerMessageId = $providerMessageId
        conversationId = $InputObject.conversationId
        folder = "Archive Import"
        subject = $subject
        from = if ($InputObject.from) { $InputObject.from } else { [pscustomobject]@{ name = $null; email = "unknown@example.invalid" } }
        to = if ($InputObject.to) { @($InputObject.to) } else { @() }
        cc = if ($InputObject.cc) { @($InputObject.cc) } else { @() }
        receivedAt = $receivedAt
        sentAt = if ($InputObject.sentAt) { ConvertTo-NomadInboxIsoDate ([string]$InputObject.sentAt) } else { $null }
        snippet = ConvertTo-NomadInboxSnippet $body
        bodyText = if ($IncludeBodies) { $body } else { $null }
        bodyHtml = $null
        headers = if ($InputObject.headers) { $InputObject.headers } else { @{} }
        unread = $false
        flagged = $false
        importance = $InputObject.importance
        categories = @("archive-import", $SourceProvider)
        attachments = if ($InputObject.attachments) { @($InputObject.attachments) } else { @() }
        capabilities = @()
        sourceType = "archive-import"
        sourceProvider = $SourceProvider
        sourcePathHash = $SourcePathHash
        importBatchId = $ImportBatchId
        actionable = $false
        importedAt = (Get-Date).ToUniversalTime().ToString("o")
        searchableText = ConvertTo-NomadInboxSearchText ($subject + " " + $body)
    }
}

function Write-NomadInboxArchiveRecords {
    param([array]$Records, [switch]$DryRun)
    if ($DryRun) { return }
    foreach ($record in $Records) {
        $index = [pscustomobject]@{
            id = $record.id
            provider = $record.provider
            sourceType = $record.sourceType
            sourceProvider = $record.sourceProvider
            importBatchId = $record.importBatchId
            subject = $record.subject
            from = $record.from
            receivedAt = $record.receivedAt
            snippet = $record.snippet
            actionable = $false
            searchableText = $record.searchableText
        }
        $recordForStorage = $record.PSObject.Copy()
        $recordForStorage.PSObject.Properties.Remove("searchableText")
        ($recordForStorage | ConvertTo-Json -Depth 50 -Compress) | Add-Content -LiteralPath (Get-NomadInboxArchiveMessagesPath)
        ($index | ConvertTo-Json -Depth 30 -Compress) | Add-Content -LiteralPath (Get-NomadInboxArchiveIndexPath)
    }
}

function Import-NomadInboxArchive {
    param(
        [Parameter(Mandatory = $true)][string]$Format,
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Source = "mail-export",
        [int]$MaxMessages = 0,
        [switch]$IncludeBodies,
        [switch]$DryRun
    )
    Initialize-NomadInbox | Out-Null
    $resolvedPath = Resolve-NomadInboxPath $Path
    if (-not (Test-Path -LiteralPath $resolvedPath)) { throw "Import path not found: $resolvedPath" }
    $formatValue = $Format.ToLowerInvariant()
    $batchId = "import-" + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss") + "-" + ([guid]::NewGuid().ToString("n").Substring(0, 8))
    $sourceHash = ConvertTo-NomadInboxHash $resolvedPath
    $records = @()
    $warnings = @()

    switch ($formatValue) {
        "eml" {
            $files = @()
            $item = Get-Item -LiteralPath $resolvedPath
            if ($item.PSIsContainer) {
                $files = @(Get-ChildItem -LiteralPath $resolvedPath -Recurse -File -Filter "*.eml")
            } else {
                $files = @($item)
            }
            foreach ($file in $files) {
                if ($MaxMessages -gt 0 -and $records.Count -ge $MaxMessages) { break }
                try {
                    $raw = Get-Content -LiteralPath $file.FullName -Raw
                    $records += ConvertFrom-NomadInboxRfc822Message -RawMessage $raw -SourceProvider $Source -SourcePathHash (ConvertTo-NomadInboxHash $file.FullName) -ImportBatchId $batchId -IncludeBodies ([bool]$IncludeBodies)
                } catch {
                    $warnings += "Failed to parse $($file.Name): $($_.Exception.Message)"
                }
            }
        }
        "mbox" {
            $raw = Get-Content -LiteralPath $resolvedPath -Raw
            $parts = [regex]::Split($raw, "(?m)^From .*\r?\n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            foreach ($part in $parts) {
                if ($MaxMessages -gt 0 -and $records.Count -ge $MaxMessages) { break }
                try {
                    $records += ConvertFrom-NomadInboxRfc822Message -RawMessage $part -SourceProvider $Source -SourcePathHash $sourceHash -ImportBatchId $batchId -IncludeBodies ([bool]$IncludeBodies)
                } catch {
                    $warnings += "Failed to parse one mbox message: $($_.Exception.Message)"
                }
            }
        }
        "jsonl" {
            foreach ($line in [System.IO.File]::ReadLines($resolvedPath)) {
                if ($MaxMessages -gt 0 -and $records.Count -ge $MaxMessages) { break }
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                try {
                    $obj = $line | ConvertFrom-Json
                    $records += ConvertTo-NomadInboxArchiveRecordFromObject -InputObject $obj -SourceProvider $Source -SourcePathHash $sourceHash -ImportBatchId $batchId -IncludeBodies ([bool]$IncludeBodies)
                } catch {
                    $warnings += "Failed to parse one jsonl line: $($_.Exception.Message)"
                }
            }
        }
        "pst" {
            throw "PST import is planned but not implemented in this bootstrap. Export PST to EML or use Outlook Desktop live sync for now."
        }
        "msg" {
            throw "MSG import is planned but not implemented in this bootstrap. Export MSG to EML or use Outlook Desktop live sync for now."
        }
        default {
            throw "Unsupported import format: $Format. Use eml, mbox, or jsonl."
        }
    }

    Write-NomadInboxArchiveRecords -Records $records -DryRun:$DryRun
    $now = (Get-Date).ToUniversalTime().ToString("o")
    $status = [pscustomobject]@{
        service = $script:ServiceName
        status = if ($DryRun) { "dryRun" } else { "ok" }
        lastImportAt = $now
        lastBatchId = $batchId
        lastSource = $Source
        lastFormat = $formatValue
        importedMessages = $records.Count
        skippedMessages = $warnings.Count
        warnings = $warnings
        updatedAt = $now
    }
    if (-not $DryRun) {
        Write-NomadInboxImportStatus $status | Out-Null
        Write-NomadInboxActionRecord -ActionType "archiveImport" -Status "success" -InputObject @{ provider = "archive-import"; source = $Source; format = $formatValue; pathHash = $sourceHash } -ResultObject @{ importedMessages = $records.Count; skippedMessages = $warnings.Count; batchId = $batchId } -ErrorMessage $null | Out-Null
    }

    [pscustomobject]@{
        status = $status.status
        service = $script:ServiceName
        batchId = $batchId
        source = $Source
        format = $formatValue
        importedMessages = $records.Count
        skippedMessages = $warnings.Count
        actionable = $false
        archiveMessagesPath = Get-NomadInboxArchiveMessagesPath
        archiveIndexPath = Get-NomadInboxArchiveIndexPath
        warnings = $warnings
        userPrompt = "Imported archive messages are read-only context. Use live sync for actions, and run 'backup status' to see how much mail context is backed up."
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
    Read-NomadInboxSyncStatus, Test-NomadInboxWorkerRunning, Get-NomadInboxWorkerLogPath, `
    Import-NomadInboxArchive, Read-NomadInboxImportStatus, Get-NomadInboxBackupStatus, `
    ConvertTo-NomadInboxOptions, Get-NomadInboxOption, Require-NomadInboxOption
