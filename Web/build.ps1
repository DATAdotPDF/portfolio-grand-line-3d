# Monta o site completo em Web/public a partir do projeto Godot.
#   /            landing (index.html, styles.css, landing.js)
#   /world/      export Web do Godot (pck em partes + wasm.br, servidos pelo worker.js)
#   /classico/   site anterior (versão acessível, sem 3D)
# Uso:  pwsh Web/build.ps1            (a partir da raiz do projeto Godot)
param(
	[string]$Godot = "D:\Godot\Godot.exe",
	[string]$ClassicSite = "D:\VSCODE_PROJECTS\AGENT_CLASS\portfolio-pedro",
	[int]$PartMB = 20
)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$public = Join-Path $PSScriptRoot "public"
$world = Join-Path $public "world"
Set-Location $root

Write-Host "1/6 Exportando world_config.json"
& $Godot --headless --path . --script res://Scripts/ExportWorldConfig.gd | Out-Null

Write-Host "2/6 Exportando Godot (Web)"
New-Item -ItemType Directory -Force Builds\Web | Out-Null
& $Godot --headless --path . --export-release "Web" Builds/Web/index.html | Out-Null
if (-not (Test-Path Builds\Web\index.pck)) { throw "Export falhou: Builds/Web/index.pck ausente" }

Write-Host "3/6 Montando /world"
if (Test-Path $world) { Remove-Item $world -Recurse -Force -Confirm:$false }
New-Item -ItemType Directory -Force (Join-Path $world "pck"), (Join-Path $world "music") | Out-Null
Get-ChildItem Builds\Web -File | Where-Object { $_.Name -notin "index.pck", "index.wasm" -and $_.Extension -ne ".tmp" } |
	ForEach-Object { Copy-Item $_.FullName $world }

# .pck em partes < 25 MiB (limite por arquivo do Workers Static Assets)
$pck = [IO.File]::ReadAllBytes((Resolve-Path Builds\Web\index.pck))
$partSize = $PartMB * 1MB
$parts = @()
for ($offset = 0; $offset -lt $pck.Length; $offset += $partSize) {
	$name = "part-{0:D2}" -f $parts.Count
	$length = [Math]::Min($partSize, $pck.Length - $offset)
	$stream = [IO.File]::Create((Join-Path $world "pck\$name"))
	$stream.Write($pck, $offset, $length)
	$stream.Close()
	$parts += $name
}
$version = (Get-FileHash Builds\Web\index.pck -Algorithm SHA256).Hash.Substring(0, 16).ToLower()
@{ parts = $parts; size = $pck.Length; version = $version } | ConvertTo-Json | Set-Content (Join-Path $world "index.pck.parts.json")

# .wasm comprimido em brotli (o worker entrega com Content-Encoding: br)
$wasmIn = (Resolve-Path Builds\Web\index.wasm).Path
$wasmOut = Join-Path $world "index.wasm.br"
node -e "const z=require('zlib'),f=require('fs');f.writeFileSync(process.argv[2],z.brotliCompressSync(f.readFileSync(process.argv[1]),{params:{[z.constants.BROTLI_PARAM_QUALITY]:11}}))" $wasmIn $wasmOut

Write-Host "4/6 Música (fora do .pck, tocada pelo navegador)"
$tracks = (Get-Content Config\music_playlist.json -Raw | ConvertFrom-Json).tracks
foreach ($t in $tracks) { Copy-Item -LiteralPath "Assets\Sound\$t" (Join-Path $world "music\$t") }

Write-Host "5/6 Landing: fontes e dados"
New-Item -ItemType Directory -Force (Join-Path $public "fonts") | Out-Null
Copy-Item Assets\Fonts\*.ttf, Assets\Fonts\OFL-*.txt (Join-Path $public "fonts")
Copy-Item Config\portfolio_content.json $public
Copy-Item Export\world_config.json $public

Write-Host "6/6 Site clássico em /classico"
$classic = Join-Path $public "classico"
if (Test-Path $ClassicSite) {
	if (Test-Path $classic) { Remove-Item $classic -Recurse -Force -Confirm:$false }
	New-Item -ItemType Directory -Force $classic | Out-Null
	Get-ChildItem $ClassicSite -Force | Where-Object { $_.Name -notin ".git", ".gitignore", "README.md" } |
		ForEach-Object { Copy-Item $_.FullName $classic -Recurse }
} else {
	Write-Warning "Site clássico não encontrado em $ClassicSite"
}

$big = Get-ChildItem $public -Recurse -File | Where-Object { $_.Length -gt 25MB }
if ($big) { throw "Arquivos acima de 25 MiB: $($big.FullName -join ', ')" }
$total = (Get-ChildItem $public -Recurse -File | Measure-Object Length -Sum).Sum / 1MB
Write-Host ("Pronto: {0} partes de pck, wasm.br {1:N1} MB, site total {2:N1} MB" -f $parts.Count, ((Get-Item $wasmOut).Length / 1MB), $total)
