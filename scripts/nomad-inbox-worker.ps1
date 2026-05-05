param(
    [int]$IntervalSeconds = 0
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot "config\nomad-inbox.ps1"
if (Test-Path -LiteralPath $configPath) {
    . $configPath
}

Import-Module (Join-Path $repoRoot "src\NomadInbox\NomadInbox.psm1") -Force -DisableNameChecking

Initialize-NomadInbox | Out-Null
Initialize-NomadInboxAccountsConfig | Out-Null

function Get-NomadInboxWorkerLogTime {
    $utcNow = [datetimeoffset]::UtcNow.UtcDateTime.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
    return ConvertTo-NomadInboxLocalTimeText $utcNow
}

while ($true) {
    try {
        $result = Invoke-NomadInboxSyncOnce -WorkerRunning
        ("[{0}] sync status={1} accounts={2}" -f (Get-NomadInboxWorkerLogTime), $result.status, $result.accountCount) | Write-Output
    } catch {
        ("[{0}] sync error={1}" -f (Get-NomadInboxWorkerLogTime), [string]$_) | Write-Output
    }

    $accounts = Get-NomadInboxAccounts
    $enabledIntervals = @($accounts.accounts | Where-Object { $_.enabled } | ForEach-Object { [int]$_.intervalSeconds })
    $sleepSeconds = if ($IntervalSeconds -gt 0) {
        $IntervalSeconds
    } elseif ($enabledIntervals.Count -gt 0) {
        ($enabledIntervals | Measure-Object -Minimum).Minimum
    } elseif ($accounts.defaultIntervalSeconds) {
        [int]$accounts.defaultIntervalSeconds
    } else {
        300
    }
    Start-Sleep -Seconds ([Math]::Max(30, $sleepSeconds))
}
