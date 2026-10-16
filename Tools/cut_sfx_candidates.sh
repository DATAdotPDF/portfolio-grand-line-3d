#!/bin/bash
# Recortes de teste dos SFX baixados pelo Pedro (Assets/Sound/SFX) para Builds/SfxCandidatos/.
# Cada recorte: trecho, mono, 44,1 kHz, fades, pitch (asetrate) quando pedido, pico em -1 dBFS,
# loops com as pontas cruzadas (Blender + numpy). Saída em OGG Vorbis (o que o Godot importa).
# Uso: bash Tools/cut_sfx_candidates.sh   (precisa de ffmpeg no PATH e D:\Blender\blender.exe)
cd "$(dirname "$0")/.."
SRC="Assets/Sound/SFX"
OUT="Builds/SfxCandidatos"
TMP="$OUT/_tmp"
BLENDER="D:/Blender/blender.exe"
LOOPIFY="$(dirname "$0")/loopify_wav.py"
mkdir -p "$OUT" "$TMP"

source "$(dirname "$0")/sfx_cut_lib.sh"

K="$SRC/Kraken"
# --- Kraken --------------------------------------------------------------------------
loop kraken_pressagio_loop      "$K/385818__tec_studio__ominous_horn.wav" 0 11.6 "$(pitch 0.85)" 1.5
loop kraken_pressagio_tensao    "$K/776333__michaelekpoh__tension.wav" 0 13.3 "" 1.5
cut  kraken_aparece_boom        "$K/541600__eminyildirim__cinematic-boom-impact-warning.wav" 0 4.8 "" 0.005 0.5
cut  kraken_tentaculo_a         "$K/376819__original_sound__1-impact-wet.wav" 0 2 "$(pitch 0.7)" 0.005 0.3
cut  kraken_tentaculo_b         "$K/376819__original_sound__1-impact-wet.wav" 0 2 "$(pitch 0.55)" 0.005 0.3
cut  kraken_rugido              "$K/837799__bikkit99__sea-creature-roar.wav" 0.3 10.5 "" 0.05 1.0
cut  kraken_rugido_grave        "$K/837799__bikkit99__sea-creature-roar.wav" 0.3 10.5 "$(pitch 0.8)" 0.05 1.0
cut  kraken_rugido_antigo       "$K/648480__jkerman__ancient-roar-of-death.wav" 52.5 6.5 "" 0.05 1.0
cut  kraken_rugido_eco          "$K/345736__noahpardo__npx-deep-roar-echo-1.wav" 1.3 5.6 "" 0.05 1.0
loop kraken_redemoinho_loop     "$K/567241__badoink__vortex.wav" 0 6.19 "$(pitch 0.75)" 0.6
loop kraken_redemoinho_borbulha "$K/696008__samanthacastleberry__stomach-growls-unstoppable-rumbling-bubbles-hyperactive-tummy-monster-hunger-wild-empty-borborygmi-deep-and-heavy-very-low-blurps-stro.mp3" 20 16 "$(pitch 0.5),lowpass=f=900" 1.5
cut  kraken_barra_carga         "$K/555060__magnuswaker__charge-up.wav" 0 2.18 "" 0.005 0.1
cut  kraken_barra_toque         "$K/555060__magnuswaker__charge-up.wav" 0.6 0.5 "" 0.005 0.15
cut  kraken_riser               "$K/784974__sabacky__riser-gleamer.wav" 0 8.5 "" 0.05 0.3
cut  kraken_arranque_nc         "$K/716972__newlocknew__expldsgn_engine-ignition-burstengine-startnitroflareblast.mp3" 0 3.5 "" 0.005 1.0
cut  kraken_intro_cinematica    "$K/810166__mokasza__awesome-cinematic-intro.mp3" 0 10 "" 0.05 1.0
# Naufrágio: madeira quebrando + rangido grave + bolhas afundando.
ffmpeg -v error -y -i "$K/624150__markdalderup__snapped-wood.wav" -i "$K/618085__sit_walk__2022-02-06-wood-creak-1.wav" -i "$K/17341__halion__water.wav" \
	-filter_complex "[0:a]pan=mono|c0=0.5*c0+0.5*c1,aresample=44100[a];[1:a]pan=mono|c0=0.5*c0+0.5*c1,asetrate=44100*0.6,aresample=44100,adelay=600[b];[2:a]atrim=60:64,asetpts=PTS-STARTPTS,aresample=44100,afade=t=in:d=0.5,afade=t=out:st=3:d=1,adelay=1400[c];[a][b][c]amix=inputs=3:normalize=0" \
	-ar 44100 "$TMP/kraken_naufragio.wav" && peak_to_ogg "$TMP/kraken_naufragio.wav" "$OUT/kraken_naufragio.ogg" && echo "OK kraken_naufragio (mix)"

# --- Navio fantasma e biomas --------------------------------------------------------
G="$SRC/Ghostship"
loop fantasma_navio_loop        "$G/648654__elenalostale__ghost-ship-ambience.wav" 2 22 "" 2.0
cut  fantasma_perseguicao       "$G/367746__univ_lyon3__steczycki_ronan_2016_2017_scream.wav" 0 5.8 "" 0.05 0.8
cut  fantasma_some_whoosh_nc    "$SRC/241146__speedenza__transition-whoosh-5a.wav" 0 2.5 "areverse" 0.3 0.05
loop fantasma_espacial_loop     "$G/55541__noisecollector__spaceghostship.wav" 10 22 "lowpass=f=3000" 2.0
loop bioma_fantasma_aves_nc     "$SRC/688741__philip_goddard__peaceful-sea-at-night-with-the-devil-bird-2.flac" 200 32 "" 2.0
cut  bioma_fantasma_piano_musica "$SRC/Biome Ghost/819108__jcmbo369__theeternallighthouse-a-soft-slow-piano-with-basic-chords-and-rythm-for-my-book-promo-video.m4a" 0 88.5 "" 0.05 3.0
loop vulcao_lava_loop           "$SRC/Biome Volcano/474849__fission9__lava-loop-1.wav" 0 20 "" 0.3
cut  vulcao_erupcao_nc          "$SRC/Biome Volcano/674560__newlocknew__natdvolc_cascading-explosion-during-the-eruptionwith-rumbledesigned_em.wav" 0 14 "" 0.2 3.0

# --- Animais ------------------------------------------------------------------------
cut  golfinho_a_nc              "$SRC/Dolphin/202489__augustsandberg__dolphins.wav" 2 4 "" 0.1 0.4
cut  golfinho_b_nc              "$SRC/Dolphin/202489__augustsandberg__dolphins.wav" 8.5 4 "" 0.1 0.4
cut  golfinho_imitacao          "$SRC/Dolphin/456151__jfournier18__dolphin-noise.wav" 0 2.58 "" 0.01 0.2
cut  baleia_canto               "$SRC/Whale/82325__kevoy__diving-with-whales.wav" 3 10 "" 0.5 1.5
cut  baleia_canto_voz           "$SRC/Whale/171945__rebekahday__lowwhalesong.wav" 5.8 10 "" 0.3 1.5
cut  foca_a_nc                  "$SRC/Seal/347162__vortichez__stormpetrels-weddell-seal-pup-laying-on-the-antarctic-ice-shelf-is-calling-his-mother.wav" 22.8 1.5 "" 0.05 0.3
cut  foca_b_nc                  "$SRC/Seal/347162__vortichez__stormpetrels-weddell-seal-pup-laying-on-the-antarctic-ice-shelf-is-calling-his-mother.wav" 27.5 1.8 "" 0.05 0.3
cut  tubarao_tensao_nc          "$SRC/Shark/13698__acclivity__shark01.wav" 0 5.1 "" 0.1 0.8
cut  tartaruga_respiro          "$SRC/Giant Turtle/427414__mega-x-stream__dinosaur-dragon-growls.wav" 0 4 "$(pitch 0.75),lowpass=f=2500" 0.1 0.8

# --- Mundo --------------------------------------------------------------------------
cut  boia_sino                  "$SRC/804786__designerschoice__belllrg-samsung-galaxy-smartphone-cu_rope-hung-bell-ringing_nicholas-judy_tdc.wav" 0 4.4 "" 0.005 0.5
cut  boia_sino_panela           "$SRC/264850__torror__hit-metal-pan-cover-bell-vibration-deep-2.wav" 0 6 "$(pitch 0.8)" 0.005 1.0
loop costa_ondas_loop           "$SRC/795445__jamgypsy__waves-crashing-on-shore.m4a" 10 24 "" 2.0
loop noite_mar_loop             "$SRC/465435__bonnyorbit__ocean-beach-at-night-with-small-waves.wav" 1 31 "" 2.0
loop fogueira_loop              "$SRC/784223__kvv_audio__foodcook_meat-frying-over-campfire-01_kvv-audio_free.wav" 0 10 "lowpass=f=6000" 1.0
loop chuva_baltico_loop         "$SRC/870414__borgory__thunderstorm-baltic-sea.wav" 0 32 "" 2.0
ffmpeg -v error -y -i "$SRC/872674__heyheytheree__chest-open-fantasy-ui-sfx-free.wav" -i "$SRC/223342__jalastram__2_coins.ogg" \
	-filter_complex "[0:a]aresample=44100[a];[1:a]pan=mono|c0=0.5*c0+0.5*c1,aresample=44100,adelay=450,volume=2.5[b];[a][b]amix=inputs=2:normalize=0" \
	-ar 44100 "$TMP/bau_abrindo_moedas.wav" && peak_to_ogg "$TMP/bau_abrindo_moedas.wav" "$OUT/bau_abrindo_moedas.ogg" && echo "OK bau_abrindo_moedas (mix)"
cut  farol_buzina               "$SRC/371290__mlppeace__foghorn.mp3" 0.15 4.3 "" 0.05 1.0
cut  farol_buzina_longe         "$SRC/371290__mlppeace__foghorn.mp3" 0.15 4.3 "lowpass=f=900,aecho=0.8:0.7:400:0.35" 0.05 1.5
cut  farol_buzina_b             "$SRC/81869__stevebob69__foghorn.wav" 0 10 "" 0.05 1.5
cut  lanterna_acende            "$SRC/637533__kyles__flame-burst-ignite-bbq-barbecue.flac" 0 1.02 "" 0.005 0.2
cut  lanterna_isqueiro          "$SRC/816728__siohfb__lighter.wav" 1.4 1.0 "" 0.005 0.3
cut  cordame_rangido_a          "$K/618083__sit_walk__2022-02-06-wood-creak-3.wav" 0 0.59 "$(pitch 0.8)" 0.01 0.1
cut  cordame_rangido_b          "$K/618084__sit_walk__2022-02-06-wood-creak-2.wav" 0 2.1 "$(pitch 0.8)" 0.01 0.2
cut  cordame_rangido_c          "$K/618085__sit_walk__2022-02-06-wood-creak-1.wav" 0 1.9 "$(pitch 0.8)" 0.01 0.2

# --- Interface, desafio e canhão ------------------------------------------------------
cut  ui_clique_madeira          "$SRC/342200__christopherderp__videogame-menu-button-click.wav" 0 0.14 "" 0.001 0.02
cut  ui_clique_b                "$SRC/629020__kolombooo__button-click.ogg" 0 0.29 "" 0.001 0.03
cut  ui_carta_papel             "$SRC/828026__designerschoice__objbag-samsung-galaxy-smartphone-cu_paper-fold-unfold_nicholas-judy_tdc.wav" 0.9 1.5 "" 0.02 0.3
cut  ui_aviso_pop               "$SRC/540568__eminyildirim__ui-pop-up.wav" 0 0.47 "" 0.001 0.05
cut  ui_aviso_notificacao       "$SRC/616699__melokacool__notification-7.ogg" 0 2.5 "" 0.005 0.3
cut  ilha_descoberta            "$SRC/401179__luizmourabr__achado-2.wav" 0.2 4.5 "" 0.02 1.2
cut  ilha_descoberta_sitar      "$SRC/422548__gsb1039__egyptian-discovery.wav" 0 4.5 "" 0.02 1.0
cut  ovo_pascoa_alerta          "$SRC/277031__headphaze__ui-completed-status-alert-notification-sfx003.wav" 0 2.48 "" 0.005 0.3
cut  ovo_pascoa_blip            "$SRC/531512__cogfirestudios__positive-blip-effect.wav" 0 3 "" 0.005 0.5
cut  sucesso_ux                 "$SRC/634450__sophieciruela__success.wav" 0 2.05 "" 0.005 0.3
cut  desafio_contagem           "$SRC/446130__justinvoke__race-start-countdown.wav" 0 1.35 "" 0.001 0.1
cut  desafio_largada            "$SRC/446142__justinvoke__race-start.wav" 0 1.35 "" 0.001 0.1
cut  desafio_contagem_321go     "$SRC/651010__therandomsoundbyte2637__pre-match-countdown.wav" 0 5.5 "" 0.001 0.2
cut  desafio_ultimos10s         "$SRC/211103__qubodup__time-running-out-buzzer.flac" 0 10.4 "" 0.001 0.05
cut  desafio_tempo_acabou       "$SRC/211103__qubodup__time-running-out-buzzer.flac" 10.4 2.6 "" 0.001 0.6
cut  desafio_tique_nc           "$SRC/243070__timbre__remix-of-167385__ultradust__wood-block-tick-tock-cartoon-clock.wav" 0 0.5 "" 0.001 0.05
cut  desafio_vitoria            "$SRC/677858__el_boss__game-success-fanfare-short.wav" 0 3.38 "" 0.005 0.4
cut  desafio_vitoria_ia         "$SRC/810330__mokasza__triumphant-success.mp3" 0 3.05 "" 0.005 0.4
cut  canhao_sem_municao         "$SRC/869285__signaturesoundsorg__20_ui_game_error_sfx.wav" 0 0.59 "" 0.001 0.1
loop canhao_mira_manivela_loop  "$SRC/517120__wdomino__crank-1.wav" 1 4 "" 0.4
cut  canhao_tiro_b              "$SRC/162455__kastenfrosch__cannonball.mp3" 0 2.77 "" 0.001 0.5
cut  canhao_tiro_corrente       "$SRC/448002__kneeling__cannon.mp3" 0 5.3 "" 0.001 1.0
cut  canhao_impacto             "$SRC/423105__ogsoundfx__guns-explosions-album-cannon-impact-9.wav" 0 1.64 "" 0.001 0.3
cut  explorar_whoosh_nc         "$SRC/241146__speedenza__transition-whoosh-5a.wav" 0 2.5 "" 0.01 0.4
rm -rf "$TMP"
