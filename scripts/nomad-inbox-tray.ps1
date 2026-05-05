$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $repoRoot "scripts\nomad-inbox.ps1"
$configPath = Join-Path $repoRoot "config\accounts.json"
$exampleConfigPath = Join-Path $repoRoot "config\accounts.example.json"
$startupPromptPath = Join-Path $repoRoot "prompts\nomadmail-startup.system.md"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:lastState = $null
$script:statusItem = $null
$script:autoSyncItem = $null
$script:connectItem = $null

function Invoke-NomadInboxCliText {
    param([string[]]$Arguments)
    try {
        $output = & $cli @Arguments
        return ($output | Out-String).Trim()
    } catch {
        return [string]$_
    }
}

function Invoke-NomadInboxCliJson {
    param([string[]]$Arguments)
    $text = Invoke-NomadInboxCliText -Arguments $Arguments
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try {
        return ($text | ConvertFrom-Json)
    } catch {
        return [pscustomobject]@{
            status = "error"
            command = ($Arguments -join " ")
            error = $text
        }
    }
}

function Show-NomadInboxBalloon {
    param([System.Windows.Forms.NotifyIcon]$Icon, [string]$Title, [string]$Text)
    $Icon.BalloonTipTitle = $Title
    $Icon.BalloonTipText = if ($Text.Length -gt 240) { $Text.Substring(0, 240) + "..." } else { $Text }
    $Icon.ShowBalloonTip(3000)
}

function Show-NomadInboxMessage {
    param([string]$Title, [string]$Text)
    [System.Windows.Forms.MessageBox]::Show(
        $Text,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Ensure-AccountsConfig {
    if (-not (Test-Path -LiteralPath $configPath)) {
        Copy-Item -LiteralPath $exampleConfigPath -Destination $configPath
    }
}

function Get-NomadInboxAgentPrompt {
    $systemPrompt = if (Test-Path -LiteralPath $startupPromptPath) {
        (Get-Content -LiteralPath $startupPromptPath -Raw).Trim()
    } else {
        "Load the NomadMail agent guide, ask before account discovery, and do not start auto sync until explicitly approved."
    }

    @"
$systemPrompt

Current task:
Connect NomadMail/NomadInbox email accounts for auto sync only after asking which provider and account scope to use. Run one request-driven sync first, then start background auto sync only after explicit approval.
"@
}

function Copy-NomadInboxAgentPrompt {
    $prompt = Get-NomadInboxAgentPrompt
    try {
        [System.Windows.Forms.Clipboard]::SetText($prompt)
        return $true
    } catch {
        return $false
    }
}

function Get-NomadInboxTrayState {
    [pscustomobject]@{
        service = Invoke-NomadInboxCliJson @("service", "status")
        accounts = Invoke-NomadInboxCliJson @("accounts", "list")
        providers = Invoke-NomadInboxCliJson @("providers", "list")
    }
}

function Get-NomadInboxEnabledAccounts {
    param($AccountsResult)
    if ($null -eq $AccountsResult -or $null -eq $AccountsResult.accounts) { return @() }
    return @($AccountsResult.accounts | Where-Object { [bool]$_.enabled })
}

function Get-NomadInboxAccountCount {
    param($AccountsResult)
    if ($null -eq $AccountsResult -or $null -eq $AccountsResult.accounts) { return 0 }
    return @($AccountsResult.accounts).Count
}

function Format-NomadInboxStatusText {
    param($State)

    if ($null -eq $State -or $null -eq $State.service) {
        return "NomadInbox status is unavailable. Open your agent and check NomadMail service status before syncing."
    }

    $service = $State.service
    $accounts = $State.accounts
    $enabledAccounts = Get-NomadInboxEnabledAccounts $accounts
    $totalAccounts = Get-NomadInboxAccountCount $accounts
    $worker = if ($service.worker) { [string]$service.worker } else { "unknown" }
    $backup = $service.backupStatus
    $syncStatus = $service.syncStatus

    $lines = New-Object System.Collections.Generic.List[string]
    if ($worker -eq "running") {
        $lines.Add("Auto sync: on")
        if ($backup) {
            $lines.Add(("Live messages: {0}" -f $backup.liveSyncedMessages))
            $lines.Add(("Archive messages: {0}" -f $backup.archiveImportedMessages))
        }
        if ($syncStatus) {
            $lines.Add(("Last run: {0}" -f $syncStatus.lastRunAt))
            $lines.Add(("Next run: {0}" -f $syncStatus.nextRunAt))
        }
        if ($syncStatus -and $syncStatus.accounts) {
            $accountSummaries = @($syncStatus.accounts | ForEach-Object {
                "{0}: {1}, synced {2}" -f $_.accountId, $_.status, $_.synced
            })
            if ($accountSummaries.Count -gt 0) {
                $lines.Add(("Accounts: {0}" -f ($accountSummaries -join "; ")))
            }
        }
    } else {
        $lines.Add("Auto sync: off")
        $lines.Add("No background sync process is running.")
        $lines.Add("Open your agent and perform a request-driven NomadMail sync, or turn on auto sync here after email accounts are connected.")
        if ($syncStatus -and $syncStatus.lastRunAt) {
            $lines.Add(("Last run: {0}" -f $syncStatus.lastRunAt))
        }
    }

    $lines.Add(("Enabled accounts: {0}/{1}" -f @($enabledAccounts).Count, $totalAccounts))
    if (@($enabledAccounts).Count -eq 0) {
        $lines.Add("No accounts are enabled. Use 'Connect accounts with agent' first.")
    }

    return ($lines -join [Environment]::NewLine)
}

function Update-NomadInboxTrayUi {
    param([System.Windows.Forms.NotifyIcon]$Icon)

    try {
        $script:lastState = Get-NomadInboxTrayState
        $worker = if ($script:lastState.service.worker) { [string]$script:lastState.service.worker } else { "unknown" }
        $enabled = Get-NomadInboxEnabledAccounts $script:lastState.accounts

        if ($worker -eq "running") {
            $Icon.Text = "NomadInbox - auto sync on"
            if ($script:autoSyncItem) { $script:autoSyncItem.Text = "Turn off auto sync" }
        } else {
            $Icon.Text = "NomadInbox - auto sync off"
            if ($script:autoSyncItem) { $script:autoSyncItem.Text = "Turn on auto sync" }
        }

        if ($script:statusItem) {
            $script:statusItem.Text = if ($worker -eq "running") {
                "Show auto sync status"
            } else {
                "Show sync instructions"
            }
        }
        if ($script:connectItem) {
            $script:connectItem.Text = if (@($enabled).Count -gt 0) {
                "Review accounts with agent"
            } else {
                "Connect accounts with agent"
            }
        }
    } catch {
        $Icon.Text = "NomadInbox - status unknown"
    }
}

function Show-NomadInboxStatus {
    param([System.Windows.Forms.NotifyIcon]$Icon)
    Update-NomadInboxTrayUi $Icon
    $text = Format-NomadInboxStatusText $script:lastState
    Show-NomadInboxBalloon $Icon "NomadInbox" $text
    Show-NomadInboxMessage "NomadInbox sync status" $text
}

function Show-NomadInboxConnectPrompt {
    param([System.Windows.Forms.NotifyIcon]$Icon)
    Ensure-AccountsConfig
    $copied = Copy-NomadInboxAgentPrompt
    $message = if ($copied) {
        "The built-in NomadMail startup system prompt was copied as a fallback for agents without NomadMail tool access. Open your agent chat and use NomadMail agent guide first when available."
    } else {
        "Open your agent chat and ask it to use the NomadMail agent guide. It should ask permission before discovering Gmail tokens, Graph tokens, Azure CLI state, or the Outlook Desktop profile."
    }
    $message = $message + [Environment]::NewLine + [Environment]::NewLine + "Accounts config: $configPath"
    Show-NomadInboxBalloon $Icon "Connect NomadInbox accounts" $message
    Show-NomadInboxMessage "Connect accounts with agent" $message
}

function Start-NomadInboxAutoSync {
    param([System.Windows.Forms.NotifyIcon]$Icon)
    Ensure-AccountsConfig
    $state = Get-NomadInboxTrayState
    $enabledAccounts = Get-NomadInboxEnabledAccounts $state.accounts
    if (@($enabledAccounts).Count -eq 0) {
        Show-NomadInboxConnectPrompt $Icon
        return
    }

    $result = Invoke-NomadInboxCliText @("service", "start")
    Update-NomadInboxTrayUi $Icon
    Show-NomadInboxBalloon $Icon "NomadInbox auto sync on" $result
}

function Stop-NomadInboxAutoSync {
    param([System.Windows.Forms.NotifyIcon]$Icon)
    $result = Invoke-NomadInboxCliText @("service", "stop")
    Update-NomadInboxTrayUi $Icon
    Show-NomadInboxBalloon $Icon "NomadInbox auto sync off" $result
}

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.SystemIcons]::Application
$notify.Text = "NomadInbox"
$notify.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$script:statusItem = $menu.Items.Add("Show sync instructions")
$script:statusItem.Add_Click({
    Show-NomadInboxStatus $notify
})

$script:autoSyncItem = $menu.Items.Add("Turn on auto sync")
$script:autoSyncItem.Add_Click({
    Update-NomadInboxTrayUi $notify
    $worker = if ($script:lastState.service.worker) { [string]$script:lastState.service.worker } else { "unknown" }
    if ($worker -eq "running") {
        Stop-NomadInboxAutoSync $notify
    } else {
        Start-NomadInboxAutoSync $notify
    }
})

$script:connectItem = $menu.Items.Add("Connect accounts with agent")
$script:connectItem.Add_Click({
    Show-NomadInboxConnectPrompt $notify
})

$accountsItem = $menu.Items.Add("Open accounts config")
$accountsItem.Add_Click({
    Ensure-AccountsConfig
    Start-Process notepad.exe $configPath
})

$folderItem = $menu.Items.Add("Open runtime folder")
$folderItem.Add_Click({
    & $cli setup | Out-Null
    Start-Process explorer.exe (Join-Path $repoRoot "data")
})

$repoItem = $menu.Items.Add("Open NomadInbox folder")
$repoItem.Add_Click({
    Start-Process explorer.exe $repoRoot
})

$exitItem = $menu.Items.Add("Exit tray")
$exitItem.Add_Click({
    $notify.Visible = $false
    $notify.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

$menu.Add_Opening({
    Update-NomadInboxTrayUi $notify
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 30000
$timer.Add_Tick({
    Update-NomadInboxTrayUi $notify
})
$timer.Start()

$notify.ContextMenuStrip = $menu
Update-NomadInboxTrayUi $notify
$initialEnabledAccounts = Get-NomadInboxEnabledAccounts $script:lastState.accounts
if (@($initialEnabledAccounts).Count -eq 0) {
    Show-NomadInboxBalloon $notify "Connect NomadInbox accounts" "No accounts are enabled. Right-click the tray icon and choose Connect accounts with agent; the agent should ask before checking Gmail, Graph, Azure CLI, or Outlook Desktop profile state."
} else {
    Show-NomadInboxBalloon $notify "NomadInbox" "Tray is running. Right-click the icon to connect accounts, turn auto sync on or off, and check sync status."
}
[System.Windows.Forms.Application]::Run()
