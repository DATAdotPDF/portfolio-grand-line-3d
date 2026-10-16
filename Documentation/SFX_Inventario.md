# Inventário de SFX (2026-10-09)

Lista do que já existe e do que falta para cobrir todo o jogo. Pasta sugerida para os novos:
`Assets/Sound/SFX/Manual/` (WAV 44,1 kHz ou OGG; loops com as pontas emendadas, sem silêncio
no início dos one-shots). Basta trocar o `preload` correspondente quando o arquivo chegar.

Legenda: **L** = loop · **1x** = one-shot · **3D** = posicional no mundo · **2D** = sem posição.

---

## 1. O que já temos (em uso)

### Arquivos de terceiros (origem/licença a confirmar)
| Arquivo | Onde toca |
|---|---|
| `SFX/CANNON SHOT SFX.wav` | Tiro do canhão do barco (Scenes/DeckCannon.tscn) |
| `SFX/FUSE SFX.wav` | Pavio do canhão (DeckCannon.tscn) |
| `SFX/CANON BALL DOPPLER SFX.wav` | Bala passando (NavalGame) |
| `SFX/EXPLOSION SFX.wav` | Bala acertando rocha/ilha (NavalGame) |
| `SFX/WATER SPLASH CANON BALL SFX.wav` | Bala caindo na água (NavalGame) |
| `SFX/WOOD IMPACT CANON BALL SFX.wav` | Baque no alvo (HitSoundManager) |
| `SFX/hitmarker_bell.wav` | Sininho de acerto (HitSoundManager) |
| `SFX/SEAGULLS OPEN SEA SFX 1.mp3` | Gaivotas (SeaAmbience, Seagulls) |

### Sintetizados por nós (Tools/make_sfx.py → `SFX/Generated/`)
| Arquivo | Tipo | Onde toca |
|---|---|---|
| `rain_light_loop` / `rain_heavy_loop` | L 2D | Chuva da tempestade |
| `wind_storm_loop` | L 2D | Vento uivando na tempestade |
| `storm_sea_loop` | L 2D | Mar grosso da tempestade |
| `wind_gust` | 1x 2D | Rajada na tempestade (Weather) |
| `thunder_crack` / `thunder_near` / `thunder_far` | 1x 2D | Trovões (Thunder) |
| `buoy_break` | 1x 3D | Alvo de madeira quebrando |
| `cyclone_loop` | L 3D | Rugido do ciclone (Cyclone) |
| `teleport_whoosh` | 1x 2D | Subida/teleporte do ciclone (CycloneRide) |
| `whale_blow` | 1x 3D | Borrifo da baleia (SeaLife, SeaShadows) |
| — (gerado no código) | L 2D | Fundo de mar `_make_ocean_bed` (SeaAmbience) |
| — (gerado no código) | 1x 3D | Canhões do forte `_cannon_sound`, trinado do caracol `_telephone_trill` (IslandEffects) |

### Sem uso hoje (podem ser apagados ou aproveitados)
`SFX/cannon.wav`, `fuse.wav`, `hit_thud.wav`, `splash.wav`, `wood_break.wav` (cannon.wav só no Tests/making_of.gd),
`SFX/OCEAN AND SEAGULLS SFX.mp3`, `SFX/WOODEN BOAT OPEN SEA SFX.mp3`, `SFX/OCEAN WAVE CRASH SFX.mp3`
(os dois últimos tirados do barco a pedido do Pedro). Já gerados mas não integrados: `dolphin_splash`, `fish_plop` (em Builds/SfxPreview).

---

## 2. O que falta

### Barco (tirados do jogo; o Pedro vai providenciar)
Entram em `Scripts/SeaAmbience.gd` (players presos em `ship.float_visual`; a lógica de volume
por velocidade/vento/impacto pode ser recuperada do histórico desta sessão).
| # | Som | Tipo | Duração | Quando toca |
|---|---|---|---|---|
| B1 | Água correndo no casco | L 3D | 10–15 s | andando; volume e tom pela velocidade (`ship.measured_speed`) |
| B2 | Proa cortando crista de onda | 1x 3D | 1–2 s | velocidade > 2,8 m/s numa crista |
| B3 | Proa batendo na onda (madeira + água) | 1x 3D | ~1,3 s (2–3 var.) | `ship.splash` com o casco na água |
| B4 | Casco caindo na água depois de salto | 1x 3D | ~1,6 s | `ship.splash` com `ship.airborne` |
| B5 | Queda grande (fim do passeio do ciclone) | 1x 3D | 2–3 s | `weather.ride` termina |
| B6 | Onda grande arrebentando no casco (tempestade) | 1x 3D | ~3,5 s | a cada 4–9 s com badness > 1,6 |
| B7 | Vela panejando (proa contra o vento) | L 3D | 6–8 s | rumo a mais de ~110° do vento |
| B8 | Vento na vela cheia (opcional, discreto) | L 3D | 10 s | — (o Pedro achou cansativo constante) |
| B9 | Madeira rangendo (pontual, não loop) | 1x 3D | 1–2 s (3–4 var.) | balanço forte / viradas |

### Prioridade alta (eventos grandes que hoje são mudos)
| # | Som | Tipo | Duração | Onde entra |
|---|---|---|---|---|
| 1 | Kraken: presságio (grave subindo, sombra chegando) | L 2D | 10–20 s | KrakenEvent fase 1 |
| 2 | Kraken: tentáculo rompendo a água | 1x 3D | 2–3 s (2–3 variações) | cada tentáculo subindo |
| 3 | Kraken: rugido/urro da criatura | 1x 2D | 3–5 s | quando o barco trava |
| 4 | Redemoinho (água girando, sucção) | L 3D | 10–15 s | fase do funil |
| 5 | Barra de ação: impulso/esforço (remo, madeira forçando) | 1x 2D | 0,3–0,6 s | cada toque/Espaço na beirada |
| 6 | Arranque final escapando do redemoinho | 1x 2D | 1,5–2 s | fim do kraken (sucesso) |
| 7 | Naufrágio (madeira rachando + afundando) | 1x 2D | 3–5 s | kraken/fantasma pegou o barco |
| 8 | Navio fantasma: ambiência (rangido etéreo, coro/vento) | L 3D | 15–20 s | GhostShip presente |
| 9 | Navio fantasma: começa a perseguir (sino/grito) | 1x 3D | 2–3 s | entra em CHASE |
| 10 | Navio fantasma some na névoa | 1x 3D | 2–3 s | despistou / amanheceu |
| 11 | Bioma fantasma: ambiência (vento oco, madeira de naufrágio) | L 2D | 20–30 s | perto do cemitério de navios |
| 12 | Vulcão: ronco grave + borbulhar | L 3D | 15–20 s | WorldDecor volcano |

### Prioridade média (vida no mar e mundo)
| # | Som | Tipo | Duração | Onde entra |
|---|---|---|---|---|
| 13 | Golfinho: assobio/clique (2–3 variações) | 1x 3D | 0,5–1,5 s | SeaLife golfinhos |
| 14 | Golfinho: respingo de salto | 1x 3D | ~1 s | (temos `dolphin_splash` sintetizado, falta ligar) |
| 15 | Peixe pulando | 1x 3D | ~0,4 s | (temos `fish_plop`, falta ligar) |
| 16 | Jubarte: canto distante | 1x 3D | 4–8 s | SeaShadows jubarte |
| 17 | Cauda/nadadeira batendo na água (baleia, tubarão-baleia) | 1x 3D | 1–2 s | SeaShadows mergulho |
| 18 | Foca: latido/grunhido | 1x 3D | 0,5–1 s | SeaShadows foca |
| 19 | Tubarão: tensão (grave curto, sem música) | 1x 2D | 2–3 s | SeaShadows tubarão chegando |
| 20 | Boia-sino balançando (sino de canal) | L/1x 3D | 1–3 s (badaladas) | WorldDecor bell / SeaLife bell |
| 21 | Tartaruga gigante: respiro/água escorrendo | 1x 3D | 2–3 s | WorldDecor turtle |
| 22 | Ondas na praia/rochas (marulho na costa) | L 3D | 10–15 s | perto das ilhas e rochas |
| 23 | Fogueira crepitando | L 3D | 8–10 s | IslandEffects bonfire |
| 24 | Baú abrindo + moedas de ouro | 1x 3D | 1,5–2,5 s | IslandEffects chest lid / treasure |
| 25 | Farol: zumbido/vento no alto (noite) | L 3D | 10 s | farol aceso |
| 26 | Lanternas flutuantes (tilintar suave, chama) | L 3D | 8–10 s | lanternas do bioma fantasma |
| 27 | Âncora/corda ao parar (opcional) | 1x 3D | 1–2 s | barco parando |
| 28 | Leme/cordame rangendo ao virar | 1x 3D | 0,5–1 s (3 var.) | virada forte |
| 29 | Ambiência noturna (grilos não; mar calmo + vento leve) | L 2D | 20–30 s | noite (DayNightCycle) |

### Prioridade normal (interface e jogo)
| # | Som | Tipo | Duração | Onde entra |
|---|---|---|---|---|
| 30 | Clique de botão (madeira/papel) | 1x 2D | <0,15 s | todos os botões do HUD |
| 31 | Abrir/fechar a carta (papel desenrolando) | 1x 2D | 0,4–0,8 s | `_set_carta_open` |
| 32 | Aviso/toast (sino curto) | 1x 2D | 0,3–0,5 s | `show_toast` |
| 33 | Chegada numa ilha / nova seção do CV | 1x 2D | 1–2 s | IslandTitleSign aparecendo |
| 34 | Desafio (Time Attack): largada | 1x 2D | 1–2 s | `start_time_attack` |
| 35 | Desafio: tique dos últimos 10 s | 1x 2D | <0,2 s | contagem final |
| 36 | Desafio: vitória / fim do tempo | 1x 2D | 2–3 s (2 arquivos) | `_finish_time_attack` |
| 37 | Cartão de easter egg abrindo | 1x 2D | 1–1,5 s | EasterEggScreen |
| 38 | Canhão sem munição/recarga (clique seco) | 1x 3D | <0,3 s | `fire()` em cooldown |
| 39 | Mira do canhão (manivela/madeira) | L 3D | 1–2 s | segurando para mirar |
| 40 | Entrada "Explorar em 3D" (whoosh/sino) | 1x 2D | 1–2 s | sair da tela inicial para o mar |

---

## 3. Atenção
- **Música:** `Assets/Sound/The Great Sea (The Legend of Zelda Wind Waker) OST Remastered.mp3` está na
  pasta da trilha e entra na playlist automaticamente (main_world lê todo mp3 de `Assets/Sound`).
  Também está em `Config/music_playlist.json` e dentro do build web atual (`Web/public/pck/part-04`,
  `pck-mobile/part-01`). É material da Nintendo e precisa sair antes de publicar.
- Os arquivos em CAIXA ALTA de `SFX/` vieram de fora: vale confirmar a licença de cada um.
- Se algum som de "falta" for melhor sintetizado (ex.: 5, 27, 30, 35, 38), dá para gerar no
  `Tools/make_sfx.py` como os outros.

---

## 4. Checagem dos sons baixados (2026-10-09)

Recortes de teste em `Builds/SfxCandidatos/` (abrir `index.html` no navegador para ouvir), gerados
por `Tools/cut_sfx_candidates.sh` (trecho, mono, pitch quando indicado, fades, loops com as pontas
cruzadas, pico em −1 dBFS, OGG). Nada disso está ligado no jogo ainda.

### Escolha sugerida por slot (licença)
| Slot | Sugestão | Licença |
|---|---|---|
| Kraken presságio | `kraken_pressagio_loop` (385818, pitch 0,85) | CC0 |
| Kraken aviso | `kraken_aparece_boom` (541600) | CC-BY |
| Tentáculo | `kraken_tentaculo_a/b` (376819, pitch 0,7/0,55) | CC-BY 3.0 |
| Rugido | `kraken_rugido` (837799, feito para kraken) | CC0 |
| Redemoinho | `kraken_redemoinho_loop` (567241) + `kraken_redemoinho_borbulha` (696008) | CC0 |
| Barra de ação | `kraken_barra_toque` / `kraken_barra_carga` (555060) | CC0 |
| Arranque final | `kraken_arranque_nc` (716972) | **NC** |
| Naufrágio | `kraken_naufragio` (mix 624150 + 618085 + 17341) | CC0 |
| Navio fantasma | `fantasma_navio_loop` (648654) | CC0 |
| Perseguição | `fantasma_perseguicao` (367746) | CC0 |
| Some na névoa | `teleport_whoosh` (nosso) ou `fantasma_some_whoosh_nc` | — / **NC** |
| Bioma fantasma | `bioma_fantasma_aves_nc` (688741) ou `fantasma_espacial_loop` (55541) | **NC** / CC-BY 3.0 |
| Vulcão | `vulcao_lava_loop` (474849) + `vulcao_erupcao_nc` (674560) | CC0 + **NC** |
| Golfinho | `golfinho_a/b_nc` (202489, real) ou `golfinho_imitacao` (456151) | **NC** / CC0 |
| Jubarte | `baleia_canto` (82325, real) | CC0 |
| Foca | `foca_a/b_nc` (347162) | **NC** |
| Tubarão | `tubarao_tensao_nc` (13698) | **NC** |
| Tartaruga | `tartaruga_respiro` (427414, testar) | CC-BY |
| Cauda batendo, âncora, recarga do canhão (ramrod) | descartados (Pedro, 2026-10-09) | — |
| Boia-sino | `boia_sino` (804786) | CC-BY |
| Costa | `costa_ondas_loop` (795445) | CC0 |
| Noite | `noite_mar_loop` (465435) | CC0 |
| Fogueira | `fogueira_loop` (784223, é carne chiando: testar) | CC-BY |
| Baú | `bau_abrindo_moedas` (872674 + 223342) | CC-BY + CC0 |
| Farol | `farol_buzina_longe` (371290) | CC0 |
| Lanterna | `lanterna_acende` (637533) | CC0 |
| Leme/cordame | `cordame_rangido_a/b/c` (618083–5) | CC0 |
| Clique | `ui_clique_madeira` (342200) | CC0 |
| Carta | `ui_carta_papel` (828026) | CC-BY |
| Aviso | `ui_aviso_pop` (540568) | CC-BY |
| Ilha | `ilha_descoberta` (401179) | CC0 |
| Easter egg | `ovo_pascoa_blip` (531512) | CC0 |
| Desafio | `desafio_contagem` + `desafio_largada` (446130/446142), `desafio_ultimos10s` + `desafio_tempo_acabou` (211103), `desafio_vitoria` (677858) | CC-BY / CC0 |
| Mira | `canhao_mira_manivela_loop` (517120) | CC0 |
| Explorar em 3D | `explorar_whoosh_nc` (241146) ou `teleport_whoosh` (nosso) | **NC** / — |

### Pontos de atenção
- **Licença NC (não comercial):** 202489, 210910, 241146, 243070, 347162, 13698, 674560, 688741,
  716972 e 771034. Um portfólio pessoal costuma contar como uso não comercial, mas é zona cinza
  (o site serve para conseguir trabalho). Para o golfinho, a foca, o tubarão, a erupção e os whooshes,
  vale ter uma alternativa CC0.
- **CC-BY:** precisam de crédito (autor + link + licença) numa página de créditos.
- **Sampling+ (81869):** licença antiga; prefira a 371290.
- **Feitos por IA, segundo os autores:** 810166, 810330, 872674 (baú) e 696008 (tag "artificial-intelligence").
- **157002** é uma compilação de sons do Freesound **e do YouTube**: o CC0 dela é duvidoso.
- **394719** tem cachorro e passarinhos (passeio no parque): não serve para o mar.
- **771034** tem clarinete por cima do canto da baleia.
- **Formatos que o Godot não importa:** `.m4a` (795445, 819108) e `.flac` (211103, 637533, 688741).
  Os recortes já saem em OGG.
- **Tamanho:** os originais somam **1,6 GB** dentro de `res://`, e o Godot já criou `.import` para
  vários deles (a tempestade do Báltico tem 27 min, o farol 1 h, o mar noturno 57 min). Se ficarem no
  projeto, vão parar no `.pck` da web. O ideal é mover os originais para uma pasta com `.gdignore`
  (ex.: `Assets/Sound/SFX/_Originais/`) ou para fora do projeto, e deixar só os recortes escolhidos.
- **Músicas novas** em `Assets/Sound` (`Kraken Blackwave 1/2`, `Last Sail Under 1/2`): no desktop
  entram sozinhas na playlist (o main_world lê todo mp3 da pasta), e não estão no `exclude_filter`
  do export nem no `Config/music_playlist.json`. Se forem trilha do kraken, precisam de lugar próprio.
- **819108 (pasta Biome Ghost)** é uma música de piano, não ambiência.
