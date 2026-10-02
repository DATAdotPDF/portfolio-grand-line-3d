# Grava o making-of (Tests/making_of.gd) com o Movie Maker do Godot em 1080p,
# gera uma folha de conferência (1 quadro a cada 5 s) e monta o MP4 final com a música.
# Uso: pwsh -File Web\make_making_of.ps1 -FFmpeg <caminho do ffmpeg.exe> [-Option 1|2] [-SkipRecord]
#   Opção 1: Barnacle Reel 1 · Opção 2: Open Sea Quest 2 (roteiros diferentes em Tests/making_of.gd)
param(
	[Parameter(Mandatory = $true)][string]$FFmpeg,
	[string]$Godot = "D:\Godot\Godot.exe",
	[ValidateSet(1, 2)][int]$Option = 1,
	[string]$Music = "",
	[switch]$SkipRecord
)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$out = Join-Path $root "Builds\MakingOf"
New-Item -ItemType Directory -Force $out | Out-Null
if (-not $Music) { $Music = @{ 1 = "Assets\Sound\Barnacle Reel 1.mp3"; 2 = "Assets\Sound\Open Sea Quest 2.mp3" }[$Option] }
$raw = Join-Path $out "raw_opcao$Option.avi"

if (-not $SkipRecord) {
	Write-Host "1/3 gravando (Movie Maker, 1920x1080 @ 30 fps)"
	# override.cfg temporário: o --resolution é ignorado com --script.
	Set-Content (Join-Path $root "override.cfg") "[display]`n`nwindow/size/viewport_width=1920`nwindow/size/viewport_height=1080`nwindow/size/window_width_override=1920`nwindow/size/window_height_override=1080`n`n[editor]`n`nmovie_writer/mjpeg_quality=0.9`n"
	try {
		& $Godot --path $root --write-movie "Builds/MakingOf/raw_opcao$Option.avi" --fixed-fps 30 --script res://Tests/making_of.gd -- "option=$Option" 2>&1 | Select-String "SCRIPT ERROR|frames"
	} finally {
		[IO.File]::Delete((Join-Path $root "override.cfg"))
	}
}

Write-Host "2/3 folha de conferência"
$frames = Join-Path $out "review"
New-Item -ItemType Directory -Force $frames | Out-Null
Get-ChildItem $frames -Filter *.jpg | ForEach-Object { [IO.File]::Delete($_.FullName) }
& $FFmpeg -y -loglevel error -i $raw -vf "fps=1/5,scale=480:270" (Join-Path $frames "f_%02d.jpg")
Add-Type -AssemblyName System.Drawing
$files = @(Get-ChildItem $frames -Filter f_*.jpg | Sort-Object Name | ForEach-Object FullName)
$cols = 5; $cw = 480; $ch = 270; $rows = [Math]::Ceiling($files.Count / $cols)
$bmp = New-Object Drawing.Bitmap ($cols * $cw), ($rows * $ch)
$g = [Drawing.Graphics]::FromImage($bmp)
$font = New-Object Drawing.Font "Arial", 13, ([Drawing.FontStyle]::Bold)
for ($i = 0; $i -lt $files.Count; $i++) {
	$img = [Drawing.Image]::FromFile($files[$i])
	$x = ($i % $cols) * $cw; $y = [Math]::Floor($i / $cols) * $ch
	$g.DrawImage($img, $x, $y, $cw, $ch); $img.Dispose()
	$g.FillRectangle([Drawing.Brushes]::Black, $x, $y, 46, 20)
	$g.DrawString(("{0}s" -f ($i * 5 + 2)), $font, [Drawing.Brushes]::Yellow, $x, $y)
}
$bmp.Save((Join-Path $out "review_opcao$Option.jpg"), [Drawing.Imaging.ImageFormat]::Jpeg); $g.Dispose(); $bmp.Dispose()

Write-Host "3/3 MP4 final (H.264 + música com fade)"
$duration = [double](& $FFmpeg -i $raw 2>&1 | Select-String "Duration: (\d+):(\d+):([\d.]+)" | ForEach-Object { $m = $_.Matches[0].Groups; [int]$m[1].Value * 3600 + [int]$m[2].Value * 60 + [double]$m[3].Value })
$fadeStart = [Math]::Max(0, $duration - 3.5)
# Música + SFX gravados no AVI (o reel toca os efeitos dentro do Godot, em sincronia com os quadros).
$mix = "[1:a]atrim=0:$($duration),afade=t=in:st=0:d=0.8,afade=t=out:st=$($fadeStart):d=3.5,volume=0.78[m];" +
	"[0:a]volume=1.35[s];[m][s]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.95[a]"
& $FFmpeg -y -loglevel error -i $raw -i $Music -filter_complex $mix -map 0:v -map "[a]" `
	-c:v libx264 -preset slow -crf 19 -pix_fmt yuv420p -movflags +faststart -c:a aac -b:a 192k `
	(Join-Path $out "making_of_opcao$Option.mp4")
$mp4 = Get-Item (Join-Path $out "making_of_opcao$Option.mp4")
Write-Host ("Pronto: {0} ({1:N1} MB, {2:N0} s)" -f $mp4.FullName, ($mp4.Length / 1MB), $duration)
