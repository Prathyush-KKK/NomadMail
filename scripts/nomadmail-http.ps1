param(
    [int]$Port = 8791,
    [string]$HostName = "127.0.0.1",
    [string]$Node = "node"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$service = Join-Path $repoRoot "service\nomadmail-service.mjs"

& $Node $service http --port $Port --host $HostName
