#!/bin/bash
# APOSENTADO (Pedro, 2026-10-09): PROIBIDO reduzir/decimar/quantizar os GLBs do Meshy (os modelos
# ficavam facetados). O mapa usa os originais de Assets/ (Scripts/WorldDecor.gd, MODELS); animados e
# segmentados saem dos originais por Tools/animate_world_props.py e Tools/split_island_by_parts.py.
# Lista dos modelos do mundo: nome | arquivo do Meshy | triângulos | textura | tamanho (m) | eixo | calado | mapas extras
cd "$(dirname "$0")/.."
BLENDER="${BLENDER:-/d/Blender/blender.exe}"
while IFS='|' read -r name src tris tex size axis draft maps; do
	[ -z "$name" ] && continue
	[ "${name:0:1}" = "#" ] && continue
	in="Assets/$src"
	out="Assets/Optimized/World/$name.glb"
	[ -f "$out" ] && [ "$FORCE" != "1" ] && { echo "skip $name"; continue; }
	"$BLENDER" -b --factory-startup -P "$(cygpath -w "$PWD/Tools/optimize_world_asset.py")" -- "$(cygpath -w "$PWD/$in")" "$(cygpath -w "$PWD/$out")" "$tris" "$tex" "$size" "$axis" "$draft" "$maps" 2>&1 | grep -E "^OPT|Error|Traceback"
done <<'LIST'
sunken_lighthouse|Meshy_AI_half_sunken_lighthous_1008215250_image-to-3d-texture.glb|14000|1024|34|z|0.18
shipwreck_chest|Meshy_AI_shipwreck_with_chest__1008225020_image-to-3d-texture.glb|14000|1024|28|max|0.12
ship_graveyard|Meshy_AI_ship_graveyard_landma_1008233924_image-to-3d-texture.glb|16000|1024|60|max|0.12
turtle_island|Meshy_AI_turtle_island_landmar_1008225032_image-to-3d-texture.glb|16000|1024|60|max|0.22
volcanic_island|Meshy_AI_volcanic_island_landm_1008233915_image-to-3d-texture.glb|16000|1024|80|max|0.1
sea_arch|Meshy_AI_sea_arch_landmark_3d_1008213656_image-to-3d-texture.glb|12000|1024|50|max|0.12
coral_reef|Meshy_AI_colorful_coral_reef_3_1008225112_image-to-3d-texture.glb|8000|1024|18|max|0.55
needle_rocks|Meshy_AI_dark_needle_rocks_3d_1008233853_image-to-3d-texture.glb|6000|1024|24|z|0.15
palm_atoll|Meshy_AI_tropical_palm_atoll_3_1008225101_image-to-3d-texture.glb|8000|1024|30|max|0.15
bell_buoy|Meshy_AI_channel_bell_buoy_3d_1008215810_image-to-3d-texture.glb|6000|1024|4.5|z|0.35
lantern_buoy|Meshy_AI_spectral_lantern_buoy_1008233905_image-to-3d-texture.glb|6000|1024|4.5|z|0.35
cargo_crates|Meshy_AI_floating_cargo_crates_1008220654_image-to-3d-texture.glb|4000|1024|4|max|0.4
# Biomas (2026-10-09): Norte ruínas/runas, Leste megálitos, Sul mar escuro/vulcânico, Oeste recifes.
collapsed_watchtower|Meshy_AI_collapsed_watchtower__1009133619_image-to-3d-texture.glb|16000|1024|34|max|0.1|normal
ruined_sunken_pier|Meshy_AI_ruined_sunken_pier_3d_1009133605_image-to-3d-texture.glb|16000|1024|48|max|0.2|normal
shattered_runed_bastion|Meshy_AI_shattered_runed_basti_1009133629_image-to-3d-texture.glb|18000|1024|46|max|0.1|normal
broken_megalithic_quay|Meshy_AI_broken_megalithic_qua_1009133641_image-to-3d-texture.glb|8000|1024|24|max|0.15|normal
cyclopean_stepped_cairn|Meshy_AI_cyclopean_stepped_cai_1009131201_image-to-3d-texture.glb|12000|1024|40|max|0.1|normal
ocean_stonehenge|Meshy_AI_ocean_stonehenge_tril_1009131238_image-to-3d-texture.glb|16000|1024|44|max|0.1|normal
abandoned_stilt_waterworks|Meshy_AI_abandoned_stilt_water_1009131215_image-to-3d-texture.glb|18000|1024|42|max|0.15|normal
megalithic_dolmen_ring|Meshy_AI_megalithic_dolmen_rin_1009131226_image-to-3d-texture.glb|14000|1024|48|max|0.1|normal
basalt_caldera|Meshy_AI_clean_basalt_caldera__1009134113_image-to-3d-texture.glb|18000|1024|80|max|0.1|normal
obsidian_rib_spire|Meshy_AI_obsidian_rib_spire_3d_1009114307_image-to-3d-texture.glb|12000|1024|40|z|0.08|normal
leviathan_jaw_arch|Meshy_AI_leviathan_jaw_arch_3d_1009114421_image-to-3d-texture.glb|14000|1024|56|max|0.1|normal
floating_basalt_chain|Meshy_AI_floating_basalt_chain_1009114355_image-to-3d-texture.glb|14000|1024|46|max|0.1|normal
spectral_lantern|Meshy_AI_clean_spectral_lanter_1009142211_image-to-3d-texture.glb|5000|1024|5|z|0.3|normal
limestone_coral_needle|Meshy_AI_limestone_coral_needl_1009121510_image-to-3d-texture.glb|12000|1024|32|z|0.1|normal
low_reef_arch|Meshy_AI_low_reef_arch_3d_1009121532_image-to-3d-texture.glb|14000|1024|48|max|0.1|normal
stepped_basalt_reef|Meshy_AI_stepped_basalt_reef_3_1009121521_image-to-3d-texture.glb|12000|1024|36|max|0.12|normal
twin_sea_pinnacles|Meshy_AI_twin_sea_pinnacles_3d_1009121457_image-to-3d-texture.glb|16000|1024|42|z|0.08|normal
LIST
# Modelos segmentados pelo Meshy: corta o GLB otimizado (textura original) nas partes da
# segmentação (Tools/split_island_by_parts.py, sem bake). Pula o que já está em partes.
for pair in "floating_basalt_chain|Meshy_AI_export_1791546246_part-segmentation.glb" "ship_graveyard|Meshy_AI_export_1791502735_part-segmentation.glb"; do
	name="${pair%%|*}"; seg="${pair#*|}"
	out="Assets/Optimized/World/$name.glb"
	grep -q "model_part" "$out" && { echo "skip split $name"; continue; }
	"$BLENDER" -b --factory-startup -P "$(cygpath -w "$PWD/Tools/split_island_by_parts.py")" -- 		"$(cygpath -w "$PWD/Assets/$seg")" "$(cygpath -w "$PWD/$out")" "$(cygpath -w "$PWD/$out.parts.glb")" 2>&1 | grep -E "ISLAND_SPLIT|Error|Traceback"
	[ -f "$out.parts.glb" ] && mv -f "$out.parts.glb" "$out"
done
# Animações "Idle" das boias e caixas (feitas no Blender; pula o que já está animado).
"$BLENDER" -b --factory-startup -P "$(cygpath -w "$PWD/Tools/animate_world_props.py")" -- "$(cygpath -w "$PWD")" 2>&1 | grep -E "^ANIM|Error|Traceback"
