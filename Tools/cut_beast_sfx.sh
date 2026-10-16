#!/bin/bash
# Sons das bestas do mar (Scripts/SeaBeasts.gd) e da tartaruga, recortados de gravações REAIS do
# Freesound que já estão no projeto e creditadas em Config/sfx_credits.json (CC0, e o impacto molhado CC-BY 3.0).
# Uso: bash Tools/cut_beast_sfx.sh   (ffmpeg no PATH, D:\Blender\blender.exe para os loops)
cd "$(dirname "$0")/.."
SRC="Assets/Sound/SFX"
OUT="$SRC/Cuts"
TMP="Builds/_sfx_beasts_tmp"
BLENDER="D:/Blender/blender.exe"
LOOPIFY="$(dirname "$0")/loopify_wav.py"
mkdir -p "$OUT" "$TMP"
source "$(dirname "$0")/sfx_cut_lib.sh"
K="$SRC/Kraken"

# Água sendo empurrada enquanto o bicho nada/anda (loop, grave).
loop beast_wake_loop   "$K/17341__halion__water.wav" 20 12 "$(pitch 0.75),lowpass=f=2500" 1.5
# Baleia de madeira (Leste): canto grave (buzina distante bem mais grave) e o rangido da madeira.
cut  whale_call        "$K/385818__tec_studio__ominous_horn.wav" 0 8 "$(pitch 0.6),lowpass=f=1500" 0.3 2.0
cut  whale_creak       "$K/618085__sit_walk__2022-02-06-wood-creak-1.wav" 0 0.59 "$(pitch 0.6)" 0.01 0.2
# Baleia: o rabo saindo da água (água escorrendo) e a pancada ao bater de volta (impacto molhado
# grave + água; "1 Impact Wet" é CC-BY 3.0, já creditado).
cut  whale_tail_rise   "$K/17341__halion__water.wav" 60 3 "$(pitch 0.7),lowpass=f=3000" 0.4 1.0
cut  whale_tail_slap   "$K/376819__original_sound__1-impact-wet.wav" 0 2 "$(pitch 0.45),lowpass=f=2500" 0.005 0.6
# Caranguejo do abismo (Sul): rugido grave com eco e o estalo das pinças.
cut  behemoth_roar     "$K/345736__noahpardo__npx-deep-roar-echo-1.wav" 1.3 4.3 "$(pitch 0.75)" 0.05 1.0
cut  behemoth_clack    "$K/624150__markdalderup__snapped-wood.wav" 0 1.64 "$(pitch 0.55)" 0.002 0.3
# Gigante de obsidiana (Sul): rugido e o ronco de pedra raspando.
cut  obsidian_roar     "$K/837799__bikkit99__sea-creature-roar.wav" 0.3 7.7 "$(pitch 0.6),lowpass=f=2000" 0.05 1.5
cut  obsidian_rumble   "$K/696008__samanthacastleberry__stomach-growls-unstoppable-rumbling-bubbles-hyperactive-tummy-monster-hunger-wild-empty-borborygmi-deep-and-heavy-very-low-blurps-stro.mp3" 20 8 "$(pitch 0.4),lowpass=f=400" 0.5 1.5
# Tartaruga (Oeste): chamado grave e longo.
cut  turtle_call       "$K/837799__bikkit99__sea-creature-roar.wav" 0.3 6 "$(pitch 0.45),lowpass=f=1200" 0.2 1.5
rm -rf "$TMP"
