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

function Test-NomadInbox {
    $root = Get-NomadInboxRoot
    $required = @(
        "README.md",
        "schemas\message.v1.json",
        "schemas\action.v1.json",
        "config\nomad-inbox.example.ps1",
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
    Test-NomadInbox, Get-NomadInboxSchemas, New-NomadInboxSampleMessage

