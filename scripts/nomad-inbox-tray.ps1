$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $repoRoot "scripts\nomad-inbox.ps1"
$configPath = Join-Path $repoRoot "config\accounts.json"
$exampleConfigPath = Join-Path $repoRoot "config\accounts.example.json"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Invoke-NomadInboxCliText {
    param([string[]]$Arguments)
    try {
        $output = & $cli @Arguments
        return ($output | Out-String).Trim()
    } catch {
        return [string]$_
    }
}

function Show-NomadInboxBalloon {
    param([System.Windows.Forms.NotifyIcon]$Icon, [string]$Title, [string]$Text)
    $Icon.BalloonTipTitle = $Title
    $Icon.BalloonTipText = if ($Text.Length -gt 240) { $Text.Substring(0, 240) + "..." } else { $Text }
    $Icon.ShowBalloonTip(3000)
}

function Ensure-AccountsConfig {
    if (-not (Test-Path -LiteralPath $configPath)) {
        Copy-Item -LiteralPath $exampleConfigPath -Destination $configPath
    }
}

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.SystemIcons]::Application
$notify.Text = "NomadInbox"
$notify.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$statusItem = $menu.Items.Add("Show sync status")
$statusItem.Add_Click({
    $text = Invoke-NomadInboxCliText @("service", "status")
    Show-NomadInboxBalloon $notify "NomadInbox status" $text
})

$startItem = $menu.Items.Add("Start background sync")
$startItem.Add_Click({
    $text = Invoke-NomadInboxCliText @("service", "start")
    Show-NomadInboxBalloon $notify "NomadInbox started" $text
})

$stopItem = $menu.Items.Add("Stop background sync")
$stopItem.Add_Click({
    $text = Invoke-NomadInboxCliText @("service", "stop")
    Show-NomadInboxBalloon $notify "NomadInbox stopped" $text
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

$notify.ContextMenuStrip = $menu
Show-NomadInboxBalloon $notify "NomadInbox" "Tray is running. Right-click the icon to start sync, stop sync, check status, or edit accounts."
[System.Windows.Forms.Application]::Run()

