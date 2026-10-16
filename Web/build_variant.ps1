# Exporta um pacote do site a partir das VARIANTES WEB dos modelos (Tools/make_web_variants.py).
#   -Profile desktop  -> Builds/Web/index.pck        (modelos de Assets/WebDesktop, texturas VRAM S3TC)
#   -Profile mobile   -> Builds/WebMobile/index.pck  (modelos de Assets/WebMobile, Basis Universal, feature "mobile_lite")
# Monta um espelho do projeto em Builds/WebProject-<perfil>: tudo menos os GLBs pesados; cada modelo
# que o jogo usa entra pela variante do perfil (mesmo caminho e mesmo .import do original, então as
# cenas e os scripts continuam achando tudo). Os originais nunca vão para o site.
param(
	[ValidateSet("desktop", "mobile")][string]$Profile = "desktop",
	[string]$Godot = "D:\Godot\Godot.exe"
)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$mirror = Join-Path $root "Builds\WebProject-$Profile"
$variants = Join-Path $root ("Assets\" + $(if ($Profile -eq "desktop") { "WebDesktop" } else { "WebMobile" }))
$outDir = Join-Path $root $(if ($Profile -eq "desktop") { "Builds\Web" } else { "Builds\WebMobile" })

Write-Host "  [$Profile] 0/5 medindo a decoração (Config/world_kinds.json, para os pacotes dos setores)"
& $Godot --headless --path $root --script res://Tests/bake_world_kinds.gd 2>&1 | Select-String "^BAKE" | ForEach-Object { Write-Host "  [$Profile]     $_" }

Write-Host "  [$Profile] 1/5 espelhando o projeto (sem os modelos pesados)"
New-Item -ItemType Directory -Force $mirror | Out-Null
$excludeDirs = @("Assets", "References", "_backup", "Builds", "Web", "Documentation", "docs", "godot-mcp-main",
	".git", ".godot", ".claude", "Tests", "Tools")
robocopy $root $mirror /MIR /XD $excludeDirs /XF "*.tmp" /NFL /NDL /NJH /NJS /NP | Out-Null
# Assets sem GLB e sem as texturas extraídas dos GLBs (a variante extrai as dela no import).
robocopy (Join-Path $root "Assets") (Join-Path $mirror "Assets") /MIR `
	/XD (Join-Path $root "Assets\WebDesktop") (Join-Path $root "Assets\WebMobile") `
	/XF "*.tmp" "*.blend" "*.blend1" "(PROPOSAL)*" "*.glb" "*.glb.import" "*_Image_*.jpg" "*_Image_*.jpg.import" "*image-to-3d-texture*.jpg" "*image-to-3d-texture*.jpg.import" "*concept*.png" "*concept*.png.import" `
	/NFL /NDL /NJH /NJS /NP | Out-Null
New-Item -ItemType File -Force (Join-Path $mirror "Builds\.gdignore") | Out-Null
# O export leva todo recurso do espelho: tira o que o jogo não usa. Gravações brutas de SFX (só os
# cortes e os arquivos citados nos scripts entram) e as texturas 4K soltas extraídas dos GLBs
# originais (a variante extrai as dela no import).
$sources = (Get-ChildItem Scripts, Scenes, Shaders, Config -Recurse -File -Include *.gd, *.tscn, *.tres, *.gdshader, *.json -ErrorAction SilentlyContinue |
	ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
$sources += (Get-ChildItem $root -File -Filter *.tscn | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
$pruned = 0
$sfx = Join-Path $mirror "Assets\Sound\SFX"
foreach ($file in Get-ChildItem $sfx -Recurse -File -Include *.wav, *.flac, *.mp3, *.ogg -ErrorAction SilentlyContinue) {
	$rel = $file.FullName.Substring($sfx.Length + 1).Replace("\", "/")
	if ($rel -match '^(Cuts|Generated)/' -or $sources.Contains($rel)) { continue }
	Remove-Item -LiteralPath $file.FullName -Force; Remove-Item -LiteralPath "$($file.FullName).import" -Force -ErrorAction SilentlyContinue
	$pruned++
}
# Texturas extraídas de um GLB (nome "<glb>_..."): o import do espelho extrai de novo as que o modelo
# usa (da variante ou do original); as que sobram (de GLB fora do site ou de uma extração antiga com
# outro nome) iam no pacote sem uso.
foreach ($file in Get-ChildItem (Join-Path $mirror "Assets") -Recurse -File -Include *.jpg, *.jpeg, *.png) {
	$srcDir = Join-Path $root $file.DirectoryName.Substring($mirror.Length + 1)
	$owner = Get-ChildItem $srcDir -File -Filter *.glb -ErrorAction SilentlyContinue |
		Where-Object { $file.Name.StartsWith([IO.Path]::GetFileNameWithoutExtension($_.Name) + "_") } | Select-Object -First 1
	if (-not $owner -or $sources.Contains($file.Name)) { continue }
	Remove-Item -LiteralPath $file.FullName -Force; Remove-Item -LiteralPath "$($file.FullName).import" -Force -ErrorAction SilentlyContinue
	$pruned++
}
foreach ($file in Get-ChildItem (Join-Path $mirror "Assets") -Recurse -File -Include *_texture_0.png, *_normal.png, *_metallic*.png, *_roughness*.png, *_emissive*.png) {
	if ($sources.Contains($file.Name)) { continue }
	Remove-Item -LiteralPath $file.FullName -Force; Remove-Item -LiteralPath "$($file.FullName).import" -Force -ErrorAction SilentlyContinue
	$pruned++
}
# Música: na web o navegador toca de /music (Web/build.ps1); nenhuma faixa vai no pacote. E restos
# (*.tmp) que um build antigo deixou no espelho (o robocopy /XF não apaga do destino).
foreach ($file in @(Get-ChildItem (Join-Path $mirror "Assets\Sound\*") -File -Include *.mp3, *.ogg, *.wav -ErrorAction SilentlyContinue) +
		@(Get-ChildItem (Join-Path $mirror "Assets") -Recurse -File -Filter *.tmp)) {
	Remove-Item -LiteralPath $file.FullName -Force; Remove-Item -LiteralPath "$($file.FullName).import" -Force -ErrorAction SilentlyContinue
	$pruned++
}
Write-Host "  [$Profile]     $pruned arquivos sem uso fora do pacote"

Write-Host "  [$Profile] 2/5 modelos: variante do perfil (ou o original, se já for leve)"
$models = python -I Tools\make_web_variants.py --list
$swapped = 0
# GLB que ficou de um build anterior e o jogo não usa mais (o robocopy /XF não apaga do destino).
$keep = @{}; foreach ($rel in $models) { $keep[(Join-Path $mirror $rel).ToLower()] = $true }
foreach ($glb in Get-ChildItem (Join-Path $mirror "Assets") -Recurse -File -Filter *.glb) {
	if ($keep.ContainsKey($glb.FullName.ToLower())) { continue }
	Remove-Item -LiteralPath $glb.FullName -Force; Remove-Item -LiteralPath "$($glb.FullName).import" -Force -ErrorAction SilentlyContinue
	$base = [IO.Path]::GetFileNameWithoutExtension($glb.Name)
	# Texturas extraídas dele (sem pegar as de um GLB mantido de nome mais longo: island_x_parts).
	$longer = @($models | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) } | Where-Object { $_ -ne $base -and $_.StartsWith("$($base)_") })
	Get-ChildItem $glb.DirectoryName -File | Where-Object { $n = $_.Name; $n.StartsWith("$($base)_") -and $_.Extension -in ".jpg", ".png", ".import" -and
		-not ($longer | Where-Object { $n.StartsWith("$($_)_") }) } | Remove-Item -Force -Confirm:$false
}
foreach ($rel in $models) {
	$src = Join-Path $root $rel
	$sub = $rel.Substring("Assets/".Length)
	$variant = Join-Path $variants $sub
	$dest = Join-Path $mirror $rel
	New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
	if (Test-Path $variant) { Copy-Item $variant $dest -Force; $swapped++ } else { Copy-Item $src $dest -Force }
	if (Test-Path "$src.import") { Copy-Item "$src.import" "$dest.import" -Force }
	# Sem isso o cache do espelho acha que o GLB já foi importado e não extrai as texturas novas.
	$base = [IO.Path]::GetFileName($rel)
	Get-ChildItem (Join-Path $mirror ".godot\imported") -Filter "$base-*" -ErrorAction SilentlyContinue | Remove-Item -Force -Confirm:$false
}
Write-Host ("  [$Profile]     {0} modelos, {1} trocados pela variante" -f @($models).Count, $swapped)

Write-Host "  [$Profile] 3/5 importando"
& $Godot --headless --path $mirror --import 2>&1 | Out-Null
# Texturas: desktop em VRAM (S3TC/BPTC); celular em Basis Universal (vale para qualquer GPU), menores.
$mode = if ($Profile -eq "desktop") { 2 } else { 4 }
foreach ($imp in Get-ChildItem (Join-Path $mirror "Assets") -Recurse -Include *.jpg.import, *.png.import) {
	$text = Get-Content $imp.FullName -Raw
	if ($text -notmatch 'compress/mode=') { continue }
	$new = $text -replace 'compress/mode=\d', "compress/mode=$mode"
	# Texturas dos modelos (nome "<glb>_..."). Desktop: tudo 2048 (Pedro achou os modelos toscos com 1024, 2026-10-16). Celular: 1024 nas
	# ilhas, placas, cidades e colossos, 512 no resto (mapas além da cor — normal, rugosidade —
	# sempre 512). Céu, nuvens e efeitos: desktop como estão, celular 1024. As placas têm o título
	# pintado na textura: ficam no tamanho cheio.
	$texName = $imp.Name.Substring(0, $imp.Name.Length - ".import".Length)
	$isModel = [bool](Get-ChildItem $imp.DirectoryName -File -Filter *.glb |
		Where-Object { $texName.StartsWith([IO.Path]::GetFileNameWithoutExtension($_.Name) + "_") } | Select-Object -First 1)
	$full = if ($Profile -eq "desktop") { 2048 } else { 1024 }
	$limit = if (-not $isModel) { $(if ($Profile -eq "mobile") { 1024 } else { 0 }) }
		elseif ($Profile -eq "desktop") { $full }
		elseif ($texName -match '(?i)island_|chalupe|sloop|gear5|title_|driftwood_mercha|north_runestone|west_coral_paradise|mushroom_grotto|whale|turtle|obsidian|behemoth' -and $texName -match '_(Image_)?(texture_)?0\.') { $full }
		else { $full / 2 }
	$new = $new -replace 'process/size_limit=\d+', "process/size_limit=$limit"
	if ($new -ne $text) { Set-Content $imp.FullName $new -NoNewline }
}
& $Godot --headless --path $mirror --import 2>&1 | Out-Null

Write-Host "  [$Profile] 4/5 preset de exportação"
$presets = Join-Path $mirror "export_presets.cfg"
$cfg = Get-Content $presets -Raw
# No espelho só está o que o jogo usa: os modelos do Meshy e das ilhas entram (antes eram excluídos).
$cfg = $cfg.Replace("Assets/Optimized/island_*,", "").Replace("Assets/Meshy_AI_*,", "")
if ($Profile -eq "mobile") { $cfg = $cfg.Replace('custom_features=""', 'custom_features="mobile_lite"') }

# Pacotes dos setores (carregamento por proximidade, Scripts/AssetPacks.gd): os modelos de cada setor
# vão para world-<setor>.pck e saem do pacote principal; o jogo baixa depois que o mundo abre.
$packDir = Join-Path $outDir "packs"
Remove-Item $packDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $packDir | Out-Null
$kinds = (Get-Content (Join-Path $mirror "Config\world_kinds.json") -Raw | ConvertFrom-Json).kinds
$packs = [ordered]@{}
foreach ($k in $kinds.PSObject.Properties) {
	if (-not $k.Value.pack) { continue }
	if (-not $packs.Contains($k.Value.pack)) { $packs[$k.Value.pack] = @() }
	$packs[$k.Value.pack] += $k.Value.path
}
$options = [regex]::Match($cfg, '(?s)\[preset\.0\.options\](.*?)(?=\n\[preset\.|\z)').Groups[1].Value
$excluded = @()
$index = 1
foreach ($pack in $packs.Keys) {
	$files = ($packs[$pack] | ForEach-Object { '"' + $_ + '"' }) -join ", "
	$cfg += "`n[preset.$index]`n`nname=""Pack-$pack""`nplatform=""Web""`nrunnable=false`nadvanced_options=false`ndedicated_server=false`ncustom_features=""""`nexport_filter=""resources""`nexport_files=PackedStringArray($files)`ninclude_filter=""""`nexclude_filter=""""`nexport_path=""""`npatches=PackedStringArray()`nencryption_include_filters=""""`nencryption_exclude_filters=""""`nseed=0`nencrypt_pck=false`nencrypt_directory=false`nscript_export_mode=2`n`n[preset.$index.options]$options"
	foreach ($res in $packs[$pack]) {
		$rel = $res.Substring("res://".Length)
		$excluded += $rel, ($rel.Substring(0, $rel.Length - 4) + "_*")
	}
	$index++
}
Set-Content $presets $cfg -NoNewline
$manifest = [ordered]@{ dir = $(if ($Profile -eq "desktop") { "packs" } else { "packs-mobile" }); packs = [ordered]@{} }
foreach ($pack in $packs.Keys) {
	$file = "world-$pack.pck"
	& $Godot --headless --path $mirror --export-pack "Pack-$pack" (Join-Path $packDir $file) 2>&1 | Out-Null
	$path = Join-Path $packDir $file
	if (-not (Test-Path $path)) { throw "Pacote $pack falhou" }
	# Pacote vazio = os modelos não foram importados no espelho (já aconteceu com um .blend solto em
	# Assets travando o import): para aqui em vez de publicar um mundo sem os setores.
	if ((Get-Item $path).Length -lt 1MB) { throw "Pacote $pack vazio ($((Get-Item $path).Length) bytes): import do espelho falhou" }
	$entry = [ordered]@{ file = $file; size = (Get-Item $path).Length
		version = (Get-FileHash $path -Algorithm SHA256).Hash.Substring(0, 12).ToLower() }
	# Acima de 20 MiB: em partes (o Cloudflare aceita até 25 MiB por arquivo); o jogo junta no navegador.
	# O inteiro vai para packs-full (teste fora do navegador: --packs=<build>/packs-full).
	$full = Join-Path $outDir "packs-full"
	New-Item -ItemType Directory -Force $full | Out-Null
	if ($entry.size -gt 20MB) {
		$bytes = [IO.File]::ReadAllBytes($path)
		$parts = @()
		for ($offset = 0; $offset -lt $bytes.Length; $offset += 20MB) {
			$name = "{0}.part-{1:D2}" -f $file, $parts.Count
			$stream = [IO.File]::Create((Join-Path $packDir $name))
			$stream.Write($bytes, $offset, [Math]::Min(20MB, $bytes.Length - $offset))
			$stream.Close()
			$parts += $name
		}
		$entry.parts = $parts
		Move-Item $path (Join-Path $full $file) -Force
	} else {
		Copy-Item $path (Join-Path $full $file) -Force
	}
	$manifest.packs[$pack] = $entry
	Write-Host ("  [$Profile]     {0}: {1} modelos, {2:N1} MB{3}" -f $file, @($packs[$pack]).Count, ($entry.size / 1MB), $(if ($entry.parts) { " em $($entry.parts.Count) partes" } else { "" }))
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $mirror "Config\world_packs.json") -Encoding utf8
# Manifesto das texturas originais deste perfil (Web/build.ps1 gera em Builds/HD).
$hd = Join-Path $root ("Builds\HD\hd_" + $Profile + ".json")
if (Test-Path $hd) { Copy-Item $hd (Join-Path $mirror "Config\hd_textures.json") -Force }
# O principal fica sem os modelos dos pacotes (e sem as texturas extraídas deles).
$cfg = $cfg -replace '(\[preset\.0\][^\[]*?exclude_filter=")', ('$1' + (($excluded -join ",") -replace '\$', '$$$$') + ",")
Set-Content $presets $cfg -NoNewline

Write-Host "  [$Profile] 5/5 exportando"
New-Item -ItemType Directory -Force $outDir | Out-Null
& $Godot --headless --path $mirror --export-release "Web" (Join-Path $outDir "index.html") 2>&1 | Out-Null
if (-not (Test-Path (Join-Path $outDir "index.pck"))) { throw "Export $Profile falhou" }
Write-Host ("  [$Profile] pck: {0:N1} MB" -f ((Get-Item (Join-Path $outDir "index.pck")).Length / 1MB))
