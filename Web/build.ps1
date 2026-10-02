# Monta o site em Web/public: o mundo 3D (Godot) É a página inicial.
#   /                 export Web do Godot com o cartão de visita como tela de carregamento
#   /pck/part-XX      .pck em partes < 25 MiB (o worker.js costura em /index.pck)
#   /index.wasm.br    wasm em brotli (o worker.js entrega como /index.wasm)
#   /music/           trilha tocada pelo navegador (fora do .pck)
# Uso:  pwsh Web/build.ps1            (a partir da raiz do projeto Godot)
param(
	[string]$Godot = "D:\Godot\Godot.exe",
	[int]$PartMB = 20
)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$public = Join-Path $PSScriptRoot "public"
Set-Location $root

Write-Host "1/5 Exportando Godot (Web)"
New-Item -ItemType Directory -Force Builds\Web | Out-Null
& $Godot --headless --path . --export-release "Web" Builds/Web/index.html | Out-Null
if (-not (Test-Path Builds\Web\index.pck)) { throw "Export falhou: Builds/Web/index.pck ausente" }

Write-Host "2/5 Limpando saída anterior"
foreach ($item in Get-ChildItem $public -Force) {
	if ($item.Name -notin "404.html", "fonts") { Remove-Item $item.FullName -Recurse -Force -Confirm:$false }
}
New-Item -ItemType Directory -Force (Join-Path $public "music"), (Join-Path $public "fonts") | Out-Null

Write-Host "3/5 Cartão de visita (conteúdo de Config/portfolio_content.json)"
$content = Get-Content Config\portfolio_content.json -Raw -Encoding utf8 | ConvertFrom-Json
function E([string]$text) { [System.Net.WebUtility]::HtmlEncode($text) }
$links = ($content.links.PSObject.Properties | Where-Object { $_.Name -in "linkedin", "github", "whatsapp" } | ForEach-Object {
	$label = @{ linkedin = "LinkedIn"; github = "GitHub"; whatsapp = "WhatsApp" }[$_.Name]
	"<a href=""$(E $_.Value)"" target=""_blank"" rel=""noopener"">$label ↗</a>"
}) -join ""
$reader = foreach ($island in $content.islands) {
	$parts = @("<p class=""kicker"">$(E $island.kicker)</p><h2>$(E $island.title)</h2>")
	foreach ($p in @($island.paragraphs)) { if ($p) { $parts += "<p>$(E $p)</p>" } }
	foreach ($f in @($island.facts)) { if ($f) { $parts += "<p><span class=""kicker"">$(E $f.label)</span><br><span class=""mono"">$(E $f.value)</span></p>" } }
	foreach ($e in @($island.entries)) { if ($e) { $parts += "<h3>$(E $e.title) · $(E $e.org)</h3><p class=""mono"">$(E $e.period)</p>" + $(if ($e.text) { "<p>$(E $e.text)</p>" } else { "" }) } }
	foreach ($pr in @($island.projects)) { if ($pr) { $parts += "<h3><a href=""$(E $pr.url)"" target=""_blank"" rel=""noopener"">$(E $pr.title) ↗</a></h3><p>$(E $pr.text)</p><p class=""mono"">$(E ($pr.stack -join ' · '))</p>" } }
	"<section id=""reader-$($island.id)"">" + ($parts -join "") + "</section>"
}
$html = Get-Content Builds\Web\index.html -Raw -Encoding utf8
$html = $html.Replace("<!--STATUS-->", (E $content.status)).Replace("<!--NAME-->", (E $content.name)).Replace("<!--ROLE-->", (E $content.role))
$html = $html.Replace("<!--TAGLINE-->", (E $content.tagline)).Replace("<!--PITCH-->", (E $content.pitch)).Replace("<!--LINKS-->", $links).Replace("<!--READER-->", ($reader -join ""))
Set-Content (Join-Path $public "index.html") $html -Encoding utf8 -NoNewline
Get-ChildItem Builds\Web -File | Where-Object { $_.Name -notin "index.html", "index.pck", "index.wasm" -and $_.Extension -ne ".tmp" } |
	ForEach-Object { Copy-Item $_.FullName $public }
Copy-Item Assets\Fonts\*.ttf, Assets\Fonts\OFL-*.txt (Join-Path $public "fonts")

Write-Host "4/5 pck em partes + wasm brotli (desktop e celular)"
function Split-Pack([string]$pckPath, [string]$partsDir, [string]$manifestName) {
	New-Item -ItemType Directory -Force (Join-Path $public $partsDir) | Out-Null
	$bytes = [IO.File]::ReadAllBytes((Resolve-Path $pckPath))
	$names = @()
	for ($offset = 0; $offset -lt $bytes.Length; $offset += $PartMB * 1MB) {
		$name = "part-{0:D2}" -f $names.Count
		$stream = [IO.File]::Create((Join-Path $public "$partsDir\$name"))
		$stream.Write($bytes, $offset, [Math]::Min($PartMB * 1MB, $bytes.Length - $offset))
		$stream.Close()
		$names += $name
	}
	$version = (Get-FileHash $pckPath -Algorithm SHA256).Hash.Substring(0, 16).ToLower()
	@{ parts = $names; size = $bytes.Length; version = $version; dir = $partsDir } | ConvertTo-Json | Set-Content (Join-Path $public $manifestName)
	return $names.Count
}
$parts = 1..(Split-Pack "Builds\Web\index.pck" "pck" "index.pck.parts.json")
pwsh -NoProfile -File (Join-Path $PSScriptRoot "build_mobile.ps1") -Godot $Godot
$mobileParts = Split-Pack "Builds\WebMobile\index.pck" "pck-mobile" "index.mobile.pck.parts.json"
$wasmOut = Join-Path $public "index.wasm.br"
node -e "const z=require('zlib'),f=require('fs');f.writeFileSync(process.argv[2],z.brotliCompressSync(f.readFileSync(process.argv[1]),{params:{[z.constants.BROTLI_PARAM_QUALITY]:11}}))" (Resolve-Path Builds\Web\index.wasm).Path $wasmOut

Write-Host "5/5 Música"
$tracks = (Get-Content Config\music_playlist.json -Raw | ConvertFrom-Json).tracks
foreach ($t in $tracks) { Copy-Item -LiteralPath "Assets\Sound\$t" (Join-Path $public "music\$t") }

$big = Get-ChildItem $public -Recurse -File | Where-Object { $_.Length -gt 25MB }
if ($big) { throw "Arquivos acima de 25 MiB: $($big.FullName -join ', ')" }
$total = (Get-ChildItem $public -Recurse -File | Measure-Object Length -Sum).Sum / 1MB
Write-Host ("Celular: {0:N1} MB em {1} partes" -f ((Get-Item "Builds\WebMobile\index.pck").Length / 1MB), $mobileParts)
Write-Host ("Pronto: {0} partes de pck ({1:N1} MB), wasm.br {2:N1} MB, site total {3:N1} MB" -f $parts.Count, ((Get-Item "Builds\Web\index.pck").Length / 1MB), ((Get-Item $wasmOut).Length / 1MB), $total)
