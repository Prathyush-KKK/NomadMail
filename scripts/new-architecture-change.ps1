param(
    [Parameter(Mandatory = $true)]
    [string]$Title,

    [Parameter(Mandatory = $true)]
    [string]$Summary
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$updatesDir = Join-Path $repoRoot "docs\governance\session-updates"
$changelog = Join-Path $repoRoot "docs\governance\SESSION_CHANGELOG.md"
$template = Join-Path $repoRoot "docs\templates\session-architecture-update.md"

New-Item -ItemType Directory -Force -Path $updatesDir | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$safeTitle = ($Title.ToLowerInvariant() -replace '[^a-z0-9]+', '-' -replace '(^-|-$)', '')
$file = Join-Path $updatesDir "$stamp-$safeTitle.md"
$today = Get-Date -Format "yyyy-MM-dd"

$content = Get-Content -LiteralPath $template -Raw
$content = $content.Replace("TITLE", $Title).Replace("YYYY-MM-DD", $today).Replace("SUMMARY", $Summary)
$content | Set-Content -LiteralPath $file -Encoding UTF8

$entry = @"

## $today - $Title

Summary:

- $Summary

Session note:

- docs/governance/session-updates/$stamp-$safeTitle.md
"@

$existing = if (Test-Path -LiteralPath $changelog) { Get-Content -LiteralPath $changelog -Raw } else { "# Session Architecture Changelog`r`n" }
$header = "# Session Architecture Changelog"
if ($existing.StartsWith($header)) {
    $updated = $header + "`r`n" + $entry + "`r`n" + ($existing.Substring($header.Length).TrimStart())
} else {
    $updated = $entry + "`r`n" + $existing
}
$updated | Set-Content -LiteralPath $changelog -Encoding UTF8

[pscustomobject]@{
    status = "ok"
    updateFile = $file
    changelog = $changelog
} | ConvertTo-Json -Depth 5

