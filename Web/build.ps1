# Monta o site em Web/public: currículo primeiro, mundo 3D (Godot) para quem quiser explorar.
#   /                 cartão de visita: "Ler o currículo" (sem download) ou "Explorar em 3D" (baixa o Godot)
#   /Pedro-Ferreira-CV.pdf  currículo (Web/cv)
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
# Slides do carregamento: resumos curtos (cabem no cartão), um por ilha.
function Short([string]$text, [int]$max = 150) {
	# Primeira frase inteira, se couber; senão corta na última palavra.
	$dot = $text.IndexOf('. ')
	if ($dot -gt 0 -and $dot -lt $max) { return $text.Substring(0, $dot + 1) }
	if ($text.Length -le $max) { return $text }
	$cut = $text.Substring(0, $max)
	return $cut.Substring(0, $cut.LastIndexOf(" ")) + "…"
}
$slideItems = @("<div class=""slide""><p class=""kicker"">Enquanto o mar carrega</p><h2>Um portfólio para navegar.</h2><p>Uma chalupa, cinco ilhas e o meu currículo espalhado nelas.</p></div>")
foreach ($island in $content.islands) {
	$body = ""
	$entries = @($island.entries | Where-Object { $_ -and $_.title })
	$projects = @($island.projects | Where-Object { $_ -and $_.title })
	if ($entries.Count) {
		$body = "<ul>" + (($entries | Select-Object -First 2 | ForEach-Object { "<li><strong>$(E $_.title)</strong> · $(E $_.org)</li>" }) -join "") + "</ul>"
	} elseif ($projects.Count) {
		$body = "<p>" + (E (($projects | Select-Object -First 3 | ForEach-Object { $_.title }) -join " · ")) + "</p>"
	} elseif (@($island.paragraphs | Where-Object { $_ }).Count) {
		$body = "<p>$(E (Short (@($island.paragraphs | Where-Object { $_ })[0])))</p>"
	}
	$slideItems += "<div class=""slide""><p class=""kicker"">$(E $island.kicker)</p><h2>$(E $island.title)</h2>$body</div>"
}
$html = Get-Content Builds\Web\index.html -Raw -Encoding utf8
$html = $html.Replace("<!--STATUS-->", (E $content.status)).Replace("<!--NAME-->", (E $content.name)).Replace("<!--ROLE-->", (E $content.role))
$html = $html.Replace("<!--TAGLINE-->", (E $content.tagline)).Replace("<!--PITCH-->", (E $content.pitch)).Replace("<!--LINKS-->", $links).Replace("<!--READER-->", ($reader -join "")).Replace("<!--SLIDES-->", ($slideItems -join ""))
Set-Content (Join-Path $public "index.html") $html -Encoding utf8 -NoNewline
Get-ChildItem Builds\Web -File | Where-Object { $_.Name -notin "index.html", "index.pck", "index.wasm" -and $_.Extension -ne ".tmp" } |
	ForEach-Object { Copy-Item $_.FullName $public }
Copy-Item Assets\Fonts\*.ttf, Assets\Fonts\OFL-*.txt (Join-Path $public "fonts")
Copy-Item Web\cv\Pedro-Ferreira-CV.pdf $public

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
