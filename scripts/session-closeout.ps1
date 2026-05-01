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

    & $validateScript

    [pscustomobject]@{
        status = "ok"
        project = $repoRoot
        architectureIndex = Join-Path $repoRoot "docs\ARCHITECTURE_INDEX.md"
        changedFiles = $gitChanged
        reminder = "Commit code and affected architecture docs together."
    } | ConvertTo-Json -Depth 5
}
finally {
    Pop-Location
}

