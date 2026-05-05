param(
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "src\NomadInbox.Tray\NomadInboxTray.cs"
$iconPath = Join-Path $repoRoot "assets\nomadinbox-tray.ico"
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot "target\NomadInboxTray\NomadInboxTray.exe"
}

$outputDir = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$tempDir = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    Join-Path $env:USERPROFILE "AppData\Local\Temp"
} else {
    Join-Path $env:LOCALAPPDATA "Temp"
}
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
$env:TEMP = $tempDir
$env:TMP = $tempDir

$references = @(
    "System.dll",
    "System.Core.dll",
    "System.Drawing.dll",
    "System.Windows.Forms.dll",
    "System.Web.Extensions.dll"
)

if (Test-Path -LiteralPath $OutputPath) {
    Remove-Item -LiteralPath $OutputPath -Force
}

$candidates = @(
    (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
    (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
)
$csc = @($candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
if ($csc.Count -gt 0) {
    $compileArgs = @(
        "/nologo",
        "/target:winexe",
        "/optimize+",
        "/platform:anycpu",
        "/out:$OutputPath",
        "/win32icon:$iconPath"
    )
    foreach ($reference in $references) {
        $compileArgs += "/reference:$reference"
    }
    $compileArgs += $sourcePath

    & $csc[0] @compileArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Tray compile failed with exit code $LASTEXITCODE"
    }
} else {
    Add-Type `
        -Path $sourcePath `
        -ReferencedAssemblies $references `
        -OutputAssembly $OutputPath `
        -OutputType WindowsApplication
}

[pscustomobject]@{
    status = "ok"
    service = "NomadInbox"
    trayClient = "compiled"
    compiler = if ($csc.Count -gt 0) { $csc[0] } else { "Add-Type" }
    sourcePath = $sourcePath
    outputPath = $OutputPath
    iconPath = $iconPath
    sizeBytes = (Get-Item -LiteralPath $OutputPath).Length
} | ConvertTo-Json -Depth 5
