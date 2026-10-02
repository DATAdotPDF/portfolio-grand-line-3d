# Exporta o pacote LEVE de celular (Builds/WebMobile/index.pck).
# Monta um espelho do projeto em Builds/MobileProject com os modelos de
# Assets/OptimizedMobile (menos triângulos, texturas de 512 px) no lugar dos
# de Assets/Optimized, e exporta com a feature "mobile_lite" (ver main_world.gd).
param([string]$Godot = "D:\Godot\Godot.exe")
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$mirror = Join-Path $root "Builds\MobileProject"
Set-Location $root

Write-Host "  mobile 1/4 espelhando o projeto"
New-Item -ItemType Directory -Force $mirror | Out-Null
$excludeDirs = @("Assets", "References", "_backup", "Builds", "Web", "Documentation", "docs", "water-wakes",
	"godot-4-stylized-sky-main", "godot-mcp-main", "godot-water-shader-main", ".git", ".godot", ".claude", "Tests")
robocopy $root $mirror /MIR /XD $excludeDirs /XF "*.tmp" /NFL /NDL /NJH /NJS /NP | Out-Null
foreach ($dir in @("Assets\Fonts", "Assets\Sound\SFX", "Assets\Optimized")) {
	robocopy (Join-Path $root $dir) (Join-Path $mirror $dir) /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
}
Copy-Item "Assets\JollyRoger.png", "Assets\JollyRoger.png.import" (Join-Path $mirror "Assets") -Force
New-Item -ItemType File -Force (Join-Path $mirror "Builds\.gdignore") | Out-Null

Write-Host "  mobile 2/4 trocando modelos pelos leves"
$optimized = Join-Path $mirror "Assets\Optimized"
foreach ($glb in Get-ChildItem "Assets\OptimizedMobile" -Filter *.glb) {
	$base = $glb.BaseName
	# Texturas extraídas da versão desktop saem: o Godot extrai as novas (menores) no import.
	Get-ChildItem $optimized -Filter "$($base)_*.jpg*" | Remove-Item -Force -Confirm:$false
	Copy-Item $glb.FullName (Join-Path $optimized $glb.Name) -Force
	# O cache .godot do espelho sobrevive entre builds: sem apagar o md5 o Godot acha que o
	# GLB já foi importado e não extrai as texturas de novo (modelos saíam brancos).
	Get-ChildItem (Join-Path $mirror ".godot\imported") -Filter "$($base).glb-*" -ErrorAction SilentlyContinue | Remove-Item -Force -Confirm:$false
}

Write-Host "  mobile 3/4 importando (texturas em Basis Universal)"
& $Godot --headless --path $mirror --import 2>&1 | Out-Null
foreach ($glb in Get-ChildItem "Assets\OptimizedMobile" -Filter *.glb) {
	if (-not (Get-ChildItem $optimized -Filter "$($glb.BaseName)_*.jpg")) { throw "Texturas de $($glb.BaseName) não foram extraídas" }
}
foreach ($imp in Get-ChildItem $optimized -Filter *.jpg.import) {
	$text = Get-Content $imp.FullName -Raw
	$text = $text -replace 'compress/mode=\d', 'compress/mode=4' -replace 'process/size_limit=\d+', 'process/size_limit=512'
	if ($imp.Name -match '_[12]\.jpg\.import$') { $text = $text -replace 'process/size_limit=\d+', 'process/size_limit=256' }
	Set-Content $imp.FullName $text -NoNewline
}
& $Godot --headless --path $mirror --import 2>&1 | Out-Null

Write-Host "  mobile 4/4 exportando"
$presets = Join-Path $mirror "export_presets.cfg"
(Get-Content $presets -Raw).Replace('custom_features=""', 'custom_features="mobile_lite"') | Set-Content $presets -NoNewline
New-Item -ItemType Directory -Force "Builds\WebMobile" | Out-Null
& $Godot --headless --path $mirror --export-release "Web" (Join-Path $root "Builds\WebMobile\index.html") 2>&1 | Out-Null
if (-not (Test-Path "Builds\WebMobile\index.pck")) { throw "Export mobile falhou" }
Write-Host ("  mobile pck: {0:N1} MB" -f ((Get-Item "Builds\WebMobile\index.pck").Length / 1MB))
