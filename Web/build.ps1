# Monta o site em Web/public: currículo primeiro, mundo 3D (Godot) para quem quiser explorar.
#   /                 cartão de visita: "Ler o currículo" (sem download) ou "Explorar em 3D" (baixa o Godot)
#   /Pedro-Ferreira-CV.pdf  currículo (Web/cv)
#   /pck/part-XX      .pck em partes < 25 MiB (o worker.js costura em /index.pck)
#   /packs/, /packs-mobile/  modelos de cada setor (world-<setor>.pck), baixados depois (AssetPacks.gd)
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

Write-Host "1/5 Exportando Godot (Web desktop, com as variantes web dos modelos)"
# Variantes em dia (pula as que já estão) e export a partir delas: os originais não vão para o site.
python -I Tools\make_web_variants.py
pwsh -NoProfile -File (Join-Path $PSScriptRoot "build_variant.ps1") -Profile desktop -Godot $Godot
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
# Leitura sem 3D ("Ler o portfólio aqui mesmo"): uma ficha por ilha, mesma ordem e conteúdo do jogo.
$reader = foreach ($island in $content.islands) {
	$parts = @("<header><p class=""kicker"">$(E $island.kicker)</p><h2>$(E $island.title)</h2></header>")
	foreach ($p in @($island.paragraphs)) { if ($p) { $parts += "<p>$(E $p)</p>" } }
	$facts = @($island.facts | Where-Object { $_ -and $_.label })
	if ($facts.Count) { $parts += "<dl class=""facts"">" + (($facts | ForEach-Object { "<div><dt>$(E $_.label)</dt><dd>$(E $_.value)</dd></div>" }) -join "") + "</dl>" }
	$entries = @($island.entries | Where-Object { $_ -and $_.title })
	if ($entries.Count) { $parts += "<ol class=""timeline"">" + (($entries | ForEach-Object { "<li><span class=""period"">$(E $_.period)</span><h3>$(E $_.title)</h3><p class=""org"">$(E $_.org)</p>" + $(if ($_.text) { "<p>$(E $_.text)</p>" } else { "" }) + "</li>" }) -join "") + "</ol>" }
	$projects = @($island.projects | Where-Object { $_ -and $_.title })
	if ($projects.Count) { $parts += "<div class=""projects"">" + (($projects | ForEach-Object { "<a class=""project"" href=""$(E $_.url)"" target=""_blank"" rel=""noopener""><h3>$(E $_.title) <span>↗</span></h3><p>$(E $_.text)</p><p class=""stack"">$(E ($_.stack -join ' · '))</p></a>" }) -join "") + "</div>" }
	if ($island.id -eq "contato") { $parts += "<nav class=""links"">$links</nav>" }
	"<section class=""sheet"" id=""reader-$($island.id)"">" + ($parts -join "") + "</section>"
}
$html = Get-Content Builds\Web\index.html -Raw -Encoding utf8
$html = $html.Replace("<!--STATUS-->", (E $content.status)).Replace("<!--NAME-->", (E $content.name)).Replace("<!--ROLE-->", (E $content.role))
$html = $html.Replace("<!--TAGLINE-->", (E $content.tagline)).Replace("<!--PITCH-->", (E $content.pitch)).Replace("<!--LINKS-->", $links).Replace("<!--READER-->", ($reader -join "")).Replace("<!--STATS-->", (($content.stats | ForEach-Object { "<div><dt>$(E $_.value)</dt><dd>$(E $_.label)</dd></div>" }) -join ""))
Set-Content (Join-Path $public "index.html") $html -Encoding utf8 -NoNewline
Get-ChildItem Builds\Web -File | Where-Object { $_.Name -notin "index.html", "index.pck", "index.wasm" -and $_.Extension -ne ".tmp" } |
	ForEach-Object { Copy-Item $_.FullName $public }
Copy-Item Assets\Fonts\*.ttf, Assets\Fonts\OFL-*.txt (Join-Path $public "fonts")
Copy-Item Web\cv\Pedro-Ferreira-CV.pdf $public
# Imagens da página (chalupa 2D do carregamento).
Copy-Item Web\assets -Destination (Join-Path $public "assets") -Recurse -Force

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
pwsh -NoProfile -File (Join-Path $PSScriptRoot "build_variant.ps1") -Profile mobile -Godot $Godot
$mobileParts = Split-Pack "Builds\WebMobile\index.pck" "pck-mobile" "index.mobile.pck.parts.json"
# Pacotes dos setores (carregamento por proximidade): o jogo baixa depois que o mundo abre.
Copy-Item Builds\Web\packs -Destination (Join-Path $public "packs") -Recurse -Force
Copy-Item Builds\WebMobile\packs -Destination (Join-Path $public "packs-mobile") -Recurse -Force
# Tamanho no botão "Explorar em 3D": o que baixa antes de abrir (os setores chegam depois).
$sizeNote = "~{0:N0} MB (~{1:N0} MB no celular)" -f ((Get-Item Builds\Web\index.pck).Length / 1MB), ((Get-Item Builds\WebMobile\index.pck).Length / 1MB)
$page = Join-Path $public "index.html"
Set-Content $page ((Get-Content $page -Raw -Encoding utf8).Replace("<!--SIZE3D-->", $sizeNote)) -Encoding utf8 -NoNewline
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
