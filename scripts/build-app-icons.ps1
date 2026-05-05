param(
    [string]$AssetsDir = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($AssetsDir)) {
    $AssetsDir = Join-Path $repoRoot "assets"
}

New-Item -ItemType Directory -Force -Path $AssetsDir | Out-Null

Add-Type -AssemblyName System.Drawing

function New-NomadInboxBitmap {
    param([int]$Size)

    $bitmap = New-Object System.Drawing.Bitmap $Size, $Size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $scale = $Size / 256.0

    function S([float]$Value) { return [int][Math]::Round($Value * $scale) }
    function Rect([float]$X, [float]$Y, [float]$W, [float]$H) {
        return New-Object System.Drawing.Rectangle (S $X), (S $Y), (S $W), (S $H)
    }

    $bgRect = Rect 12 12 232 232
    $bgPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $radius = S 52
    $diameter = $radius * 2
    $bgPath.AddArc($bgRect.X, $bgRect.Y, $diameter, $diameter, 180, 90)
    $bgPath.AddArc($bgRect.Right - $diameter, $bgRect.Y, $diameter, $diameter, 270, 90)
    $bgPath.AddArc($bgRect.Right - $diameter, $bgRect.Bottom - $diameter, $diameter, $diameter, 0, 90)
    $bgPath.AddArc($bgRect.X, $bgRect.Bottom - $diameter, $diameter, $diameter, 90, 90)
    $bgPath.CloseFigure()

    $bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $bgRect, ([System.Drawing.Color]::FromArgb(21, 94, 117)), ([System.Drawing.Color]::FromArgb(17, 24, 39)), 45
    $graphics.FillPath($bgBrush, $bgPath)

    $mailRect = Rect 50 76 156 106
    $mailPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $mailRadius = S 20
    $mailDiameter = $mailRadius * 2
    $mailPath.AddArc($mailRect.X, $mailRect.Y, $mailDiameter, $mailDiameter, 180, 90)
    $mailPath.AddArc($mailRect.Right - $mailDiameter, $mailRect.Y, $mailDiameter, $mailDiameter, 270, 90)
    $mailPath.AddArc($mailRect.Right - $mailDiameter, $mailRect.Bottom - $mailDiameter, $mailDiameter, $mailDiameter, 0, 90)
    $mailPath.AddArc($mailRect.X, $mailRect.Bottom - $mailDiameter, $mailDiameter, $mailDiameter, 90, 90)
    $mailPath.CloseFigure()
    $graphics.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(248, 250, 252))), $mailPath)

    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(15, 118, 110)), (S 12)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $graphics.DrawLines($pen, @(
        (New-Object System.Drawing.Point (S 62), (S 92)),
        (New-Object System.Drawing.Point (S 118), (S 136)),
        (New-Object System.Drawing.Point (S 138), (S 136)),
        (New-Object System.Drawing.Point (S 194), (S 92))
    ))

    $routePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(245, 158, 11)), (S 10)
    $routePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $routePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $routePen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dot
    $graphics.DrawArc($routePen, (Rect 80 134 96 68), 20, 140)

    $dotBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(245, 158, 11))
    $graphics.FillEllipse($dotBrush, (Rect 164 157 36 36))
    $graphics.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(17, 24, 39))), (Rect 177 170 10 10))

    $graphics.Dispose()
    return $bitmap
}

$sizes = @(16, 24, 32, 48, 64, 128, 256)
$pngPaths = @()
foreach ($size in $sizes) {
    $bitmap = New-NomadInboxBitmap -Size $size
    $path = Join-Path $AssetsDir ("nomadinbox-tray-{0}.png" -f $size)
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    $pngPaths += $path
}

$icoPath = Join-Path $AssetsDir "nomadinbox-tray.ico"
$stream = [System.IO.File]::Open($icoPath, [System.IO.FileMode]::Create)
try {
    $writer = New-Object System.IO.BinaryWriter $stream
    $writer.Write([UInt16]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]$pngPaths.Count)

    $entries = @()
    $offset = 6 + (16 * $pngPaths.Count)
    foreach ($path in $pngPaths) {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $size = [int](([System.IO.Path]::GetFileNameWithoutExtension($path) -split "-")[-1])
        $entrySize = if ($size -eq 256) { 0 } else { $size }
        $writer.Write([byte]$entrySize)
        $writer.Write([byte]$entrySize)
        $writer.Write([byte]0)
        $writer.Write([byte]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]32)
        $writer.Write([UInt32]$bytes.Length)
        $writer.Write([UInt32]$offset)
        $entries += ,$bytes
        $offset += $bytes.Length
    }

    foreach ($bytes in $entries) {
        $writer.Write($bytes)
    }
}
finally {
    if ($writer) { $writer.Dispose() }
    $stream.Dispose()
}

[pscustomobject]@{
    status = "ok"
    assetsDir = $AssetsDir
    icon = $icoPath
    png = $pngPaths
} | ConvertTo-Json -Depth 5
