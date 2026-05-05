param(
    [string]$Node = "node"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$service = Join-Path $repoRoot "service\nomadmail-service.mjs"

& $Node $service mcp
