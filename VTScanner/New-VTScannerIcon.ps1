<#
.SYNOPSIS
    Generates the VTScanner application icon (multi-resolution .ico) using GDI+.
.DESCRIPTION
    Draws a heater-shield with a magnifying glass and "VT" letters at 16/32/48/256 px
    and packs them into a single .ico file. Called once by Install-VTScanner.ps1.
#>

Add-Type -AssemblyName System.Drawing

function New-VTScannerIcon {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OutputPath
    )

    $sizes = @(16, 32, 48, 256)
    $pngBlobs = @{}

    foreach ($size in $sizes) {
        $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g   = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.TextRenderingHint  = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

        $pad   = [Math]::Max(1.0, [double]$size * 0.06)
        $left  = [float]$pad
        $top   = [float]$pad
        $sw    = [float]($size - 2 * $pad)
        $sh    = [float]($size - 2 * $pad)
        $right = [float]($left + $sw)
        $bot   = [float]($top  + $sh)
        $cx    = [float]($left + $sw / 2)
        $shoulderY = [float]($top + $sh * 0.55)
        $cornerR   = [float]($sw * 0.15)

        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddArc($left,                  $top, $cornerR * 2, $cornerR * 2, 180, 90)
        $path.AddLine([float]($left + $cornerR), $top, [float]($right - $cornerR), $top)
        $path.AddArc([float]($right - $cornerR * 2), $top, $cornerR * 2, $cornerR * 2, 270, 90)
        $path.AddLine($right, [float]($top + $cornerR), $right, $shoulderY)
        $path.AddBezier(
            $right,                $shoulderY,
            $right,                [float]($bot - $sh * 0.10),
            [float]($cx + $sw * 0.18), $bot,
            $cx,                   $bot)
        $path.AddBezier(
            $cx,                   $bot,
            [float]($cx - $sw * 0.18), $bot,
            $left,                 [float]($bot - $sh * 0.10),
            $left,                 $shoulderY)
        $path.CloseFigure()

        $rect = New-Object System.Drawing.RectangleF($left, $top, $sw, $sh)
        $colorTop = [System.Drawing.Color]::FromArgb(255, 31, 111, 235)
        $colorBot = [System.Drawing.Color]::FromArgb(255, 11,  58, 122)
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            $rect, $colorTop, $colorBot,
            [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
        $g.FillPath($brush, $path)

        $strokeWidth = [Math]::Max(1.0, [double]$size * 0.025)
        $borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, [float]$strokeWidth)
        $borderPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
        $g.DrawPath($borderPen, $path)

        if ($size -ge 32) {
            $lensCx = $cx
            $lensCy = [float]($top + $sh * 0.42)
            $lensR  = [float]($sw * 0.27)

            $magPenWidth = [float]([Math]::Max(2.0, [double]$size * 0.045))
            $magPen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, $magPenWidth)
            $magPen.LineCap = [System.Drawing.Drawing2D.LineCap]::Round

            $g.DrawEllipse($magPen,
                [float]($lensCx - $lensR), [float]($lensCy - $lensR),
                [float]($lensR * 2),       [float]($lensR * 2))

            $hx1 = [float]($lensCx + $lensR * 0.7071)
            $hy1 = [float]($lensCy + $lensR * 0.7071)
            $hx2 = [float]($lensCx + $lensR * 1.65)
            $hy2 = [float]($lensCy + $lensR * 1.65)
            $g.DrawLine($magPen, $hx1, $hy1, $hx2, $hy2)

            $fontSize = [float]($lensR * 0.95)
            $font = New-Object System.Drawing.Font('Segoe UI', $fontSize,
                [System.Drawing.FontStyle]::Bold,
                [System.Drawing.GraphicsUnit]::Pixel)
            $sf = New-Object System.Drawing.StringFormat
            $sf.Alignment     = [System.Drawing.StringAlignment]::Center
            $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
            $textRect = New-Object System.Drawing.RectangleF(
                [float]($lensCx - $lensR), [float]($lensCy - $lensR),
                [float]($lensR * 2),       [float]($lensR * 2))
            $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
            $g.DrawString('VT', $font, $textBrush, $textRect, $sf)

            $font.Dispose(); $sf.Dispose(); $textBrush.Dispose(); $magPen.Dispose()
        } else {
            $fontSize = [float]([double]$size * 0.55)
            $font = New-Object System.Drawing.Font('Segoe UI', $fontSize,
                [System.Drawing.FontStyle]::Bold,
                [System.Drawing.GraphicsUnit]::Pixel)
            $sf = New-Object System.Drawing.StringFormat
            $sf.Alignment     = [System.Drawing.StringAlignment]::Center
            $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
            $textRect = New-Object System.Drawing.RectangleF($left, $top, $sw, [float]($sh * 0.92))
            $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
            $g.DrawString('VT', $font, $textBrush, $textRect, $sf)
            $font.Dispose(); $sf.Dispose(); $textBrush.Dispose()
        }

        $brush.Dispose(); $borderPen.Dispose(); $path.Dispose(); $g.Dispose()

        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngBlobs[$size] = $ms.ToArray()
        $ms.Dispose()
        $bmp.Dispose()
    }

    $outDir = Split-Path -Parent $OutputPath
    if ($outDir -and -not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    $stream = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::Create)
    try {
        $writer = New-Object System.IO.BinaryWriter($stream)
        $writer.Write([UInt16]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]$sizes.Count)

        $headerSize = 6 + 16 * $sizes.Count
        $offset = $headerSize
        foreach ($size in $sizes) {
            $data = $pngBlobs[$size]
            $dim  = if ($size -ge 256) { 0 } else { $size }
            $writer.Write([byte]$dim)
            $writer.Write([byte]$dim)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([UInt16]1)
            $writer.Write([UInt16]32)
            $writer.Write([UInt32]$data.Length)
            $writer.Write([UInt32]$offset)
            $offset += $data.Length
        }
        foreach ($size in $sizes) {
            $writer.Write($pngBlobs[$size])
        }
        $writer.Flush()
    } finally {
        $stream.Dispose()
    }

    Write-Verbose "Wrote icon: $OutputPath"
}
