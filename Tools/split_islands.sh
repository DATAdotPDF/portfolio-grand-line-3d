#!/bin/bash
# Corta as 5 ilhas texturizadas (Assets/Optimized/island_*.glb) nas partes da segmentação do Meshy
# (Tools/split_island_by_parts.py) → Assets/Optimized/Islands/island_<nome>_parts.glb. Sem bake.
cd "$(dirname "$0")/.."
BLENDER="${BLENDER:-/d/Blender/blender.exe}"
mkdir -p Builds/IslandSplit
while IFS='|' read -r name seg; do
	[ -z "$name" ] && continue
	"$BLENDER" -b --factory-startup -P "$(cygpath -w "$PWD/Tools/split_island_by_parts.py")" -- \
		"$(cygpath -w "$PWD/Assets/$seg")" "$(cygpath -w "$PWD/Assets/Optimized/island_$name.glb")" "$(cygpath -w "$PWD/Builds/IslandSplit/island_${name}_parts.glb")" 2>&1 | grep -E "ISLAND_SPLIT|Error|Traceback"
done <<'LIST'
sobre|Meshy_AI_export_1791510731_part-segmentation.glb
experiencia|Meshy_AI_export_1791515145_part-segmentation.glb
formacao|Meshy_AI_export_1791510364_part-segmentation.glb
projetos|Meshy_AI_export_1791510578_part-segmentation.glb
contato|Meshy_AI_export_1791508651_part-segmentation.glb
LIST
echo SPLIT_DONE
