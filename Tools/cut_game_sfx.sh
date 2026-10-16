#!/bin/bash
# Recortes FINAIS usados no jogo (Assets/Sound/SFX/Cuts/*.ogg), tirados das gravações que o Pedro
# baixou do Freesound. Só licenças CC0 ou CC-BY (créditos em Config/sfx_credits.json).
# Uso: bash Tools/cut_game_sfx.sh   (ffmpeg no PATH, D:\Blender\blender.exe para os loops)
# A tempestade do Báltico (27 min, 316 MB) fica FORA do projeto, em $ORIG.
cd "$(dirname "$0")/.."
SRC="Assets/Sound/SFX"
ORIG="${ORIG:-D:/Godot/SFX_Originais}"
OUT="$SRC/Cuts"
TMP="Builds/_sfx_tmp"
BLENDER="D:/Blender/blender.exe"
LOOPIFY="$(dirname "$0")/loopify_wav.py"
mkdir -p "$OUT" "$TMP"
source "$(dirname "$0")/sfx_cut_lib.sh"

BALTIC="$ORIG/870414__borgory__thunderstorm-baltic-sea.wav"   # CC0
[ -f "$BALTIC" ] || BALTIC="$SRC/870414__borgory__thunderstorm-baltic-sea.wav"
SUMMER="$SRC/237036__supercell10__29_07_2013_thunderstorm.wav" # CC0
NIGHT="$SRC/59028__daveincamas__200806thunderstorm.wav"        # CC-BY 4.0
K="$SRC/Kraken"

# --- Tempestade: chuva e trovões reais ---------------------------------------------------
loop storm_rain_light_loop  "$BALTIC" 0 40 "" 2.0
loop storm_rain_heavy_loop  "$SUMMER" 160 20 "" 2.0
cut  thunder_crack_a        "$NIGHT" 89.4 10 "" 0.01 2.0
cut  thunder_crack_b        "$SUMMER" 45.4 9 "" 0.01 2.0
cut  thunder_near_a         "$BALTIC" 970.9 9 "" 0.02 2.0
cut  thunder_near_b         "$BALTIC" 1103.4 9 "" 0.02 2.0
cut  thunder_near_c         "$SUMMER" 7.9 8 "" 0.02 2.0
cut  thunder_far_a          "$BALTIC" 171.4 8 "lowpass=f=1500" 0.1 2.0
cut  thunder_far_b          "$BALTIC" 501.8 9 "lowpass=f=1500" 0.3 2.0
cut  thunder_far_c          "$BALTIC" 576.0 8 "lowpass=f=1500" 0.1 2.0
# Mar de fundo (ondas pequenas, gravação real) no lugar do ruído gerado no código.
loop ocean_bed_loop         "$SRC/465435__bonnyorbit__ocean-beach-at-night-with-small-waves.wav" 1 31 "lowpass=f=5000" 2.0
# Vento: o "vortex" (CC0) grave vira rajada, rugido do ciclone e a subida do passeio.
cut  storm_gust             "$K/567241__badoink__vortex.wav" 0 4 "$(pitch 0.8)" 0.8 1.5
loop cyclone_roar_loop      "$K/567241__badoink__vortex.wav" 0 6.19 "$(pitch 0.6)" 0.8
cut  cyclone_lift           "$K/555060__magnuswaker__charge-up.wav" 0 2.18 "$(pitch 0.8)" 0.05 0.4
# Alvo de madeira quebrando.
cut  buoy_break             "$K/624150__markdalderup__snapped-wood.wav" 0 1.64 "" 0.001 0.3

# --- Kraken: sons próprios ----------------------------------------------------------------
loop kraken_omen_loop       "$K/385818__tec_studio__ominous_horn.wav" 0 11.6 "$(pitch 0.85)" 1.5
cut  kraken_boom            "$K/541600__eminyildirim__cinematic-boom-impact-warning.wav" 0 4.8 "" 0.005 0.5
cut  kraken_tentacle_a      "$K/376819__original_sound__1-impact-wet.wav" 0 2 "$(pitch 0.7)" 0.005 0.3
cut  kraken_tentacle_b      "$K/376819__original_sound__1-impact-wet.wav" 0 2 "$(pitch 0.55)" 0.005 0.3
cut  kraken_roar            "$K/837799__bikkit99__sea-creature-roar.wav" 0.3 10.5 "$(pitch 0.9)" 0.05 1.0
cut  kraken_roar_retreat    "$K/345736__noahpardo__npx-deep-roar-echo-1.wav" 1.3 5.6 "" 0.05 1.0
loop kraken_whirlpool_loop  "$K/567241__badoink__vortex.wav" 0 6.19 "$(pitch 0.75)" 0.6
loop kraken_bubbles_loop    "$K/696008__samanthacastleberry__stomach-growls-unstoppable-rumbling-bubbles-hyperactive-tummy-monster-hunger-wild-empty-borborygmi-deep-and-heavy-very-low-blurps-stro.mp3" 20 16 "$(pitch 0.5),lowpass=f=900" 1.5
cut  kraken_action_tap      "$K/555060__magnuswaker__charge-up.wav" 0.6 0.5 "" 0.005 0.15
cut  kraken_breakout        "$K/555060__magnuswaker__charge-up.wav" 0 2.18 "" 0.005 0.3
ffmpeg -v error -y -i "$K/624150__markdalderup__snapped-wood.wav" -i "$K/618085__sit_walk__2022-02-06-wood-creak-1.wav" -i "$K/17341__halion__water.wav" \
	-filter_complex "[0:a]pan=mono|c0=0.5*c0+0.5*c1,aresample=44100[a];[1:a]pan=mono|c0=0.5*c0+0.5*c1,asetrate=44100*0.6,aresample=44100,adelay=600[b];[2:a]atrim=60:64,asetpts=PTS-STARTPTS,aresample=44100,afade=t=in:d=0.5,afade=t=out:st=3:d=1,adelay=1400[c];[a][b][c]amix=inputs=3:normalize=0" \
	-ar 44100 "$TMP/kraken_shipwreck.wav" && peak_to_ogg "$TMP/kraken_shipwreck.wav" "$OUT/kraken_shipwreck.ogg" && echo "OK kraken_shipwreck (mix)"
rm -rf "$TMP"
