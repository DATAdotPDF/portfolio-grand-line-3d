#!/bin/bash
# Funções de recorte usadas por cut_sfx_candidates.sh e cut_game_sfx.sh.
# Precisa de: OUT, TMP, BLENDER, LOOPIFY definidos antes do source.

# peak_to_ogg in.wav out.ogg : normaliza o pico para -1 dBFS e grava OGG.
peak_to_ogg() {
	local peak gain
	peak=$(ffmpeg -v info -i "$1" -af volumedetect -f null - 2>&1 | grep max_volume | awk '{print $5}')
	gain=$(awk -v p="$peak" 'BEGIN{print -1.0 - p}')
	ffmpeg -v error -y -i "$1" -af "volume=${gain}dB" -c:a libvorbis -q:a 5 "$2"
}

# cut nome arquivo início duração "filtros extras" fade_in fade_out
cut() {
	local name=$1 src=$2 ss=$3 dur=$4 extra=$5 fi=${6:-0.01} fo=${7:-0.15}
	local chain="pan=mono|c0=0.5*c0+0.5*c1"
	[ "$(ffprobe -v error -show_entries stream=channels -of csv=p=0 "$src" | head -1)" = "1" ] && chain="anull"
	chain="$chain,aresample=44100"
	[ -n "$extra" ] && chain="$chain,$extra"
	chain="$chain,afade=t=in:d=$fi,areverse,afade=t=in:d=$fo,areverse"
	ffmpeg -v error -y -ss "$ss" -t "$dur" -i "$src" -af "$chain" -ar 44100 "$TMP/$name.wav" || { echo "FAIL $name"; return; }
	peak_to_ogg "$TMP/$name.wav" "$OUT/$name.ogg"
	echo "OK $name"
}

# loop nome arquivo início duração "filtros" cruzamento
loop() {
	local name=$1 src=$2 ss=$3 dur=$4 extra=$5 cross=${6:-1.0}
	local chain="pan=mono|c0=0.5*c0+0.5*c1"
	[ "$(ffprobe -v error -show_entries stream=channels -of csv=p=0 "$src" | head -1)" = "1" ] && chain="anull"
	chain="$chain,aresample=44100"
	[ -n "$extra" ] && chain="$chain,$extra"
	ffmpeg -v error -y -ss "$ss" -t "$dur" -i "$src" -af "$chain" -ar 44100 "$TMP/$name.raw.wav" || { echo "FAIL $name"; return; }
	"$BLENDER" -b --factory-startup -P "$LOOPIFY" -- "$TMP/$name.raw.wav" "$TMP/$name.wav" "$cross" 2>&1 | grep -q LOOP || { echo "FAIL loop $name"; return; }
	peak_to_ogg "$TMP/$name.wav" "$OUT/$name.ogg"
	echo "OK $name (loop)"
}

pitch() { echo "asetrate=44100*$1,aresample=44100"; }

