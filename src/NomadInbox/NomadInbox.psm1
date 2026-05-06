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
function Get-NomadInboxProviderRawPath { Join-Path (Get-NomadInboxDataDir) "provider-raw.jsonl" }
function Get-NomadInboxMessageExtractsPath { Join-Path (Get-NomadInboxDataDir) "message-extracts.jsonl" }
function Get-NomadInboxThreadIndexPath { Join-Path (Get-NomadInboxDataDir) "thread-index.jsonl" }
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
    foreach ($file in @((Get-NomadInboxMessagesPath), (Get-NomadInboxProviderRawPath), (Get-NomadInboxMessageExtractsPath), (Get-NomadInboxThreadIndexPath), (Get-NomadInboxActionsPath), (Get-NomadInboxArchiveMessagesPath), (Get-NomadInboxArchiveIndexPath))) {
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
        providerRawPath = Get-NomadInboxProviderRawPath
        messageExtractsPath = Get-NomadInboxMessageExtractsPath
        threadIndexPath = Get-NomadInboxThreadIndexPath
        archiveMessagesPath = Get-NomadInboxArchiveMessagesPath
        archiveIndexPath = Get-NomadInboxArchiveIndexPath
        importStatusPath = Get-NomadInboxImportStatusPath
        actionsPath = Get-NomadInboxActionsPath
        attachmentsDir = $attachmentsDir
        timeContext = Get-NomadInboxTimeContext
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

function Test-NomadInboxTruthy {
    param($Value, [bool]$Default = $false)
    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return [bool]$Value }
    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $Default }
    return $text -in @("1", "true", "yes", "y", "on", "enabled")
}

function Test-NomadInboxAccountOption {
    param($Account, [string[]]$Names, [bool]$Default = $false)
    if ($null -eq $Account) { return $Default }
    foreach ($name in $Names) {
        if ($Account.PSObject.Properties.Name -contains $name) {
            return Test-NomadInboxTruthy $Account.$name $Default
        }
    }
    return $Default
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

function Get-NomadInboxMessageId {
    param([string]$Provider, [string]$AccountId, [string]$ProviderMessageId)
    return "$Provider`:$AccountId`:" + (ConvertTo-NomadInboxHash $ProviderMessageId).Substring(0, 32)
}

function Get-NomadInboxProviderRawId {
    param([string]$Provider, [string]$AccountId, [string]$ProviderMessageId)
    return "raw:$Provider`:$AccountId`:" + (ConvertTo-NomadInboxHash $ProviderMessageId).Substring(0, 32)
}

function ConvertTo-NomadInboxSafeFileName {
    param([string]$Name)
    $fallback = if ([string]::IsNullOrWhiteSpace($Name)) { "attachment.bin" } else { $Name.Trim() }
    $invalid = [regex]::Escape((-join [System.IO.Path]::GetInvalidFileNameChars()))
    $safe = [regex]::Replace($fallback, "[$invalid]+", "_")
    if ($safe.Length -gt 120) { $safe = $safe.Substring(0, 120) }
    return $safe
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

function Get-NomadInboxUserCulture {
    $cultureName = if (-not [string]::IsNullOrWhiteSpace($env:NOMADINBOX_USER_CULTURE)) {
        $env:NOMADINBOX_USER_CULTURE
    } elseif (-not [string]::IsNullOrWhiteSpace($env:NOMADINBOX_USER_LOCALE)) {
        $env:NOMADINBOX_USER_LOCALE
    } else {
        ""
    }

    if (-not [string]::IsNullOrWhiteSpace($cultureName)) {
        try {
            return [System.Globalization.CultureInfo]::GetCultureInfo($cultureName)
        } catch {
        }
    }

    return [System.Globalization.CultureInfo]::CurrentCulture
}

function Resolve-NomadInboxTimeZoneCandidate {
    param([string]$Candidate)

    if ([string]::IsNullOrWhiteSpace($Candidate)) { return $null }

    try {
        return [System.TimeZoneInfo]::FindSystemTimeZoneById($Candidate)
    } catch {
    }

    $aliases = @{
        "Asia/Calcutta" = "India Standard Time"
        "Asia/Kolkata" = "India Standard Time"
        "India Standard Time" = "Asia/Kolkata"
        "Etc/UTC" = "UTC"
        "UTC" = "Etc/UTC"
        "America/New_York" = "Eastern Standard Time"
        "Eastern Standard Time" = "America/New_York"
        "America/Chicago" = "Central Standard Time"
        "Central Standard Time" = "America/Chicago"
        "America/Denver" = "Mountain Standard Time"
        "Mountain Standard Time" = "America/Denver"
        "America/Los_Angeles" = "Pacific Standard Time"
        "Pacific Standard Time" = "America/Los_Angeles"
        "Europe/London" = "GMT Standard Time"
        "GMT Standard Time" = "Europe/London"
        "Europe/Berlin" = "W. Europe Standard Time"
        "W. Europe Standard Time" = "Europe/Berlin"
        "Asia/Tokyo" = "Tokyo Standard Time"
        "Tokyo Standard Time" = "Asia/Tokyo"
        "Asia/Shanghai" = "China Standard Time"
        "China Standard Time" = "Asia/Shanghai"
        "Australia/Sydney" = "AUS Eastern Standard Time"
        "AUS Eastern Standard Time" = "Australia/Sydney"
    }

    if ($aliases.ContainsKey($Candidate)) {
        try {
            return [System.TimeZoneInfo]::FindSystemTimeZoneById($aliases[$Candidate])
        } catch {
        }
    }

    return $null
}

function Get-NomadInboxUserTimeZone {
    foreach ($candidate in @($env:NOMADINBOX_USER_TIME_ZONE, $env:NOMADINBOX_USER_TIME_ZONE_IANA)) {
        $timeZone = Resolve-NomadInboxTimeZoneCandidate $candidate
        if ($null -ne $timeZone) { return $timeZone }
    }

    return [System.TimeZoneInfo]::Local
}

function Get-NomadInboxUtcNowIso {
    return ([datetimeoffset]::UtcNow.UtcDateTime.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture))
}

function Test-NomadInboxHasExplicitTimeZone {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ($Value -match '(?i)(Z|[+-]\d{2}:?\d{2})\s*(\)|$)' -or $Value -match '(?i)\b(UT|UTC|GMT|EST|EDT|CST|CDT|MST|MDT|PST|PDT)\b')
}

function ConvertTo-NomadInboxUtcDateTimeOffsetFromDateTime {
    param([datetime]$Value)

    if ($Value.Kind -eq [System.DateTimeKind]::Utc) {
        return (New-Object System.DateTimeOffset -ArgumentList $Value)
    }
    if ($Value.Kind -eq [System.DateTimeKind]::Local) {
        return (New-Object System.DateTimeOffset -ArgumentList $Value).ToUniversalTime()
    }

    $timeZone = Get-NomadInboxUserTimeZone
    $unspecified = [datetime]::SpecifyKind($Value, [System.DateTimeKind]::Unspecified)
    try {
        $utc = [System.TimeZoneInfo]::ConvertTimeToUtc($unspecified, $timeZone)
        return (New-Object System.DateTimeOffset -ArgumentList $utc)
    } catch {
        return (New-Object System.DateTimeOffset -ArgumentList $Value).ToUniversalTime()
    }
}

function ConvertTo-NomadInboxUtcDateTimeOffset {
    param([string]$Value, [switch]$UseNowFallback)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        if ($UseNowFallback) { return [datetimeoffset]::UtcNow }
        throw "Date/time value is empty."
    }

    $culture = Get-NomadInboxUserCulture
    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $allowWhiteSpace = [System.Globalization.DateTimeStyles]::AllowWhiteSpaces

    if (Test-NomadInboxHasExplicitTimeZone $Value) {
        foreach ($provider in @($culture, $invariant)) {
            $offset = [datetimeoffset]::MinValue
            if ([datetimeoffset]::TryParse($Value, $provider, $allowWhiteSpace, [ref]$offset)) {
                return $offset.ToUniversalTime()
            }
        }
    }

    foreach ($provider in @($culture, $invariant)) {
        $dateTime = [datetime]::MinValue
        if ([datetime]::TryParse($Value, $provider, $allowWhiteSpace, [ref]$dateTime)) {
            return ConvertTo-NomadInboxUtcDateTimeOffsetFromDateTime $dateTime
        }
    }

    $assumeLocal = $allowWhiteSpace -bor [System.Globalization.DateTimeStyles]::AssumeLocal
    foreach ($provider in @($culture, $invariant)) {
        $offset = [datetimeoffset]::MinValue
        if ([datetimeoffset]::TryParse($Value, $provider, $assumeLocal, [ref]$offset)) {
            return $offset.ToUniversalTime()
        }
    }

    if ($UseNowFallback) { return [datetimeoffset]::UtcNow }
    throw "Unable to parse date/time using user locale '$($culture.Name)' and time zone '$((Get-NomadInboxUserTimeZone).Id)': $Value"
}

function ConvertTo-NomadInboxUtcIsoFromDateTime {
    param([datetime]$Value)
    return ((ConvertTo-NomadInboxUtcDateTimeOffsetFromDateTime $Value).UtcDateTime.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture))
}

function ConvertTo-NomadInboxIsoDate {
    param([string]$Value)
    $offset = ConvertTo-NomadInboxUtcDateTimeOffset -Value $Value -UseNowFallback
    return $offset.UtcDateTime.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-NomadInboxLocalTimeText {
    param([string]$Value, [string]$Fallback = "Not recorded")

    if ([string]::IsNullOrWhiteSpace($Value)) { return $Fallback }
    try {
        $utc = ConvertTo-NomadInboxUtcDateTimeOffset -Value $Value
        $culture = Get-NomadInboxUserCulture
        $timeZone = Get-NomadInboxUserTimeZone
        $local = [System.TimeZoneInfo]::ConvertTime($utc, $timeZone)
        return ("{0} ({1})" -f $local.ToString("g", $culture), $timeZone.StandardName)
    } catch {
        return [string]$Value
    }
}

function Get-NomadInboxTimeContext {
    $culture = Get-NomadInboxUserCulture
    $timeZone = Get-NomadInboxUserTimeZone
    $nowUtc = [datetimeoffset]::UtcNow
    $nowLocal = [System.TimeZoneInfo]::ConvertTime($nowUtc, $timeZone)

    [pscustomobject]@{
        cultureName = $culture.Name
        cultureDisplayName = $culture.DisplayName
        timeZoneId = $timeZone.Id
        timeZoneDisplayName = $timeZone.DisplayName
        requestedWindowsTimeZoneId = if ([string]::IsNullOrWhiteSpace($env:NOMADINBOX_USER_TIME_ZONE)) { $null } else { $env:NOMADINBOX_USER_TIME_ZONE }
        requestedIanaTimeZoneId = if ([string]::IsNullOrWhiteSpace($env:NOMADINBOX_USER_TIME_ZONE_IANA)) { $null } else { $env:NOMADINBOX_USER_TIME_ZONE_IANA }
        utcOffset = $nowLocal.Offset.ToString()
        nowLocal = $nowLocal.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
        nowUtc = $nowUtc.UtcDateTime.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
        parsingRule = "Ambiguous date/time strings are parsed with the user culture and user time zone, then stored as UTC ISO 8601."
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
            captureRawProviderData = Test-NomadInboxAccountOption -Account $_ -Names @("captureRawProviderData", "captureRaw", "storeRaw") -Default $true
            includeBodies = Test-NomadInboxAccountOption -Account $_ -Names @("includeBodies", "storeBodies") -Default $false
            includeAttachments = Test-NomadInboxAccountOption -Account $_ -Names @("includeAttachments", "captureAttachments") -Default $true
            saveAttachments = Test-NomadInboxAccountOption -Account $_ -Names @("saveAttachments", "storeAttachmentBytes") -Default $false
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
    $gmailConfigured = -not [string]::IsNullOrWhiteSpace($env:NOMADINBOX_GMAIL_CLIENT_SECRET_JSON) -or -not [string]::IsNullOrWhiteSpace($env:NOMADINBOX_GMAIL_ACCESS_TOKEN)
    $graphConfigured = -not [string]::IsNullOrWhiteSpace($env:NOMADINBOX_GRAPH_CLIENT_ID) -or -not [string]::IsNullOrWhiteSpace($env:NOMADINBOX_GRAPH_ACCESS_TOKEN)
    $providers = @(
        [pscustomobject]@{
            id = "gmail-api"
            name = "Gmail API"
            runtime = "Google Gmail REST API"
            auth = "OAuth Desktop client or Workspace delegation"
            status = if ($gmailConfigured) { "configured" } else { "unconfigured" }
            defaultScopes = "gmail.readonly"
            capabilities = @("sync", "search", "get", "attachments", "draft", "send-confirmed", "mark-read", "star", "move")
        },
        [pscustomobject]@{
            id = "outlook-graph"
            name = "Outlook Graph"
            runtime = "Microsoft Graph Mail API"
            auth = "Microsoft OAuth device-code or delegated OAuth"
            status = if ($graphConfigured) { "configured" } else { "unconfigured" }
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
        gmailAccessTokenConfigured = -not [string]::IsNullOrWhiteSpace($env:NOMADINBOX_GMAIL_ACCESS_TOKEN)
        graphClientConfigured = -not [string]::IsNullOrWhiteSpace($env:NOMADINBOX_GRAPH_CLIENT_ID)
        graphAccessTokenConfigured = -not [string]::IsNullOrWhiteSpace($env:NOMADINBOX_GRAPH_ACCESS_TOKEN)
        outlookDesktopProfile = if ([string]::IsNullOrWhiteSpace($env:NOMADINBOX_OUTLOOK_DESKTOP_PROFILE)) { "default" } else { $env:NOMADINBOX_OUTLOOK_DESKTOP_PROFILE }
        localConfigExpected = Join-Path (Get-NomadInboxRoot) "config\nomad-inbox.ps1"
        localConfigExists = Test-Path -LiteralPath (Join-Path (Get-NomadInboxRoot) "config\nomad-inbox.ps1")
        timeContext = Get-NomadInboxTimeContext
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
            updatedAt = Get-NomadInboxUtcNowIso
            timeContext = Get-NomadInboxTimeContext
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
        timestamp = Get-NomadInboxUtcNowIso
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

function New-NomadInboxProviderRawRecord {
    param(
        [string]$Provider,
        [string]$AccountId,
        [string]$ProviderMessageId,
        [string]$ConversationId,
        $RawObject,
        [bool]$BodyCaptured = $false,
        [bool]$AttachmentMetadataCaptured = $false,
        [bool]$AttachmentBytesCaptured = $false
    )
    $messageId = Get-NomadInboxMessageId -Provider $Provider -AccountId $AccountId -ProviderMessageId $ProviderMessageId
    $rawId = Get-NomadInboxProviderRawId -Provider $Provider -AccountId $AccountId -ProviderMessageId $ProviderMessageId
    [pscustomobject]@{
        schemaVersion = 1
        rawId = $rawId
        messageId = $messageId
        provider = $Provider
        accountId = $AccountId
        providerMessageId = $ProviderMessageId
        conversationId = $ConversationId
        capturedAt = Get-NomadInboxUtcNowIso
        bodyCaptured = $BodyCaptured
        attachmentMetadataCaptured = $AttachmentMetadataCaptured
        attachmentBytesCaptured = $AttachmentBytesCaptured
        raw = $RawObject
    }
}

function Write-NomadInboxProviderRawRecords {
    param([array]$Records)
    Initialize-NomadInbox | Out-Null
    $path = Get-NomadInboxProviderRawPath
    $byId = [ordered]@{}
    if (Test-Path -LiteralPath $path) {
        foreach ($line in [System.IO.File]::ReadLines($path)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $existing = $line | ConvertFrom-Json
                if ($existing.rawId) { $byId[[string]$existing.rawId] = $existing }
            } catch {
            }
        }
    }
    foreach ($record in @($Records)) {
        if ($record.rawId) { $byId[[string]$record.rawId] = $record }
    }
    $lines = @($byId.Values | ForEach-Object { $_ | ConvertTo-Json -Depth 100 -Compress })
    $lines | Set-Content -LiteralPath $path -Encoding UTF8
}

function New-NomadInboxSyncResult {
    param(
        $Account,
        [string]$Status,
        [string]$Reason,
        [int]$Synced,
        [datetime]$StartedAt
    )
    [pscustomobject]@{
        accountId = $Account.id
        displayName = $Account.displayName
        provider = $Account.provider
        status = $Status
        reason = $Reason
        synced = $Synced
        startedAt = ConvertTo-NomadInboxUtcIsoFromDateTime $StartedAt
        finishedAt = Get-NomadInboxUtcNowIso
    }
}

function New-NomadInboxLiveMessage {
    param(
        [string]$Provider,
        [string]$AccountId,
        [string]$ProviderMessageId,
        [string]$ConversationId,
        [string]$Folder,
        [string]$Subject,
        $From,
        [array]$To,
        [array]$Cc,
        [string]$ReceivedAt,
        [string]$SentAt,
        [string]$Snippet,
        [string]$BodyText,
        [string]$BodyHtml,
        [hashtable]$Headers,
        [bool]$Unread,
        [bool]$Flagged,
        [string]$Importance,
        [array]$Categories,
        [array]$Attachments,
        [array]$Capabilities,
        [string]$ProviderRawRef,
        [bool]$RawCaptured = $false
    )
    $id = Get-NomadInboxMessageId -Provider $Provider -AccountId $AccountId -ProviderMessageId $ProviderMessageId
    $fallbackThreadKey = (ConvertTo-NomadInboxHash (($Subject + "|" + $Provider + "|" + $AccountId).ToLowerInvariant())).Substring(0, 32)
    [pscustomobject]@{
        schemaVersion = 2
        id = $id
        accountId = $AccountId
        provider = $Provider
        providerMessageId = $ProviderMessageId
        conversationId = $ConversationId
        threadKey = if ([string]::IsNullOrWhiteSpace($ConversationId)) { $fallbackThreadKey } else { $ConversationId }
        folder = $Folder
        subject = if ([string]::IsNullOrWhiteSpace($Subject)) { "(no subject)" } else { $Subject }
        from = $From
        to = @($To)
        cc = @($Cc)
        receivedAt = if ([string]::IsNullOrWhiteSpace($ReceivedAt)) { Get-NomadInboxUtcNowIso } else { ConvertTo-NomadInboxIsoDate $ReceivedAt }
        sentAt = if ([string]::IsNullOrWhiteSpace($SentAt)) { $null } else { ConvertTo-NomadInboxIsoDate $SentAt }
        snippet = ConvertTo-NomadInboxSnippet $Snippet
        bodyText = if ([string]::IsNullOrWhiteSpace($BodyText)) { $null } else { $BodyText }
        bodyHtml = if ([string]::IsNullOrWhiteSpace($BodyHtml)) { $null } else { $BodyHtml }
        bodyTextAvailable = -not [string]::IsNullOrWhiteSpace($BodyText)
        bodyHtmlAvailable = -not [string]::IsNullOrWhiteSpace($BodyHtml)
        headers = if ($Headers) { $Headers } else { @{} }
        unread = $Unread
        flagged = $Flagged
        importance = $Importance
        categories = @($Categories)
        attachments = @($Attachments | Where-Object { $null -ne $_ })
        capabilities = @($Capabilities)
        sourceType = "live-sync"
        sourceProvider = $Provider
        sourcePathHash = $null
        importBatchId = $null
        providerRawRef = if ([string]::IsNullOrWhiteSpace($ProviderRawRef)) { $null } else { $ProviderRawRef }
        rawCaptured = $RawCaptured
        extractionStatus = "pending"
        normalizedAt = Get-NomadInboxUtcNowIso
        actionable = $true
        importedAt = $null
    }
}

function Write-NomadInboxLiveMessages {
    param([array]$Records)
    Initialize-NomadInbox | Out-Null
    $path = Get-NomadInboxMessagesPath
    $byId = [ordered]@{}
    if (Test-Path -LiteralPath $path) {
        foreach ($line in [System.IO.File]::ReadLines($path)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $existing = $line | ConvertFrom-Json
                if ($existing.id) { $byId[[string]$existing.id] = $existing }
            } catch {
            }
        }
    }
    foreach ($record in $Records) {
        if ($record.id) { $byId[[string]$record.id] = $record }
    }
    $lines = @($byId.Values | ForEach-Object { $_ | ConvertTo-Json -Depth 50 -Compress })
    $lines | Set-Content -LiteralPath $path -Encoding UTF8
}

function Get-NomadInboxComValue {
    param($Object, [string]$Name)
    try {
        if ($null -eq $Object) { return $null }
        return $Object.$Name
    } catch {
        return $null
    }
}

function Get-NomadInboxAttachmentOutputPath {
    param([string]$Provider, [string]$ProviderMessageId, [int]$Index, [string]$FileName)
    $dir = New-NomadInboxDirectory (Join-Path (Get-NomadInboxDataDir) "attachments")
    $messageHash = (ConvertTo-NomadInboxHash $ProviderMessageId).Substring(0, 16)
    $safeName = ConvertTo-NomadInboxSafeFileName $FileName
    return Join-Path $dir "$Provider-$messageHash-$Index-$safeName"
}

function Get-NomadInboxOutlookAttachmentMetadata {
    param($Item, [string]$ProviderMessageId, [bool]$SaveBytes = $false)
    $result = @()
    $attachments = Get-NomadInboxComValue $Item "Attachments"
    $count = Get-NomadInboxComValue $attachments "Count"
    if ($null -eq $count -or [int]$count -le 0) { return @() }
    for ($i = 1; $i -le [int]$count; $i++) {
        try {
            $attachment = $attachments.Item($i)
            $fileName = [string](Get-NomadInboxComValue $attachment "FileName")
            if ([string]::IsNullOrWhiteSpace($fileName)) {
                $fileName = [string](Get-NomadInboxComValue $attachment "DisplayName")
            }
            if ([string]::IsNullOrWhiteSpace($fileName)) { $fileName = "attachment-$i.bin" }
            $localPath = $null
            if ($SaveBytes) {
                $localPath = Get-NomadInboxAttachmentOutputPath -Provider "outlook-desktop" -ProviderMessageId $ProviderMessageId -Index $i -FileName $fileName
                $attachment.SaveAsFile($localPath)
            }
            $result += [pscustomobject]@{
                id = [string]$i
                name = $fileName
                contentType = $null
                sizeBytes = Get-NomadInboxComValue $attachment "Size"
                localPath = $localPath
                providerType = Get-NomadInboxComValue $attachment "Type"
                displayName = Get-NomadInboxComValue $attachment "DisplayName"
                position = Get-NomadInboxComValue $attachment "Position"
            }
        } catch {
        }
    }
    return @($result)
}

function New-NomadInboxOutlookRawSnapshot {
    param($Item, [array]$Attachments, [bool]$IncludeBodies = $false)
    [pscustomobject]@{
        entryId = Get-NomadInboxComValue $Item "EntryID"
        conversationId = Get-NomadInboxComValue $Item "ConversationID"
        conversationTopic = Get-NomadInboxComValue $Item "ConversationTopic"
        messageClass = Get-NomadInboxComValue $Item "MessageClass"
        subject = Get-NomadInboxComValue $Item "Subject"
        senderName = Get-NomadInboxComValue $Item "SenderName"
        senderEmailAddress = Get-NomadInboxComValue $Item "SenderEmailAddress"
        to = Get-NomadInboxComValue $Item "To"
        cc = Get-NomadInboxComValue $Item "CC"
        bcc = Get-NomadInboxComValue $Item "BCC"
        receivedTime = [string](Get-NomadInboxComValue $Item "ReceivedTime")
        sentOn = [string](Get-NomadInboxComValue $Item "SentOn")
        importance = Get-NomadInboxComValue $Item "Importance"
        unread = Get-NomadInboxComValue $Item "UnRead"
        isMarkedAsTask = Get-NomadInboxComValue $Item "IsMarkedAsTask"
        categories = Get-NomadInboxComValue $Item "Categories"
        size = Get-NomadInboxComValue $Item "Size"
        attachments = @($Attachments | Where-Object { $null -ne $_ })
        body = if ($IncludeBodies) { Get-NomadInboxComValue $Item "Body" } else { $null }
        htmlBody = if ($IncludeBodies) { Get-NomadInboxComValue $Item "HTMLBody" } else { $null }
    }
}

function Get-NomadInboxExternalCommandOutput {
    param([string[]]$CommandNames, [string[]]$Arguments)
    foreach ($name in $CommandNames) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $command) { continue }
        try {
            $output = & $command.Source @Arguments 2>$null
            $text = ($output | Out-String).Trim()
            if (-not [string]::IsNullOrWhiteSpace($text)) { return $text }
        } catch {
        }
    }
    return ""
}

function Get-NomadInboxGmailAccessToken {
    if (-not [string]::IsNullOrWhiteSpace($env:NOMADINBOX_GMAIL_ACCESS_TOKEN)) {
        return $env:NOMADINBOX_GMAIL_ACCESS_TOKEN
    }
    return Get-NomadInboxExternalCommandOutput -CommandNames @("gcloud", "gcloud.cmd", "gcloud.ps1") -Arguments @("auth", "print-access-token")
}

function Get-NomadInboxGraphAccessToken {
    if (-not [string]::IsNullOrWhiteSpace($env:NOMADINBOX_GRAPH_ACCESS_TOKEN)) {
        return $env:NOMADINBOX_GRAPH_ACCESS_TOKEN
    }
    $json = Get-NomadInboxExternalCommandOutput -CommandNames @("az", "az.cmd", "az.ps1") -Arguments @("account", "get-access-token", "--resource-type", "ms-graph", "--output", "json")
    if ([string]::IsNullOrWhiteSpace($json)) { return "" }
    try {
        $obj = $json | ConvertFrom-Json
        return [string]$obj.accessToken
    } catch {
        return ""
    }
}

function Get-NomadInboxGmailHeader {
    param($Message, [string]$Name)
    foreach ($header in @($Message.payload.headers)) {
        if ($header.name -ieq $Name) { return [string]$header.value }
    }
    return ""
}

function ConvertFrom-NomadInboxGmailMessage {
    param($Message, $Account, [string]$BodyText = $null, [string]$BodyHtml = $null, [array]$Attachments = @(), [string]$ProviderRawRef = "", [bool]$RawCaptured = $false)
    $headers = @{}
    foreach ($header in @($Message.payload.headers)) {
        if ($header.name) { $headers[[string]$header.name] = [string]$header.value }
    }
    $internalDate = [double]0
    [double]::TryParse([string]$Message.internalDate, [ref]$internalDate) | Out-Null
    $receivedAt = if ($internalDate -gt 0) {
        ([datetimeoffset]::FromUnixTimeMilliseconds([int64]$internalDate)).UtcDateTime.ToString("o")
    } else {
        ConvertTo-NomadInboxIsoDate (Get-NomadInboxGmailHeader $Message "Date")
    }
    $labelIds = @($Message.labelIds)
    New-NomadInboxLiveMessage `
        -Provider "gmail-api" `
        -AccountId $Account.id `
        -ProviderMessageId ([string]$Message.id) `
        -ConversationId ([string]$Message.threadId) `
        -Folder $Account.folder `
        -Subject (Get-NomadInboxGmailHeader $Message "Subject") `
        -From (ConvertTo-NomadInboxAddress (Get-NomadInboxGmailHeader $Message "From")) `
        -To (ConvertTo-NomadInboxAddressList (Get-NomadInboxGmailHeader $Message "To")) `
        -Cc (ConvertTo-NomadInboxAddressList (Get-NomadInboxGmailHeader $Message "Cc")) `
        -ReceivedAt $receivedAt `
        -SentAt (ConvertTo-NomadInboxIsoDate (Get-NomadInboxGmailHeader $Message "Date")) `
        -Snippet ([string]$Message.snippet) `
        -BodyText $BodyText `
        -BodyHtml $BodyHtml `
        -Headers $headers `
        -Unread ($labelIds -contains "UNREAD") `
        -Flagged ($labelIds -contains "STARRED") `
        -Importance $null `
        -Categories $labelIds `
        -Attachments @($Attachments) `
        -Capabilities @("reply", "replyAll", "forward", "markRead", "markUnread", "star", "archive", "trash", "saveAttachment") `
        -ProviderRawRef $ProviderRawRef `
        -RawCaptured $RawCaptured
}

function Invoke-NomadInboxGmailApiSync {
    param($Account, [datetime]$StartedAt)
    $token = Get-NomadInboxGmailAccessToken
    if ([string]::IsNullOrWhiteSpace($token)) {
        return New-NomadInboxSyncResult -Account $Account -Status "pendingProviderAuth" -Reason "Set NOMADINBOX_GMAIL_ACCESS_TOKEN or sign in with gcloud using Gmail scopes." -Synced 0 -StartedAt $StartedAt
    }
    $limit = if ($Account.limit) { [int]$Account.limit } else { 25 }
    $captureRaw = Test-NomadInboxAccountOption -Account $Account -Names @("captureRawProviderData", "captureRaw", "storeRaw") -Default $true
    $includeBodies = Test-NomadInboxAccountOption -Account $Account -Names @("includeBodies", "storeBodies") -Default $false
    $includeAttachments = Test-NomadInboxAccountOption -Account $Account -Names @("includeAttachments", "captureAttachments") -Default $true
    $folder = if ([string]::IsNullOrWhiteSpace($Account.folder)) { "Inbox" } else { [string]$Account.folder }
    $headers = @{ Authorization = "Bearer $token" }
    $queryParams = @{
        maxResults = [Math]::Max(1, [Math]::Min(100, $limit))
    }
    if ($folder -ieq "Inbox") { $queryParams.labelIds = "INBOX" }
    if (-not [string]::IsNullOrWhiteSpace($Account.query)) { $queryParams.q = [string]$Account.query }
    $query = ($queryParams.GetEnumerator() | ForEach-Object { "{0}={1}" -f [uri]::EscapeDataString($_.Key), [uri]::EscapeDataString([string]$_.Value) }) -join "&"
    $listUri = "https://gmail.googleapis.com/gmail/v1/users/me/messages?$query"
    try {
        $list = Invoke-RestMethod -Method Get -Uri $listUri -Headers $headers
        $records = @()
        $rawRecords = @()
        foreach ($messageRef in @($list.messages | Where-Object { $null -ne $_ -and $_.id })) {
            $formatQuery = if ($includeBodies -or $includeAttachments) {
                "format=full"
            } else {
                "format=metadata&metadataHeaders=From&metadataHeaders=To&metadataHeaders=Cc&metadataHeaders=Subject&metadataHeaders=Date&metadataHeaders=Message-ID"
            }
            $messageUri = "https://gmail.googleapis.com/gmail/v1/users/me/messages/$([uri]::EscapeDataString([string]$messageRef.id))?$formatQuery"
            $message = Invoke-RestMethod -Method Get -Uri $messageUri -Headers $headers
            $attachments = @()
            if ($includeAttachments -and $message.payload) {
                $parts = @($message.payload.parts | Where-Object { $null -ne $_ })
                foreach ($part in $parts) {
                    if (-not [string]::IsNullOrWhiteSpace($part.filename)) {
                        $attachments += [pscustomobject]@{
                            id = if ($part.body.attachmentId) { [string]$part.body.attachmentId } else { [string]$part.partId }
                            name = [string]$part.filename
                            contentType = [string]$part.mimeType
                            sizeBytes = if ($part.body.size) { [int64]$part.body.size } else { $null }
                            localPath = $null
                        }
                    }
                }
            }
            $rawRef = $null
            if ($captureRaw) {
                $rawRef = Get-NomadInboxProviderRawId -Provider "gmail-api" -AccountId $Account.id -ProviderMessageId ([string]$message.id)
                $rawRecords += New-NomadInboxProviderRawRecord `
                    -Provider "gmail-api" `
                    -AccountId $Account.id `
                    -ProviderMessageId ([string]$message.id) `
                    -ConversationId ([string]$message.threadId) `
                    -RawObject $message `
                    -BodyCaptured:$includeBodies `
                    -AttachmentMetadataCaptured:$includeAttachments `
                    -AttachmentBytesCaptured:$false
            }
            $records += ConvertFrom-NomadInboxGmailMessage -Message $message -Account $Account -Attachments $attachments -ProviderRawRef $rawRef -RawCaptured:$captureRaw
        }
        Write-NomadInboxLiveMessages -Records $records
        if ($rawRecords.Count -gt 0) { Write-NomadInboxProviderRawRecords -Records $rawRecords }
        Write-NomadInboxActionRecord -ActionType "sync" -Status "success" -InputObject @{ accountId = $Account.id; provider = $Account.provider; folder = $Account.folder; limit = $Account.limit } -ResultObject @{ synced = $records.Count } -ErrorMessage $null | Out-Null
        return New-NomadInboxSyncResult -Account $Account -Status "ok" -Reason $null -Synced $records.Count -StartedAt $StartedAt
    } catch {
        Write-NomadInboxActionRecord -ActionType "sync" -Status "error" -InputObject @{ accountId = $Account.id; provider = $Account.provider } -ResultObject @{} -ErrorMessage ([string]$_.Exception.Message) | Out-Null
        return New-NomadInboxSyncResult -Account $Account -Status "error" -Reason ([string]$_.Exception.Message) -Synced 0 -StartedAt $StartedAt
    }
}

function ConvertTo-NomadInboxGraphAddress {
    param($Recipient)
    if ($null -eq $Recipient -or $null -eq $Recipient.emailAddress) {
        return [pscustomobject]@{ name = $null; email = "unknown@example.invalid" }
    }
    [pscustomobject]@{ name = $Recipient.emailAddress.name; email = $Recipient.emailAddress.address }
}

function ConvertFrom-NomadInboxGraphMessage {
    param($Message, $Account, [array]$Attachments = @(), [string]$ProviderRawRef = "", [bool]$RawCaptured = $false, [bool]$IncludeBodies = $false)
    $flagged = $false
    if ($Message.flag -and $Message.flag.flagStatus) { $flagged = ([string]$Message.flag.flagStatus) -ne "notFlagged" }
    $bodyText = $null
    $bodyHtml = $null
    if ($IncludeBodies -and $Message.body -and $Message.body.content) {
        if ([string]$Message.body.contentType -ieq "html") {
            $bodyHtml = [string]$Message.body.content
        } else {
            $bodyText = [string]$Message.body.content
        }
    }
    New-NomadInboxLiveMessage `
        -Provider "outlook-graph" `
        -AccountId $Account.id `
        -ProviderMessageId ([string]$Message.id) `
        -ConversationId ([string]$Message.conversationId) `
        -Folder $Account.folder `
        -Subject ([string]$Message.subject) `
        -From (ConvertTo-NomadInboxGraphAddress $Message.from) `
        -To (@($Message.toRecipients | ForEach-Object { ConvertTo-NomadInboxGraphAddress $_ })) `
        -Cc (@($Message.ccRecipients | ForEach-Object { ConvertTo-NomadInboxGraphAddress $_ })) `
        -ReceivedAt (ConvertTo-NomadInboxIsoDate ([string]$Message.receivedDateTime)) `
        -SentAt (ConvertTo-NomadInboxIsoDate ([string]$Message.sentDateTime)) `
        -Snippet ([string]$Message.bodyPreview) `
        -BodyText $bodyText `
        -BodyHtml $bodyHtml `
        -Headers @{} `
        -Unread (-not [bool]$Message.isRead) `
        -Flagged $flagged `
        -Importance ([string]$Message.importance) `
        -Categories @($Message.categories) `
        -Attachments @($Attachments) `
        -Capabilities @("reply", "replyAll", "forward", "markRead", "markUnread", "flag", "unflag", "move", "archive", "trash", "saveAttachment") `
        -ProviderRawRef $ProviderRawRef `
        -RawCaptured $RawCaptured
}

function Invoke-NomadInboxOutlookGraphSync {
    param($Account, [datetime]$StartedAt)
    $token = Get-NomadInboxGraphAccessToken
    if ([string]::IsNullOrWhiteSpace($token)) {
        return New-NomadInboxSyncResult -Account $Account -Status "pendingProviderAuth" -Reason "Set NOMADINBOX_GRAPH_ACCESS_TOKEN or sign in with Azure CLI for Microsoft Graph." -Synced 0 -StartedAt $StartedAt
    }
    $limit = if ($Account.limit) { [int]$Account.limit } else { 25 }
    $captureRaw = Test-NomadInboxAccountOption -Account $Account -Names @("captureRawProviderData", "captureRaw", "storeRaw") -Default $true
    $includeBodies = Test-NomadInboxAccountOption -Account $Account -Names @("includeBodies", "storeBodies") -Default $false
    $includeAttachments = Test-NomadInboxAccountOption -Account $Account -Names @("includeAttachments", "captureAttachments") -Default $true
    $saveAttachments = Test-NomadInboxAccountOption -Account $Account -Names @("saveAttachments", "storeAttachmentBytes") -Default $false
    $folder = if ([string]::IsNullOrWhiteSpace($Account.folder)) { "Inbox" } else { [string]$Account.folder }
    $headers = @{ Authorization = "Bearer $token" }
    $top = [Math]::Max(1, [Math]::Min(100, $limit))
    $select = "id,conversationId,conversationIndex,subject,from,toRecipients,ccRecipients,bccRecipients,replyTo,receivedDateTime,sentDateTime,bodyPreview,isRead,flag,importance,categories,hasAttachments,internetMessageId,webLink,parentFolderId"
    if ($includeBodies) { $select += ",body" }
    $base = if ($folder -ieq "Inbox") { "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages" } else { "https://graph.microsoft.com/v1.0/me/messages" }
    $uri = "$base?`$top=$top&`$orderby=receivedDateTime desc&`$select=$select"
    try {
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
        $records = @()
        $rawRecords = @()
        foreach ($message in @($response.value | Where-Object { $null -ne $_ -and $_.id })) {
            $attachments = @()
            if ($includeAttachments -and $message.hasAttachments) {
                try {
                    $attachmentUri = "https://graph.microsoft.com/v1.0/me/messages/$([uri]::EscapeDataString([string]$message.id))/attachments"
                    $attachmentResponse = Invoke-RestMethod -Method Get -Uri $attachmentUri -Headers $headers
                    $attachmentIndex = 0
                    foreach ($attachment in @($attachmentResponse.value)) {
                        $attachmentIndex++
                        $localPath = $null
                        if ($saveAttachments -and $attachment.contentBytes) {
                            $fileName = if ($attachment.name) { [string]$attachment.name } else { "attachment-$attachmentIndex.bin" }
                            $localPath = Get-NomadInboxAttachmentOutputPath -Provider "outlook-graph" -ProviderMessageId ([string]$message.id) -Index $attachmentIndex -FileName $fileName
                            [System.IO.File]::WriteAllBytes($localPath, [System.Convert]::FromBase64String([string]$attachment.contentBytes))
                        }
                        $attachments += [pscustomobject]@{
                            id = [string]$attachment.id
                            name = [string]$attachment.name
                            contentType = [string]$attachment.contentType
                            sizeBytes = if ($attachment.size) { [int64]$attachment.size } else { $null }
                            localPath = $localPath
                            isInline = if ($null -ne $attachment.isInline) { [bool]$attachment.isInline } else { $false }
                        }
                    }
                    $message | Add-Member -NotePropertyName attachments -NotePropertyValue @($attachmentResponse.value) -Force
                } catch {
                }
            }
            $rawRef = $null
            if ($captureRaw) {
                $rawRef = Get-NomadInboxProviderRawId -Provider "outlook-graph" -AccountId $Account.id -ProviderMessageId ([string]$message.id)
                $rawRecords += New-NomadInboxProviderRawRecord `
                    -Provider "outlook-graph" `
                    -AccountId $Account.id `
                    -ProviderMessageId ([string]$message.id) `
                    -ConversationId ([string]$message.conversationId) `
                    -RawObject $message `
                    -BodyCaptured:$includeBodies `
                    -AttachmentMetadataCaptured:$includeAttachments `
                    -AttachmentBytesCaptured:$saveAttachments
            }
            $records += ConvertFrom-NomadInboxGraphMessage -Message $message -Account $Account -Attachments $attachments -ProviderRawRef $rawRef -RawCaptured:$captureRaw -IncludeBodies:$includeBodies
        }
        Write-NomadInboxLiveMessages -Records $records
        if ($rawRecords.Count -gt 0) { Write-NomadInboxProviderRawRecords -Records $rawRecords }
        Write-NomadInboxActionRecord -ActionType "sync" -Status "success" -InputObject @{ accountId = $Account.id; provider = $Account.provider; folder = $Account.folder; limit = $Account.limit } -ResultObject @{ synced = $records.Count } -ErrorMessage $null | Out-Null
        return New-NomadInboxSyncResult -Account $Account -Status "ok" -Reason $null -Synced $records.Count -StartedAt $StartedAt
    } catch {
        Write-NomadInboxActionRecord -ActionType "sync" -Status "error" -InputObject @{ accountId = $Account.id; provider = $Account.provider } -ResultObject @{} -ErrorMessage ([string]$_.Exception.Message) | Out-Null
        return New-NomadInboxSyncResult -Account $Account -Status "error" -Reason ([string]$_.Exception.Message) -Synced 0 -StartedAt $StartedAt
    }
}

function ConvertFrom-NomadInboxOutlookDesktopItem {
    param($Item, $Account, [array]$Attachments = @(), [string]$ProviderRawRef = "", [bool]$RawCaptured = $false, [bool]$IncludeBodies = $false)
    $receivedAt = if ($Item.ReceivedTime) { ConvertTo-NomadInboxUtcIsoFromDateTime ([datetime]$Item.ReceivedTime) } else { Get-NomadInboxUtcNowIso }
    $sentAt = if ($Item.SentOn) { ConvertTo-NomadInboxUtcIsoFromDateTime ([datetime]$Item.SentOn) } else { $null }
    $entryId = if ($Item.EntryID) { [string]$Item.EntryID } else { ConvertTo-NomadInboxHash ([string]$Item.Subject + [string]$receivedAt) }
    $senderEmail = if ($Item.SenderEmailAddress) { [string]$Item.SenderEmailAddress } else { "unknown@example.invalid" }
    $senderName = if ($Item.SenderName) { [string]$Item.SenderName } else { $null }
    $body = if ($Item.Body) { [string]$Item.Body } else { "" }
    $htmlBody = if ($IncludeBodies -and $Item.HTMLBody) { [string]$Item.HTMLBody } else { $null }
    New-NomadInboxLiveMessage `
        -Provider "outlook-desktop" `
        -AccountId $Account.id `
        -ProviderMessageId $entryId `
        -ConversationId ([string]$Item.ConversationID) `
        -Folder $Account.folder `
        -Subject ([string]$Item.Subject) `
        -From ([pscustomobject]@{ name = $senderName; email = $senderEmail }) `
        -To (ConvertTo-NomadInboxAddressList ([string]$Item.To)) `
        -Cc (ConvertTo-NomadInboxAddressList ([string]$Item.CC)) `
        -ReceivedAt $receivedAt `
        -SentAt $sentAt `
        -Snippet $body `
        -BodyText $(if ($IncludeBodies) { $body } else { $null }) `
        -BodyHtml $htmlBody `
        -Headers @{} `
        -Unread ([bool]$Item.UnRead) `
        -Flagged ([bool]$Item.IsMarkedAsTask) `
        -Importance ([string]$Item.Importance) `
        -Categories (@(([string]$Item.Categories) -split ',' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })) `
        -Attachments @($Attachments) `
        -Capabilities @("reply", "replyAll", "forward", "markRead", "markUnread", "flag", "unflag", "move", "archive", "trash", "saveAttachment") `
        -ProviderRawRef $ProviderRawRef `
        -RawCaptured $RawCaptured
}

function Invoke-NomadInboxOutlookDesktopSync {
    param($Account, [datetime]$StartedAt)
    if (-not $IsWindows -and $PSVersionTable.PSEdition -eq "Core") {
        return New-NomadInboxSyncResult -Account $Account -Status "unsupportedRuntime" -Reason "Outlook Desktop sync requires Windows PowerShell in a signed-in desktop session." -Synced 0 -StartedAt $StartedAt
    }
    $limit = if ($Account.limit) { [int]$Account.limit } else { 25 }
    $captureRaw = Test-NomadInboxAccountOption -Account $Account -Names @("captureRawProviderData", "captureRaw", "storeRaw") -Default $true
    $includeBodies = Test-NomadInboxAccountOption -Account $Account -Names @("includeBodies", "storeBodies") -Default $false
    $includeAttachments = Test-NomadInboxAccountOption -Account $Account -Names @("includeAttachments", "captureAttachments") -Default $true
    $saveAttachments = Test-NomadInboxAccountOption -Account $Account -Names @("saveAttachments", "storeAttachmentBytes") -Default $false
    try {
        $outlook = New-Object -ComObject Outlook.Application
        $namespace = $outlook.GetNamespace("MAPI")
        $folder = $namespace.GetDefaultFolder(6)
        $items = $folder.Items
        $items.Sort("[ReceivedTime]", $true)
        $records = @()
        $rawRecords = @()
        $count = [Math]::Min($items.Count, [Math]::Max(1, $limit))
        for ($i = 1; $i -le $count; $i++) {
            try {
                $item = $items.Item($i)
                if ($null -eq $item) { continue }
                if ($item.MessageClass -and -not ([string]$item.MessageClass).StartsWith("IPM.Note")) { continue }
                $entryId = if ($item.EntryID) { [string]$item.EntryID } else { ConvertTo-NomadInboxHash ([string]$item.Subject + [string]$item.ReceivedTime) }
                $attachments = if ($includeAttachments) { Get-NomadInboxOutlookAttachmentMetadata -Item $item -ProviderMessageId $entryId -SaveBytes:$saveAttachments } else { @() }
                $rawRef = $null
                if ($captureRaw) {
                    $rawRef = Get-NomadInboxProviderRawId -Provider "outlook-desktop" -AccountId $Account.id -ProviderMessageId $entryId
                    $rawRecords += New-NomadInboxProviderRawRecord `
                        -Provider "outlook-desktop" `
                        -AccountId $Account.id `
                        -ProviderMessageId $entryId `
                        -ConversationId ([string]$item.ConversationID) `
                        -RawObject (New-NomadInboxOutlookRawSnapshot -Item $item -Attachments $attachments -IncludeBodies:$includeBodies) `
                        -BodyCaptured:$includeBodies `
                        -AttachmentMetadataCaptured:$includeAttachments `
                        -AttachmentBytesCaptured:$saveAttachments
                }
                $records += ConvertFrom-NomadInboxOutlookDesktopItem -Item $item -Account $Account -Attachments $attachments -ProviderRawRef $rawRef -RawCaptured:$captureRaw -IncludeBodies:$includeBodies
            } catch {
            }
        }
        Write-NomadInboxLiveMessages -Records $records
        if ($rawRecords.Count -gt 0) { Write-NomadInboxProviderRawRecords -Records $rawRecords }
        Write-NomadInboxActionRecord -ActionType "sync" -Status "success" -InputObject @{ accountId = $Account.id; provider = $Account.provider; folder = $Account.folder; limit = $Account.limit } -ResultObject @{ synced = $records.Count } -ErrorMessage $null | Out-Null
        return New-NomadInboxSyncResult -Account $Account -Status "ok" -Reason $null -Synced $records.Count -StartedAt $StartedAt
    } catch {
        Write-NomadInboxActionRecord -ActionType "sync" -Status "error" -InputObject @{ accountId = $Account.id; provider = $Account.provider } -ResultObject @{} -ErrorMessage ([string]$_.Exception.Message) | Out-Null
        return New-NomadInboxSyncResult -Account $Account -Status "error" -Reason ([string]$_.Exception.Message) -Synced 0 -StartedAt $StartedAt
    }
}

function Invoke-NomadInboxAccountSync {
    param($Account)
    $startedAt = [datetime]::UtcNow
    if (-not [bool]$Account.enabled) {
        return New-NomadInboxSyncResult -Account $Account -Status "skipped" -Reason "accountDisabled" -Synced 0 -StartedAt $startedAt
    }

    if ($Account.provider -eq "sample") {
        $sample = New-NomadInboxSampleMessage
        $sample.id = "sample:" + $Account.id + ":" + ([datetimeoffset]::UtcNow.UtcDateTime.ToString("yyyyMMddHHmmss", [System.Globalization.CultureInfo]::InvariantCulture))
        Write-NomadInboxLiveMessages -Records @($sample)
        Write-NomadInboxActionRecord -ActionType "sync" -Status "success" -InputObject @{ accountId = $Account.id; provider = $Account.provider } -ResultObject @{ synced = 1 } -ErrorMessage $null | Out-Null
        return New-NomadInboxSyncResult -Account $Account -Status "ok" -Reason $null -Synced 1 -StartedAt $startedAt
    }

    switch ($Account.provider) {
        "gmail-api" { return Invoke-NomadInboxGmailApiSync -Account $Account -StartedAt $startedAt }
        "outlook-graph" { return Invoke-NomadInboxOutlookGraphSync -Account $Account -StartedAt $startedAt }
        "outlook-desktop" { return Invoke-NomadInboxOutlookDesktopSync -Account $Account -StartedAt $startedAt }
    }

    Write-NomadInboxActionRecord -ActionType "sync" -Status "dryRun" -InputObject @{ accountId = $Account.id; provider = $Account.provider; folder = $Account.folder; limit = $Account.limit } -ResultObject @{ synced = 0; reason = "providerAdapterNotInstalled" } -ErrorMessage $null | Out-Null
    New-NomadInboxSyncResult -Account $Account -Status "pendingProviderAdapter" -Reason "Provider adapter is not installed for this provider." -Synced 0 -StartedAt $startedAt
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
    $now = [datetimeoffset]::UtcNow
    $enabledIntervals = @($accounts | Where-Object { [bool]$_.enabled } | ForEach-Object { if ($_.intervalSeconds) { [int]$_.intervalSeconds } elseif ($config.defaultIntervalSeconds) { [int]$config.defaultIntervalSeconds } else { 300 } })
    $interval = if ($enabledIntervals.Count -gt 0) { ($enabledIntervals | Measure-Object -Minimum).Minimum } elseif ($config.defaultIntervalSeconds) { [int]$config.defaultIntervalSeconds } else { 300 }
    $status = [pscustomobject]@{
        service = $script:ServiceName
        worker = if ($WorkerRunning -or (Test-NomadInboxWorkerRunning)) { "running" } else { "stopped" }
        lastRunAt = $now.UtcDateTime.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
        nextRunAt = $now.AddSeconds($interval).UtcDateTime.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
        accounts = $results
        updatedAt = $now.UtcDateTime.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
        timeContext = Get-NomadInboxTimeContext
    }
    Write-NomadInboxSyncStatus $status | Out-Null
    [pscustomobject]@{
        status = "ok"
        service = $script:ServiceName
        accountCount = $results.Count
        results = $results
        statusPath = Get-NomadInboxStatusPath
        timeContext = Get-NomadInboxTimeContext
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
        timeContext = Get-NomadInboxTimeContext
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
        $status.updatedAt = Get-NomadInboxUtcNowIso
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
            updatedAt = Get-NomadInboxUtcNowIso
            timeContext = Get-NomadInboxTimeContext
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
    $rawCount = Get-NomadInboxJsonlCount (Get-NomadInboxProviderRawPath)
    $extractCount = Get-NomadInboxJsonlCount (Get-NomadInboxMessageExtractsPath)
    $threadIndexCount = Get-NomadInboxJsonlCount (Get-NomadInboxThreadIndexPath)
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
        $prompts += "Last live sync ran at $(ConvertTo-NomadInboxLocalTimeText $syncStatus.lastRunAt). Run 'sync once' or enable background sync to keep this fresher."
    }
    if ($null -ne $importStatus -and $importStatus.lastImportAt) {
        $prompts += "Last archive import ran at $(ConvertTo-NomadInboxLocalTimeText $importStatus.lastImportAt) from $($importStatus.lastSource). Re-run import when you export more historical mail."
    }

    [pscustomobject]@{
        status = "ok"
        service = $script:ServiceName
        liveSyncedMessages = $liveCount
        providerRawSnapshots = $rawCount
        messageExtracts = $extractCount
        threadIndexRecords = $threadIndexCount
        archiveImportedMessages = $archiveCount
        archiveIndexedMessages = $indexCount
        totalBackedUpMessages = $liveCount + $archiveCount
        messagesPath = Get-NomadInboxMessagesPath
        providerRawPath = Get-NomadInboxProviderRawPath
        messageExtractsPath = Get-NomadInboxMessageExtractsPath
        threadIndexPath = Get-NomadInboxThreadIndexPath
        archiveMessagesPath = Get-NomadInboxArchiveMessagesPath
        archiveIndexPath = Get-NomadInboxArchiveIndexPath
        syncStatus = $syncStatus
        importStatus = $importStatus
        userPrompts = $prompts
        updatedAt = Get-NomadInboxUtcNowIso
        timeContext = Get-NomadInboxTimeContext
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
        importedAt = Get-NomadInboxUtcNowIso
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
    $receivedAt = if ($InputObject.receivedAt) { ConvertTo-NomadInboxIsoDate ([string]$InputObject.receivedAt) } else { Get-NomadInboxUtcNowIso }
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
        importedAt = Get-NomadInboxUtcNowIso
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
    $batchId = "import-" + ([datetimeoffset]::UtcNow.UtcDateTime.ToString("yyyyMMddHHmmss", [System.Globalization.CultureInfo]::InvariantCulture)) + "-" + ([guid]::NewGuid().ToString("n").Substring(0, 8))
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
    $now = Get-NomadInboxUtcNowIso
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
        timeContext = Get-NomadInboxTimeContext
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
        timeContext = Get-NomadInboxTimeContext
        userPrompt = "Imported archive messages are read-only context. Use live sync for actions, and run 'backup status' to see how much mail context is backed up."
    }
}

function Test-NomadInbox {
    $root = Get-NomadInboxRoot
    $required = @(
        "README.md",
        "schemas\message.v1.json",
        "schemas\provider-raw.v1.json",
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
        timeContext = Get-NomadInboxTimeContext
        config = Get-NomadInboxConfigStatus
    }
}

function Get-NomadInboxSchemas {
    $root = Get-NomadInboxRoot
    [pscustomobject]@{
        status = "ok"
        schemas = @(
            [pscustomobject]@{ name = "message.v1"; path = Join-Path $root "schemas\message.v1.json" },
            [pscustomobject]@{ name = "provider-raw.v1"; path = Join-Path $root "schemas\provider-raw.v1.json" },
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
        receivedAt = Get-NomadInboxUtcNowIso
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
    ConvertTo-NomadInboxOptions, Get-NomadInboxOption, Require-NomadInboxOption, `
    Get-NomadInboxTimeContext, ConvertTo-NomadInboxLocalTimeText
