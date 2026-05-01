$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$required = @(
    "README.md",
    ".gitignore",
    "config\nomad-inbox.example.ps1",
    "scripts\nomad-inbox.ps1",
    "scripts\new-architecture-change.ps1",
    "scripts\session-closeout.ps1",
    "src\NomadInbox\NomadInbox.psm1",
    "schemas\message.v1.json",
    "schemas\action.v1.json",
    "docs\ARCHITECTURE_INDEX.md",
    "docs\PRODUCT_SPEC.md",
    "docs\ARCHITECTURE.md",
    "docs\c4\01-system-context.md",
    "docs\c4\02-container.md",
    "docs\c4\03-dynamic-flows.md",
    "docs\adrs\0001-create-fresh-nomadinbox-repository.md",
    "docs\service-catalog\service-catalog.yaml",
    "docs\processes\process-catalog.md",
    "docs\runbooks\local-bootstrap.md",
    "docs\slo\nomadinbox-slo.md",
    "docs\governance\ARCHITECTURE_UPDATE_PROCESS.md",
    "docs\governance\SESSION_CHANGELOG.md",
    "api\openapi\nomadinbox.v1.yaml",
    "api\asyncapi\nomadinbox-events.v1.yaml"
)

$missing = @()
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $path))) {
        $missing += $path
    }
}

$forbiddenTracked = @()
if (Get-Command git -ErrorAction SilentlyContinue) {
    $tracked = git -C $repoRoot ls-files
    $forbiddenTracked = @($tracked | Where-Object {
        $_ -match '^data/' -or
        $_ -match '^runtime/' -or
        $_ -match '^target/' -or
        $_ -match 'token-cache' -or
        $_ -match 'client_secret' -or
        $_ -match '^config/nomad-inbox\.ps1$'
    })
}

$result = [pscustomobject]@{
    status = if ($missing.Count -eq 0 -and $forbiddenTracked.Count -eq 0) { "ok" } else { "failed" }
    project = $repoRoot
    missing = $missing
    forbiddenTracked = $forbiddenTracked
}

$result | ConvertTo-Json -Depth 10
if ($result.status -ne "ok") { exit 1 }
