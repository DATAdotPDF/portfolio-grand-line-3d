"""Gera as variantes WEB (desktop e celular) de todo modelo pesado que o jogo carrega.

Os originais ficam intactos como fonte; as cópias leves vão para Assets/WebDesktop/<caminho> e
Assets/WebMobile/<caminho> (pastas com .gdignore: o editor não importa). Os builds do site
(Web/build_variant.ps1) trocam os originais por elas no espelho do projeto.
Uso: python Tools/make_web_variants.py [--force] [nome_parcial ...]   |   --list (modelos usados pelo jogo)
Pula o que já está em dia (variante mais nova que o original).
"""
import glob
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLENDER = os.environ.get("BLENDER", r"D:\Blender\blender.exe")
TOOL = os.path.join(ROOT, "Tools", "make_web_variant.py")
# Abaixo disso o modelo já é leve (títulos, bússola, canhão, chalupa): vai como está.
SKIP_BELOW_MB = 6.0
# (padrão no caminho, triângulos desktop, triângulos celular). O primeiro que casar vale.
BUDGETS = [
	# Pedro achou os modelos do site toscos (2026-10-16): orçamentos maiores, sobretudo no desktop.
	(r"Meshy_AI_island_", 200000, 50000),      # as 5 ilhas do portfólio (o coração do site)
	# Colossos com rig (~110 mil triângulos no original): no desktop ficam inteiros (sem Decimate,
	# que mexe nos pesos); no celular, reduzidos com folga.
	(r"Creatures/(turtle|whale|obsidian|behemoth)", 400000, 60000),
	(r"ghost_ship", 150000, 40000),
	(r"Creatures/maw", 80000, 20000),
	(r"Creatures/tentacle", 120000, 25000),
	(r"Creatures/(dolphin|fin|flyfish)", 40000, 10000),
	(r"Creatures/gull", 25000, 6000),
	# Cidades (vistas de perto, 140 m de lado): o maior orçamento dos marcos.
	(r"(driftwood_mercha|north_runestone|west_coral_paradise|mushroom_grotto)", 300000, 70000),
	# Muitas peças pequenas: com pouco orçamento viravam cacos (folha de comparação) — celular maior.
	(r"cargo_crates", 40000, 20000),
	(r"abandoned_stilt_waterworks", 150000, 50000),
	(r"(bell_buoy|spectral_lantern)", 25000, 8000),
	(r"(coral_reef|palm_atoll|broken_megalithic)", 80000, 20000),
	(r".*", 150000, 35000),                    # marcos dos biomas
]
TOOL_ONLY = {"InspectIslandAxes.gd", "MeasureAssets.gd", "InspectIslandAxes.tscn", "MeasureAssets.tscn"}
LEVELS = {"WebDesktop": (2048, "color_normal", 1), "WebMobile": (1024, "color", 2)}


def referenced_models():
	refs = set()
	files = glob.glob(os.path.join(ROOT, "Scripts", "**", "*.gd"), recursive=True)
	files += [p for p in glob.glob(os.path.join(ROOT, "**", "*.tscn"), recursive=True)
		if not re.search(r"[\\/](Builds|Tests|References|_backup|\.godot)[\\/]", p)]
	for path in files:
		# Ferramentas de medição (cenas fora do export): os modelos delas não vão para o site.
		if os.path.basename(path) in TOOL_ONLY:
			continue
		text = open(path, encoding="utf-8", errors="ignore").read()
		refs.update(re.findall(r'res://(Assets/[^"\']+?\.glb)', text))
		if path.endswith("WorldDecor.gd"):
			refs.update("Assets/" + m for m in re.findall(r'"([^"]+?\.glb)"', text))
	return sorted(r for r in refs if os.path.exists(os.path.join(ROOT, r)))


def budget(rel):
	for pattern, desktop, mobile in BUDGETS:
		if re.search(pattern, rel):
			return desktop, mobile
	return 150000, 35000


def main():
	if "--list" in sys.argv:
		# Para os builds: um caminho por linha (relativo à raiz do projeto).
		for rel in referenced_models():
			print(rel)
		return
	force = "--force" in sys.argv
	only = [a for a in sys.argv[1:] if not a.startswith("--")]
	for level in LEVELS:
		os.makedirs(os.path.join(ROOT, "Assets", level), exist_ok=True)
		open(os.path.join(ROOT, "Assets", level, ".gdignore"), "w").close()
	for rel in referenced_models():
		src = os.path.join(ROOT, rel)
		size_mb = os.path.getsize(src) / 1048576
		if size_mb < SKIP_BELOW_MB or (only and not any(o in rel for o in only)):
			continue
		desktop, mobile = budget(rel)
		for level, (tex, maps, idx) in LEVELS.items():
			tris = desktop if idx == 1 else mobile
			out = os.path.join(ROOT, "Assets", level, rel[len("Assets/"):])
			if not force and os.path.exists(out) and os.path.getmtime(out) > os.path.getmtime(src):
				continue
			os.makedirs(os.path.dirname(out), exist_ok=True)
			r = subprocess.run([BLENDER, "-b", "--factory-startup", "-P", TOOL, "--", src, out, str(tris), str(tex), maps],
				capture_output=True, text=True, errors="ignore")
			line = next((l for l in r.stdout.splitlines() if "WEB_VARIANT" in l), "FAILED " + rel)
			got = os.path.getsize(out) / 1048576 if os.path.exists(out) else 0.0
			print("%-11s %6.1f MB -> %5.1f MB  %s" % (level, size_mb, got, line), flush=True)


if __name__ == "__main__":
	main()
