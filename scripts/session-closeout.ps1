param(
    [Parameter(Mandatory = $true)]
    [string]$Title,

    [Parameter(Mandatory = $true)]
    [string]$Summary,

    [switch]$SkipChangeNote
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$newChangeScript = Join-Path $PSScriptRoot "new-architecture-change.ps1"
$stateScript = Join-Path $PSScriptRoot "update-workspace-state.ps1"
$validateScript = Join-Path $PSScriptRoot "validate.ps1"

Push-Location $repoRoot
try {
    $gitChanged = @()
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $gitChanged = git status --short --untracked-files=all
    }

    if (-not $SkipChangeNote) {
        & $newChangeScript -Title $Title -Summary $Summary
    }

    & $stateScript -Title $Title -Summary $Summary -Status "completed"

    & $validateScript

    [pscustomobject]@{
        status = "ok"
        project = $repoRoot
        architectureIndex = Join-Path $repoRoot "docs\ARCHITECTURE_INDEX.md"
        workspaceState = Join-Path $repoRoot "docs\governance\WORKSPACE_STATE.md"
        changedFiles = $gitChanged
        reminder = "Commit code and affected architecture docs together. For documentation-only or primarily documentation commits, use the fixed docs subject from ARCHITECTURE_UPDATE_PROCESS.md and generic folder-level body lines only."
    } | ConvertTo-Json -Depth 5
}
finally {
    Pop-Location
}
