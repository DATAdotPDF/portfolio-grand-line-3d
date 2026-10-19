extends Node3D

## Decoração do mapa em 4 biomas (Pedro, 2026-10-09), com os GLBs ORIGINAIS do Meshy (Assets/):
## topologia e materiais originais, sem Decimate/redução/quantização e sem LODs (generate_lods=false
## nos .import). Escala em metros e linha d'água são aplicadas aqui (MODELS), não no arquivo.
## Animados/segmentados: Assets/World/ (Tools/animate_world_props.py e split_island_by_parts.py,
## sempre a partir dos originais).
## Setores = quatro áreas iguais da esfera:
## - NORTE (lat ≥ 30°) "Ruínas do Tempo e Runas Vivas": torre desabada, píer afundado, bastião de
##   runas; cais megalíticos e caixas de recheio; gancho para a patrulha da barbatana de tubarão.
## - LESTE (faixa do equador, lon 0–180°) "Civilização Perdida e Megálitos": marco escalonado,
##   stonehenge, palafitas abandonadas, anel de dólmens; boias de sino e caixas de recheio.
## - SUL (lat ≤ -30°) "Mar Sombrio": caldeira de basalto (fumaça), espinho de obsidiana, arco da
##   mandíbula (navegável), correntes de basalto (o monólito flutua), cemitério de navios; lanternas
##   espectrais em anel na borda (a cada ~175 m) pairando sobre as ondas, névoa verde e o navio
##   fantasma (GhostShip.gd usa is_in_ghost_biome e ghost_points).
## - OESTE (faixa do equador, lon 180–360°) "Recifes de Coral e Grutas": agulha de calcário, arco
##   baixo de recife (navegável), recife escalonado, pináculos gêmeos; a tartaruga nada num circuito
##   só dentro do Oeste; atóis e recifes de coral (os únicos repetidos, escala 0,85–1,15).
## Regras: ISLAND_CLEARANCE m livres em volta das 5 ilhas, corredor de ROUTE_CLEAR m na rota, um
## ponto de interesse a cada ~SPACING m na rota alternando os lados (40–120 m da linha); o que não
## coube na rota vai para o miolo do setor, espalhado e não muito longe da rota.
## - Arcos navegáveis: colisão só nos pilares. Runas (Norte/Sul) brilham mais à noite.
## - Animações (boias, caixas, monólito): feitas no Blender (Tools/animate_world_props.py) e
##   exportadas no GLB como "Idle"; aqui só tocamos em loop e pomos o modelo na altura da onda.
## - Caldeira e rochedo vulcânico (modelos "clean", sem lava/fumaça pintadas): fumaça, rios de lava
##   e água fervendo gerados aqui (_build_volcano_fx).
## - Weather.gd evita os itens (items[].root/height) ao pôr ciclones e tempestades.

const BeastOutline := preload("res://Scripts/BeastOutline.gd")
const ASSETS := "res://Assets/"
## Pasta dos derivados (animados/segmentados, feitos a partir dos originais).
const DERIVED := "res://Assets/World/"
## nome → [GLB, tamanho (m), "h" = altura | "max" = maior lado, calado (fração da altura embaixo d'água)]
const MODELS := {
	"collapsed_watchtower": ["Meshy_AI_collapsed_watchtower__1009133619_image-to-3d-texture.glb", 34.0, "max", 0.1],
	"ruined_sunken_pier": ["Meshy_AI_ruined_sunken_pier_3d_1009133605_image-to-3d-texture.glb", 48.0, "max", 0.2],
	"shattered_runed_bastion": ["Meshy_AI_shattered_runed_basti_1009133629_image-to-3d-texture.glb", 46.0, "max", 0.1],
	"broken_megalithic_quay": ["Meshy_AI_broken_megalithic_qua_1009133641_image-to-3d-texture.glb", 24.0, "max", 0.15],
	"cargo_crates": ["World/cargo_crates.glb", 4.0, "max", 0.4],
	"cyclopean_stepped_cairn": ["Meshy_AI_cyclopean_stepped_cai_1009131201_image-to-3d-texture.glb", 40.0, "max", 0.1],
	"ocean_stonehenge": ["Meshy_AI_ocean_stonehenge_tril_1009131238_image-to-3d-texture.glb", 44.0, "max", 0.1],
	"abandoned_stilt_waterworks": ["World/abandoned_stilt_waterworks.glb", 42.0, "max", 0.15],
	"megalithic_dolmen_ring": ["Meshy_AI_megalithic_dolmen_rin_1009131226_image-to-3d-texture.glb", 48.0, "max", 0.1],
	"bell_buoy": ["World/bell_buoy.glb", 4.5, "h", 0.35],
	"basalt_caldera": ["Meshy_AI_clean_basalt_caldera__1009134113_image-to-3d-texture.glb", 80.0, "max", 0.1],
	"volcanic_crag": ["Meshy_AI_volcanic_crag_clean_r_1009112024_image-to-3d-texture.glb", 60.0, "max", 0.1],
	"obsidian_rib_spire": ["Meshy_AI_obsidian_rib_spire_3d_1009114307_image-to-3d-texture.glb", 40.0, "h", 0.08],
	"leviathan_jaw_arch": ["Meshy_AI_leviathan_jaw_arch_3d_1009114421_image-to-3d-texture.glb", 56.0, "max", 0.1],
	"floating_basalt_chain": ["World/floating_basalt_chain.glb", 46.0, "max", 0.1],
	"ship_graveyard": ["World/ship_graveyard.glb", 60.0, "max", 0.12],
	"spectral_lantern": ["World/spectral_lantern.glb", 5.0, "h", 0.3],
	"limestone_coral_needle": ["Meshy_AI_limestone_coral_needl_1009121510_image-to-3d-texture.glb", 32.0, "h", 0.1],
	"low_reef_arch": ["Meshy_AI_low_reef_arch_3d_1009121532_image-to-3d-texture.glb", 66.0, "max", 0.1],
	"stepped_basalt_reef": ["Meshy_AI_stepped_basalt_reef_3_1009121521_image-to-3d-texture.glb", 36.0, "max", 0.12],
	"twin_sea_pinnacles": ["World/twin_sea_pinnacles.glb", 42.0, "h", 0.08],
	# Tartaruga inteira com o rig do Meshy, animada no Blender (Tools/animate_meshy_rigs_blender.py):
	# clipe "Swim" em loop (mesmas medidas da versão anterior: linha d'água e efeitos valem).
	"turtle_island": ["Optimized/Creatures/turtle.glb", 260.0, "max", 0.5],
	"palm_atoll": ["Meshy_AI_tropical_palm_atoll_3_1008225101_image-to-3d-texture.glb", 30.0, "max", 0.15],
	"coral_reef": ["Meshy_AI_colorful_coral_reef_3_1008225112_image-to-3d-texture.glb", 18.0, "max", 0.62],
	# Carta "The Shattered Sea" (References/2D/Meshy_AI_cartesian-diamond-nautical-chart-2d.png):
	# peças centrais de cada setor e as rochas do recheio.
	"runestone_citadel": ["Meshy_AI_north_runestone_citad_1011000701_image-to-3d-texture.glb", 140.0, "max", 0.1],
	# Partido ao meio pela fenda (Blender) e bem maior: o barco passa entre as metades.
	"split_monolith_runes": ["World/split_monolith_runes.glb", 75.0, "h", 0.08],
	"half_sunken_lighthouse": ["Meshy_AI_half_sunken_lighthous_1008215250_image-to-3d-texture.glb", 34.0, "h", 0.18],
	"driftwood_merchant": ["Meshy_AI_east_driftwood_mercha_1011001340_image-to-3d-texture.glb", 140.0, "max", 0.12],
	"stilt_lookout_post": ["World/stilt_lookout_post.glb", 24.0, "h", 0.15],
	"shipwreck_chest": ["Meshy_AI_shipwreck_with_chest__1008225020_image-to-3d-texture.glb", 32.0, "max", 0.12],
	"coral_paradise": ["Meshy_AI_west_coral_paradise_i_1011000215_image-to-3d-texture.glb", 140.0, "max", 0.12],
	"mushroom_grotto": ["Meshy_AI_mushroom_grotto_caver_1011005842_image-to-3d-texture.glb", 50.0, "max", 0.1],
	"dragon_horns_reef": ["Meshy_AI_dragon_horns_reef_3d_1009111246_image-to-3d-texture.glb", 36.0, "max", 0.1],
	"reef_rocks_cluster": ["Meshy_AI_reef_rocks_cluster_3d_1008214902_image-to-3d-texture.glb", 28.0, "max", 0.12],
	"sea_stack_spire": ["Meshy_AI_sea_stack_spire_3d_1008214818_image-to-3d-texture.glb", 34.0, "h", 0.08],
	"dark_needle_rocks": ["Meshy_AI_dark_needle_rocks_3d_1008233853_image-to-3d-texture.glb", 26.0, "max", 0.15],
	"balancing_tor_rock": ["Meshy_AI_balancing_tor_rock_3d_1009111229_image-to-3d-texture.glb", 26.0, "h", 0.1],
}
const SPACING := 250.0
const ISLAND_CLEARANCE := 230.0
const ROUTE_CLEAR := 40.0
## Distância dos pontos da rota até a linha (m), além do raio do modelo.
const ROUTE_SIDE := Vector2(40.0, 120.0)
## Até onde cada modelo é desenhado (o planeta esconde o resto atrás do horizonte).
const DRAW_DISTANCE := 520.0
## Colisão dos fixos: faixa de altura do casco (m, em volta da linha d'água), tamanho da célula do
## contorno e até onde o colisor sobe.
const HULL_BAND := Vector2(-0.6, 2.5)
const FOOT_CELL := 0.75
const FOOT_TOP := 14.0
## Altura da onda junto aos pontos fixos, com o mar calmo em volta deles (m).
const CALM_WAVE := 0.5
## Boias e caixas são animadas até esta distância do barco.
const FLOAT_DISTANCE := 260.0

enum Sector { NORTH, EAST, SOUTH, WEST }
const SECTOR_LAT := 30.0

## nome → [raio de colisão relativo à pegada, boia?, luz noturna (cor ou null), altura da luz (fração)]
const KINDS := {
	# Norte
	"collapsed_watchtower": [0.3, false, Color(1.0, 0.72, 0.4), 0.78],
	"ruined_sunken_pier": [0.3, false, Color(1.0, 0.72, 0.4), 0.55],
	"shattered_runed_bastion": [0.32, false, Color(0.4, 0.9, 1.0), 0.45],
	"broken_megalithic_quay": [0.33, false, null, 0.0],
	"cargo_crates": [0.4, true, null, 0.0],
	# Leste
	"cyclopean_stepped_cairn": [0.34, false, Color(1.0, 0.8, 0.5), 0.5],
	"ocean_stonehenge": [0.3, false, Color(0.45, 0.85, 1.0), 0.4],
	"abandoned_stilt_waterworks": [0.3, false, Color(1.0, 0.7, 0.38), 0.75],
	"megalithic_dolmen_ring": [0.3, false, Color(0.45, 0.85, 1.0), 0.35],
	"bell_buoy": [0.35, true, Color(1.0, 0.75, 0.35), 0.8],
	# Sul
	"basalt_caldera": [0.36, false, Color(1.0, 0.45, 0.15), 0.85],
	"volcanic_crag": [0.36, false, Color(1.0, 0.45, 0.15), 0.7],
	"obsidian_rib_spire": [0.3, false, Color(0.35, 1.0, 0.85), 0.86],
	"leviathan_jaw_arch": [0.0, false, Color(0.55, 0.75, 1.0), 0.6],
	"floating_basalt_chain": [0.3, false, Color(0.35, 1.0, 0.85), 0.6],
	"ship_graveyard": [0.32, false, Color(0.4, 1.0, 0.65), 0.5],
	"spectral_lantern": [0.35, true, Color(0.35, 1.0, 0.6), 0.7],
	# Oeste
	"limestone_coral_needle": [0.32, false, Color(1.0, 0.45, 0.85), 0.45],
	"low_reef_arch": [0.0, false, Color(1.0, 0.5, 0.85), 0.5],
	"stepped_basalt_reef": [0.34, false, Color(0.4, 0.9, 1.0), 0.6],
	"twin_sea_pinnacles": [0.3, false, Color(1.0, 0.45, 0.85), 0.35],
	"turtle_island": [0.36, false, Color(1.0, 0.9, 0.55), 0.5],
	"palm_atoll": [0.36, false, Color(1.0, 0.9, 0.55), 0.4],
	"coral_reef": [0.35, false, Color(1.0, 0.45, 0.85), 0.5],
	"runestone_citadel": [0.3, false, Color(0.4, 0.9, 1.0), 0.55],
	"split_monolith_runes": [0.3, false, Color(0.4, 0.9, 1.0), 0.5],
	"half_sunken_lighthouse": [0.3, false, Color(1.0, 0.85, 0.5), 0.92],
	"driftwood_merchant": [0.3, false, Color(1.0, 0.72, 0.4), 0.55],
	"stilt_lookout_post": [0.3, false, Color(1.0, 0.72, 0.4), 0.85],
	"shipwreck_chest": [0.3, false, Color(1.0, 0.8, 0.4), 0.4],
	"coral_paradise": [0.3, false, Color(1.0, 0.5, 0.85), 0.5],
	"mushroom_grotto": [0.3, false, Color(0.6, 1.0, 0.7), 0.5],
	"dragon_horns_reef": [0.3, false, Color(1.0, 0.45, 0.85), 0.4],
	"reef_rocks_cluster": [0.32, false, null, 0.0],
	"sea_stack_spire": [0.3, false, null, 0.0],
	"dark_needle_rocks": [0.33, false, null, 0.0],
	"balancing_tor_rock": [0.3, false, null, 0.0],
}
## Modelos antigos que ficaram fora dos biomas (não entram como "modelo novo").
## kraken_maw_teeth: a boca do Kraken não é ilha (Pedro, 2026-10-16); ela só existe no encontro (KrakenEvent).
const RETIRED := ["sunken_lighthouse", "volcanic_island", "sea_arch", "needle_rocks", "lantern_buoy", "kraken_maw_teeth"]
## Arcos navegáveis: só os dois pilares colidem (frações da largura no eixo x).
const ARCHES := ["leviathan_jaw_arch", "low_reef_arch"]
## Modelos com runas: brilham mais à noite (shaders/rune_glow).
const RUNED := ["shattered_runed_bastion", "obsidian_rib_spire", "floating_basalt_chain"]
## Brilho noturno por modelo (Shaders/rune_glow.gdshader): runas, megálitos, corais
## bioluminescentes e o vidro da lanterna. band = faixa de altura (fração) que pode acender.
const NIGHT_GLOW := {
	"rune": {"day_strength": 0.08, "night_strength": 2.2, "hue_band": Vector3(150.0, 205.0, 1.0)},
	"stone": {"day_strength": 0.0, "night_strength": 1.8, "hue_band": Vector3(150.0, 205.0, 1.0)},
	"coral": {"day_strength": 0.0, "night_strength": 1.4, "value_range": Vector2(0.35, 0.65), "saturation_range": Vector2(0.35, 0.6), "pulse_speed": 0.8},
	"lantern": {"day_strength": 0.0, "night_strength": 2.6, "value_range": Vector2(0.45, 0.75), "saturation_range": Vector2(0.05, 0.25),
		"tint": Color(0.35, 1.0, 0.6, 0.65), "band": Vector2(0.56, 0.9)},
}
const GLOW_OF := {
	"shattered_runed_bastion": "rune", "collapsed_watchtower": "rune", "ruined_sunken_pier": "rune",
	"obsidian_rib_spire": "rune", "floating_basalt_chain": "rune",
	"ocean_stonehenge": "stone", "megalithic_dolmen_ring": "stone", "cyclopean_stepped_cairn": "stone",
	"coral_reef": "coral", "limestone_coral_needle": "coral", "twin_sea_pinnacles": "coral",
	"low_reef_arch": "coral", "stepped_basalt_reef": "coral", "spectral_lantern": "lantern",
	"runestone_citadel": "rune", "split_monolith_runes": "rune",
	"coral_paradise": "coral", "mushroom_grotto": "coral", "dragon_horns_reef": "coral",
}
## Quatro mares: cor para onde cada bioma puxa o mar (a = quanto), na ordem N, L, S, O
## (Shaders/ocean_waves.gdshaderinc, biome_tint).
const SEA_TINTS := [Color(0.2, 0.36, 0.8, 0.45), Color(0.0, 0.55, 0.25, 0.38), Color(0.16, 0.05, 0.34, 0.5), Color(0.0, 0.85, 0.7, 0.3)]
## Animados que se veem de longe (bandeira do cemitério, roda d'água, correntes): animam até o limite
## de desenho, não só perto do barco.
const WIDE_ANIMATION := ["ship_graveyard", "abandoned_stilt_waterworks", "floating_basalt_chain", "stilt_lookout_post"]
## Fogos-fátuos (fadinhas) à noite nas ilhas com coqueiros.
const WISPS := ["palm_atoll", "turtle_island"]
## Os únicos que se repetem: escala sorteada nesta faixa.
const REPEAT_SCALE := Vector2(0.85, 1.15)

## Biomas: nome no HUD, marcos (um de cada) e recheio [modelo, quantos].
const BIOMES := {
	# Conjuntos de cada bioma conforme as referências do Pedro (prints dos assets base por área).
	Sector.NORTH: {"name": "Ruínas do Tempo e Runas Vivas", "anchor": Vector2(58.0, 180.0),
		"landmarks": ["runestone_citadel", "shattered_runed_bastion", "collapsed_watchtower", "split_monolith_runes",
			"ruined_sunken_pier", "half_sunken_lighthouse"],
		"filler": ["broken_megalithic_quay", "reef_rocks_cluster"]},
	Sector.EAST: {"name": "Madeira e Baleia", "anchor": Vector2(-15.0, 60.0),
		"landmarks": ["driftwood_merchant", "abandoned_stilt_waterworks", "ocean_stonehenge", "stilt_lookout_post",
			"cyclopean_stepped_cairn", "megalithic_dolmen_ring", "shipwreck_chest"],
		"filler": ["balancing_tor_rock", "sea_stack_spire"]},
	Sector.SOUTH: {"name": "Abismo e Kraken", "anchor": Vector2(-50.0, 0.0),
		"landmarks": ["basalt_caldera", "leviathan_jaw_arch", "ship_graveyard", "volcanic_crag",
			"floating_basalt_chain", "obsidian_rib_spire", "dragon_horns_reef"],
		"filler": ["dark_needle_rocks"]},
	Sector.WEST: {"name": "Corais e Tartaruga", "anchor": Vector2(-12.0, 210.0),
		"landmarks": ["coral_paradise", "mushroom_grotto", "low_reef_arch", "twin_sea_pinnacles", "limestone_coral_needle",
			"stepped_basalt_reef"],
		"filler": ["palm_atoll"]},
}
## Espaço entre os pontos de interesse no preenchimento uniforme (m, centro a centro, aprox.): com o
## horizonte do barco (~250 m para um item de 30 m) sempre tem algo à vista.
const POI_SPACING := 300.0
## Os que se repetem (recheio) variam a escala nesta faixa.
const FILLER_SCALE := Vector2(0.75, 1.25)
## Bichos do mar (sessão das criaturas faz o modelo/rig/som; aqui só o caminho): circuitos fechados
## dentro do setor de cada um, [setor, centro (lat, lon), raios (lat, lon) em graus, velocidade m/s].
## Os colossos são grandes (baleia 320×190 m, caranguejo ~220 m, colosso de ossos ~190 m, tartaruga
## 260 m): cada circuito fica a ≥ ISLAND_CLEARANCE + meio comprimento das ilhas e a ≥ ROUTE_CLEAR +
## meia largura + 20 m da rota (BEAST_HALF), senão o corpo e a colisão entram no corredor do barco.
## As voltas são curtas o bastante para o bicho aparecer de qualquer ponto de dentro delas (ali não
## entra item nenhum, BEAST_CLEAR), senão sobra mar sem nada no horizonte.
const BEASTS := {
	"timber_whale": [Sector.EAST, Vector2(17.5, 60.0), Vector2(5.5, 24.0), 1.2],
	"abyssal_behemoth": [Sector.SOUTH, Vector2(-52.0, 60.0), Vector2(8.0, 22.0), 1.0],
	"abyssal_obsidian": [Sector.SOUTH, Vector2(-52.0, 175.0), Vector2(8.0, 26.0), 0.9],
}
## Meia largura e meio comprimento (m) de cada bicho, para conferir o circuito.
const BEAST_HALF := {"turtle": Vector2(130, 130), "timber_whale": Vector2(95, 160),
	"abyssal_behemoth": Vector2(110, 110), "abyssal_obsidian": Vector2(95, 95)}
## Distância livre de pontos de interesse em volta do caminho dos bichos (m).
const BEAST_CLEAR := 180.0
## Distância mínima entre itens do mesmo setor no miolo (m, além dos raios).
const INTERIOR_GAP := 140.0

## Marcos de borda de cada bioma: [modelo, escala, altura no ar (-1 = sorteada em GHOST_HOVER)].
const BORDER_MARKERS := {
	Sector.NORTH: ["cargo_crates", 1.0, 0.0],
	Sector.EAST: ["bell_buoy", 1.0, 0.0],
	Sector.SOUTH: ["spectral_lantern", 1.0, -1.0],
	Sector.WEST: ["coral_reef", 0.55, 0.0],
}
## Quanto a fileira de marcos fica para dentro da borda do bioma (graus).
const BORDER_INSET := 2.0
## Mar Sombrio: lanternas no anel da borda (a cada ~LANTERN_STEP m), pairando sobre a onda.
const LANTERN_STEP := 175.0
const GHOST_HOVER := Vector2(2.5, 4.0)
const GHOST_GREEN := Color(0.35, 1.0, 0.6)

## Tartaruga: circuito (elipse) só dentro do Oeste, a mais de ISLAND_CLEARANCE das ilhas.
const TURTLE_CENTER := Vector2(0.0, 300.0)   # lat, lon (graus)
const TURTLE_RADII := Vector2(9.0, 12.0)    # lat, lon (graus): volta curta, sempre à vista de dentro
const TURTLE_SPEED := 0.5                    # m/s
## Inclinação para a frente (graus): a cabeça chega mais perto da água.
const TURTLE_PITCH_DEG := 3.0
## Linha d'água no modelo da tartaruga (unidades do modelo abaixo do centro da caixa), medida no Blender
## com a inclinação acima: ~97% das nadadeiras traseiras (leme) ficam embaixo d'água (só a raiz, colada
## no casco, pode raspar a superfície) e as dianteiras saem no alto da remada (-0,22 embaixo … +0,05 fora).
const TURTLE_WATER_Z := 0.19
## Tamanho em que os efeitos da tartaruga (lâmina, gotas, afundar) foram acertados (m): escalam com ela.
const TURTLE_FX_SIZE := 80.0
## Ossos das pontas das nadadeiras (rig do Meshy, Tools/animate_meshy_rigs_blender.py): [ponta, osso de antes].
## Dianteiras Bone_013→012 e Bone_015→014, traseiras Bone_017→016 e Bone_019→018.
const TURTLE_FLIPPERS := [["Bone_012", "Bone_013"], ["Bone_014", "Bone_015"],
	["Bone_016", "Bone_017"], ["Bone_018", "Bone_019"]]

## Sombras dos modelos altos sob controle: com o sol baixo um rochedo de 70 m jogava uma faixa de sombra
## de centenas de metros no mar — mesmo atrás da curva do planeta ou fora do quadro (o mapa de sombra
## cobre 120 m em volta da câmera, mas quem projeta pode estar longe). Liga só perto do barco e com o
## sol alto o bastante para a sombra ter até SHADOW_MAX_LENGTH m.
@export var limit_shadows := true
const SHADOW_REACH := 200.0
const SHADOW_MAX_LENGTH := 120.0
## Caldeira: liga fumaça, lava e água fervendo geradas aqui.
@export var volcano_fx := true
## Quantos rios de lava descem da cratera.
@export var lava_flows := 3

const LAVA_FLOW := preload("res://Shaders/lava_flow.gdshader")
const LAVA_WATER := preload("res://Shaders/lava_water.gdshader")
const SPECTRAL := preload("res://Shaders/spectral_glow.gdshader")
const RUNE_GLOW := preload("res://Shaders/rune_glow.gdshader")
const WorldScale := preload("res://Scripts/WorldScale.gd")
const AssetPacks := preload("res://Scripts/AssetPacks.gd")
## Carregamento por proximidade (site): as medidas de cada modelo (caixa, contorno de colisão, se tem
## "Idle") ficam em KIND_CACHE (Tests/bake_world_kinds.gd, rodado pelo Web/build_variant.ps1). Um
## modelo que não está no pacote principal nasce sem a malha (colisão, luz e efeitos já no lugar) e a
## malha entra quando o pacote do setor chega (AssetPacks.gd). A disposição é a mesma nos dois casos.
const KIND_CACHE := "res://Config/world_kinds.json"
## Sempre no pacote principal: a tartaruga (efeitos presos ao modelo) e os vulcões (os rios de lava
## saem do relevo do modelo e sorteiam do mesmo rng da disposição).
const CORE_KINDS := ["turtle_island", "basalt_caldera", "volcanic_crag"]
## Itens montados por quadro quando um pacote chega (instanciar é o que pesa).
const ATTACH_PER_FRAME := 2
## Raio de carga (só no site): fora dele o modelo do marco sai da cena (colisão, luz e efeitos
## ficam) e, sem nenhum item perto, a cena do modelo é solta da memória. No desktop é o próprio
## alcance de desenho (nada muda na tela); no celular, mais curto: a curvatura do planeta já esconde
## quase tudo além disso. Pedro, 2026-10-16: em vez de baixar a qualidade dos modelos.
const LOAD_RANGE_DESKTOP := DRAW_DISTANCE
const LOAD_RANGE_MOBILE := 360.0
## Folga para sair (evita entrar/sair no limite).
const LOAD_MARGIN := 80.0
## Antecipação do download (m além do raio de carga): o pacote do modelo chega antes de ele entrar.
const PREFETCH := 220.0
## Espera depois que o mundo roda liso antes de começar a trazer modelos (s), e o intervalo entre um
## modelo montado e o próximo no site (s).
const STREAM_SETTLE := 1.5
const ATTACH_GAP := 0.25
## Ritmo da roda d'água abandonada (fração do clipe "Idle" do Blender).
const WATERWHEEL_SPEED := 0.15

var world: Node3D
var planet_radius := 800.0
var scenes := {}
var items: Array[Dictionary] = []
var turtle: Dictionary = {}
var rng := RandomNumberGenerator.new()
## Runas dos bichos do abismo (SeaBeasts: caranguejo/behemoth e gigante de obsidiana) acendem à noite
## como as das ilhas. Espera o SeaBeasts criar os modelos.
var beasts_glowing := false

func _glow_beasts() -> void:
	var beasts_node: Node = world.get("sea_beasts")
	if beasts_node == null:
		beasts_glowing = true
		return
	var list: Array = beasts_node.get("beasts")
	if list == null or list.is_empty():
		return
	for beast in list:
		if beast.name in ["abyssal_behemoth", "abyssal_obsidian"] and beast.get("model") is Node3D:
			_add_rune_glow(beast.model, rng.randf_range(0.0, TAU), NIGHT_GLOW["rune"])
	beasts_glowing = true

## Liga os quatro mares nos materiais do oceano (esfera e patch). Chamado no primeiro quadro: os
## materiais do oceano só são registrados depois que a decoração é criada.
var seas_tinted := false

func _tint_seas() -> void:
	var ocean: Node = world.get("ocean")
	if ocean == null or ocean.materials.is_empty():
		return
	seas_tinted = true
	var tints := PackedVector4Array()
	for c in SEA_TINTS:
		tints.append(Vector4(c.r, c.g, c.b, c.a))
	for material in ocean.materials:
		(material as ShaderMaterial).set_shader_parameter("biome_tints", tints)
		(material as ShaderMaterial).set_shader_parameter("biome_tint_enabled", true)
	print("WORLD_DECOR quatro mares em %d materiais" % ocean.materials.size())

## Pontos de mar livre no Mar Sombrio (normalizados) onde o navio fantasma pode surgir.
var ghost_points: Array[Vector3] = []
var in_ghost_biome := false
var current_sector := -1
var mist: CPUParticles3D
var volcano: Dictionary = {}
## Gancho para os bichos (sessão das criaturas): circuitos por nome, em pontos normalizados.
## "shark_fin": volta no miolo do Norte.
var patrol_paths := {}
## Bichos: nome → {"sector", "speed" (m/s)} (os caminhos estão em patrol_paths).
var beast_info := {}
## Modelos na pasta fora de KINDS e de RETIRED (assets novos): entram uma vez no seu setor.
var new_kinds: Array[String] = []
var glow_mesh: QuadMesh
var rune_materials: Array[ShaderMaterial] = []
## Raio (m) de cada modelo, para respeitar corredor e distâncias antes de criar.
var kind_radius := {}
## Contornos de colisão já calculados (por modelo e escala).
var footprint_cache := {}
## Altura de cada modelo contra a onda máxima (impresso no carregamento).
var lift_report := {}
## Medidas lidas de KIND_CACHE (nome → {"path", "bounds", "idle", "foot"}) e as tiradas dos modelos
## carregados nesta sessão (valem mais que as do arquivo).
var kind_cache := {}
var kind_bounds := {}
var kind_idle := {}
## Itens esperando o modelo (pacote do setor) e os carregamentos em andamento (caminho → nome).
var pending: Array[Dictionary] = []
var loading := {}
var asset_packs: Node
var streaming := false
var load_range := LOAD_RANGE_DESKTOP
var stream_timer := 0.0
var sectors_marked := false
## ?medir: os itens no raio de carga quando o mundo abriu (o barco anda e o raio muda; a marca é
## deste conjunto).
var first_near: Array = []
var first_near_taken := false
var settle_left := STREAM_SETTLE
var attach_wait := 0.0
var lava_rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 20261009
	kind_cache = _read_kind_cache()
	for kind in KINDS:
		var path: String = ASSETS + String(MODELS[kind][0])
		if ResourceLoader.exists(path):
			scenes[kind] = load(path)
		elif not _cached(kind):
			push_warning("WorldDecor: falta %s" % path)
	# Derivados novos em Assets/World (fora de MODELS): entram uma vez no mapa. No export web só
	# existem os .import: o nome do modelo sai deles também.
	for file in DirAccess.get_files_at(DERIVED):
		var name := String(file).trim_suffix(".import")
		if name.get_extension() != "glb":
			continue
		var kind := name.get_basename()
		if not MODELS.has(kind) and not RETIRED.has(kind) and not new_kinds.has(kind) and ResourceLoader.exists(DERIVED + name):
			new_kinds.append(kind)
			scenes[kind] = load(DERIVED + name)
	# Site: os derivados novos que estão num pacote de setor vêm da lista medida, na mesma ordem.
	var cached_new: Array = kind_cache.get("new_kinds", [])
	if not cached_new.is_empty():
		var ordered: Array[String] = []
		for kind in cached_new:
			if (scenes.has(kind) or _cached(kind)) and not MODELS.has(kind) and not RETIRED.has(kind):
				ordered.append(kind)
		for kind in new_kinds:
			if not ordered.has(kind):
				ordered.append(kind)
		new_kinds = ordered
	if scenes.is_empty() and kind_cache.get("kinds", {}).is_empty():
		push_warning("WorldDecor: nenhum modelo")
		return
	var queues := {}
	for sector in BIOMES:
		var queue: Array[String] = []
		for kind in BIOMES[sector].landmarks:
			if _has_kind(kind):
				queue.append(kind)
		queues[sector] = queue
	for kind in new_kinds:
		(queues[Sector.EAST] as Array).append(kind)
	var fillers := {}
	for sector in BIOMES:
		var list: Array[String] = []
		for kind in BIOMES[sector].filler:
			if _has_kind(kind):
				list.append(kind)
		fillers[sector] = list
	_place_turtle()
	_map_beasts()
	_place_centrepieces(queues)
	_place_routes(queues, fillers)
	_place_uniform(queues, fillers)
	_place_borders()
	_fill_horizon_holes(fillers)
	_build_mist()
	_map_ghost_points()
	_map_patrols()
	var per := {}
	for item in items:
		var s: int = item.sector
		per[s] = int(per.get(s, 0)) + 1
	for kind in lift_report:
		print("WORLD_DECOR onda ", lift_report[kind])
	if not pending.is_empty():
		print("WORLD_DECOR esperando os pacotes dos setores: %d itens" % pending.size())
		_start_packs()
	streaming = asset_packs != null
	load_range = LOAD_RANGE_MOBILE if OS.has_feature("mobile_lite") else LOAD_RANGE_DESKTOP
	print("WORLD_DECOR itens=%d modelos=%d por_setor N=%d L=%d S=%d O=%d pontos_fantasma=%d novos=%s" % [items.size(), scenes.size(),
		per.get(Sector.NORTH, 0), per.get(Sector.EAST, 0), per.get(Sector.SOUTH, 0), per.get(Sector.WEST, 0), ghost_points.size(), new_kinds])

# --- Geometria ------------------------------------------------------------------

func _island_dirs() -> Array[Vector3]:
	var dirs: Array[Vector3] = []
	for island in world.islands:
		dirs.append(island.global_position.normalized())
	return dirs

func _island_distance(p: Vector3) -> float:
	var d := INF
	for c in _island_dirs():
		d = minf(d, p.angle_to(c) * planet_radius)
	return d

func _lat_of(p: Vector3) -> float:
	return rad_to_deg(asin(clampf(p.normalized().y, -1.0, 1.0)))

func _lon_of(p: Vector3) -> float:
	var n := p.normalized()
	return fposmod(rad_to_deg(atan2(n.z, n.x)), 360.0)

## Setor de um ponto (direção ou posição no mundo).
func sector_of(p: Vector3) -> int:
	var lat := _lat_of(p)
	if lat >= SECTOR_LAT:
		return Sector.NORTH
	if lat <= -SECTOR_LAT:
		return Sector.SOUTH
	return Sector.EAST if _lon_of(p) < 180.0 else Sector.WEST

func sector_name(sector: int) -> String:
	return BIOMES[sector].name if BIOMES.has(sector) else ""

## O ponto (no mundo) está no Mar Sombrio? margin (m) aumenta (+) ou encolhe (-) a borda.
func is_in_ghost_biome(world_point: Vector3, margin := 0.0) -> bool:
	return _lat_of(world_point) <= -SECTOR_LAT + margin / planet_radius * 180.0 / PI

func _too_close(p: Vector3, gap: float, radius := 0.0) -> bool:
	for item in items:
		if (item.dir as Vector3).angle_to(p) * planet_radius < gap + float(item.radius) + radius:
			return true
	return false

## Ponto a dist metros de center, no rumo bearing (graus a partir do norte local).
func _offset(center: Vector3, bearing_deg: float, dist: float) -> Vector3:
	var basis := _surface_basis(center)
	var tangent := basis.z.rotated(center, deg_to_rad(bearing_deg))
	return center.rotated(center.cross(tangent).normalized(), dist / planet_radius).normalized()

func _route_distance(p: Vector3) -> float:
	var dirs := _island_dirs()
	var d := INF
	for i in dirs.size() - 1:
		var a: Vector3 = dirs[i]
		var b: Vector3 = dirs[i + 1]
		var n := a.cross(b).normalized()
		var off := absf(asin(clampf(p.dot(n), -1.0, 1.0)))
		var proj := (p - n * p.dot(n)).normalized()
		var inside := proj.angle_to(a) + proj.angle_to(b) <= a.angle_to(b) + 0.001
		d = minf(d, (off if inside else minf(p.angle_to(a), p.angle_to(b))) * planet_radius)
	return d

func _radius_of(kind: String) -> float:
	if not kind_radius.has(kind):
		var box := _raw_bounds(kind)
		kind_radius[kind] = maxf(box.size.x, box.size.z) * 0.5 * _unit_scale(kind, box)
	return float(kind_radius[kind])

## Caixa do modelo original (unidades do arquivo): medida do modelo carregado, ou a de KIND_CACHE.
func _raw_bounds(kind: String) -> AABB:
	if not kind_bounds.has(kind):
		if scenes.has(kind):
			var model: Node3D = (scenes[kind] as PackedScene).instantiate()
			kind_bounds[kind] = _bounds(model)
			kind_idle[kind] = _has_idle(model)
			model.free()
		else:
			var entry: Dictionary = kind_cache.kinds[kind]
			var b: Array = entry.bounds
			kind_bounds[kind] = AABB(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]))
			kind_idle[kind] = bool(entry.idle)
			if entry.has("foot") and not footprint_cache.has(kind):
				var hulls := []
				for flat in entry.foot:
					var hull := PackedVector2Array()
					for i in range(0, (flat as Array).size(), 2):
						hull.append(Vector2(flat[i], flat[i + 1]))
					hulls.append(hull)
				footprint_cache[kind] = hulls
	return kind_bounds[kind]

func _has_idle(model: Node) -> bool:
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	return player != null and player.has_animation("Idle")

## Livre para um modelo de raio r: longe das ilhas, fora do corredor da rota e do circuito da
## tartaruga, e a gap m dos outros itens.
func _free(p: Vector3, r: float, gap: float) -> bool:
	return _island_distance(p) >= ISLAND_CLEARANCE + r and _route_distance(p) >= ROUTE_CLEAR + r \
		and _beast_distance(p) >= BEAST_CLEAR + r and not _too_close(p, gap, r)

## Quanto (m) o ponto está para dentro do seu setor (até a borda mais próxima).
func _sector_depth(p: Vector3) -> float:
	var lat := _lat_of(p)
	var to_band := absf(absf(lat) - SECTOR_LAT)
	if absf(lat) >= SECTOR_LAT:
		return deg_to_rad(to_band) * planet_radius
	var lon := _lon_of(p)
	var to_meridian := minf(fposmod(lon, 180.0), 180.0 - fposmod(lon, 180.0)) * cos(deg_to_rad(lat))
	return deg_to_rad(minf(to_band, to_meridian)) * planet_radius

func _fibonacci(i: int, samples: int, offset: float) -> Vector3:
	var y := 1.0 - 2.0 * (float(i) + 0.5) / samples
	var r := sqrt(1.0 - y * y)
	var phi := float(i) * PI * (3.0 - sqrt(5.0)) + offset
	return Vector3(cos(phi) * r, y, sin(phi) * r)

# --- Rota e miolo dos setores ------------------------------------------------------

## Um ponto a cada SPACING m em cada perna, alternando os lados; cada ponto pega o próximo marco do
## setor onde cai (os marcos ficam à vista de quem segue a rota) e, sem marco, um recheio.
func _place_routes(queues: Dictionary, fillers: Dictionary) -> void:
	var dirs := _island_dirs()
	var slot := 0
	for leg in dirs.size() - 1:
		var a: Vector3 = dirs[leg]
		var b: Vector3 = dirs[leg + 1]
		var length: float = a.angle_to(b) * planet_radius
		var tangent: Vector3 = (b - a * a.dot(b)).normalized()
		var along := ISLAND_CLEARANCE + SPACING * 0.5
		while along < length - ISLAND_CLEARANCE:
			var on_route: Vector3 = a.slerp(b, along / length).normalized()
			var side_dir: Vector3 = on_route.cross(a.slerp(b, along / length + 0.001) - on_route).normalized()
			var side := 1.0 if slot % 2 == 0 else -1.0
			slot += 1
			along += SPACING
			for attempt in 2:
				var lateral := rng.randf_range(ROUTE_SIDE.x, ROUTE_SIDE.y)
				var guess: Vector3 = (on_route * planet_radius + side_dir * side * (lateral + 20.0)).normalized()
				var sector := sector_of(guess)
				var landmark := not (queues[sector] as Array).is_empty()
				var queue: Array = queues[sector] if landmark else fillers[sector]
				if queue.is_empty():
					break
				var kind: String = queue[0]
				var r := _radius_of(kind)
				var p: Vector3 = (on_route * planet_radius + side_dir * side * (lateral + r)).normalized()
				if sector_of(p) != sector or not _free(p, r, 30.0):
					side = -side
					continue
				queue.pop_front()
				if not landmark:
					queue.push_back(kind)
				_spawn_in(kind, p, sector, 0.0, not landmark)
				break

## Preenchimento uniforme (como a carta): pontos de um "ruído azul" na esfera, cada um a ~POI_SPACING
## dos outros itens e livre das ilhas, do corredor da rota, do caminho dos bichos e da borda do setor.
## Os marcos que sobraram da rota vão primeiro (a peça central no ponto mais perto do "centro" do
## setor), depois o recheio em ciclo, até o setor encher.
func _place_uniform(queues: Dictionary, fillers: Dictionary) -> void:
	var samples := 9000
	var pool := {}
	for i in samples:
		var p := _fibonacci(i, samples, 0.7)
		var sector := sector_of(p)
		if _island_distance(p) < ISLAND_CLEARANCE + 15.0 or _route_distance(p) < ROUTE_CLEAR + 15.0 \
			or _beast_distance(p) < BEAST_CLEAR + 15.0 or _sector_depth(p) < 60.0:
			continue
		if not pool.has(sector):
			pool[sector] = []
		(pool[sector] as Array).append(p)
	for sector in BIOMES:
		var points: Array = pool.get(sector, [])
		# Ordem sorteada (sem amontoar num canto); a peça central procura o ponto mais perto do centro.
		for k in range(points.size() - 1, 0, -1):
			var m := rng.randi_range(0, k)
			var tmp = points[k]
			points[k] = points[m]
			points[m] = tmp
		var anchor: Vector2 = BIOMES[sector].anchor
		var center := _lat_lon(anchor.x, anchor.y)
		var queue: Array = queues[sector]
		if not queue.is_empty():
			points.sort_custom(func(a, b): return (a as Vector3).angle_to(center) < (b as Vector3).angle_to(center))
			var first: String = queue.pop_front()
			_place_first_fit(first, points, sector, false)
			# O resto volta a ser sorteado.
			for k in range(points.size() - 1, 0, -1):
				var m := rng.randi_range(0, k)
				var tmp = points[k]
				points[k] = points[m]
				points[m] = tmp
		while not queue.is_empty():
			var kind: String = queue.pop_front()
			if not _place_first_fit(kind, points, sector, false):
				push_warning("WorldDecor: sem lugar para %s" % kind)
		var list: Array = fillers[sector]
		var n := 0
		while not list.is_empty():
			var kind: String = list[n % list.size()]
			if not _place_first_fit(kind, points, sector, true):
				break
			n += 1

## Peça central de cada setor (primeira da lista de marcos): no ponto livre mais perto do "centro"
## do setor (BIOMES.anchor), antes da rota pegar os marcos.
func _place_centrepieces(queues: Dictionary) -> void:
	var samples := 9000
	for sector in BIOMES:
		var queue: Array = queues[sector]
		if queue.is_empty():
			continue
		var anchor: Vector2 = BIOMES[sector].anchor
		var center := _lat_lon(anchor.x, anchor.y)
		var points := []
		for i in samples:
			var p := _fibonacci(i, samples, 0.7)
			if sector_of(p) == sector and p.angle_to(center) < deg_to_rad(25.0):
				points.append(p)
		points.sort_custom(func(a, b): return (a as Vector3).angle_to(center) < (b as Vector3).angle_to(center))
		var kind: String = queue.pop_front()
		if not _place_first_fit(kind, points, sector, false):
			queue.push_front(kind)
			push_warning("WorldDecor: peça central %s sem lugar perto do centro" % kind)

## Põe o modelo no primeiro ponto livre da lista (a ~POI_SPACING dos outros) e tira o ponto dela.
func _place_first_fit(kind: String, points: Array, sector: int, filler: bool) -> bool:
	var r := _radius_of(kind) * (FILLER_SCALE.y if filler else 1.0)
	for k in points.size():
		var p: Vector3 = points[k]
		if _island_distance(p) < ISLAND_CLEARANCE + r or _route_distance(p) < ROUTE_CLEAR + r \
			or _beast_distance(p) < BEAST_CLEAR + r or _sector_depth(p) < 40.0 + r:
			continue
		if _too_close(p, POI_SPACING - 50.0, r):
			continue
		points.remove_at(k)
		_spawn_in(kind, p, sector, 0.0, filler)
		return true
	return false

## Horizonte nunca vazio: amostra o mar do planeta todo (~25 m entre amostras) e, onde o barco não veria item nenhum (olho a
## HOLE_EYE m; um item de altura h aparece até √(2R·olho)+√(2R·h), no máximo DRAW_DISTANCE), põe um
## recheio do setor ali mesmo, com as mesmas regras de ilha/rota/bichos. Dentro das voltas dos bichos
## não entra nada (BEAST_CLEAR): as voltas são curtas para o próprio bicho estar sempre à vista.
const HOLE_EYE := 6.0
## Distâncias (m) dos pontos alternativos em volta de um buraco.
const HOLE_STEPS := [100.0, 160.0, 220.0]
func _fill_horizon_holes(fillers: Dictionary) -> void:
	var samples := 12000
	var added := 0
	var turn := {}
	for i in samples:
		var p := _fibonacci(i, samples, 0.3)
		if _island_distance(p) < ISLAND_CLEARANCE:
			continue
		var seen := false
		for item in items:
			var reach := minf(sqrt(2.0 * planet_radius * HOLE_EYE) + sqrt(2.0 * planet_radius * maxf(float(item.height), 0.5)), DRAW_DISTANCE)
			if p.angle_to(item.dir) * planet_radius < reach:
				seen = true
				break
		if seen:
			continue
		# O próprio ponto ou, se ali não pode (dentro da volta de um bicho, rota...), um ponto livre em
		# volta, perto o bastante para o recheio aparecer de lá.
		var candidates: Array[Vector3] = [p]
		for dist in HOLE_STEPS:
			for b in 16:
				candidates.append(_offset(p, b * 22.5, dist))
		for q in candidates:
			var sector := sector_of(q)
			var list: Array = fillers.get(sector, [])
			if list.is_empty():
				continue
			var n: int = turn.get(sector, 0)
			var kind: String = list[n % list.size()]
			var r := _radius_of(kind) * FILLER_SCALE.y
			if not _free(q, r, 80.0) or _sector_depth(q) < 20.0 + r:
				continue
			turn[sector] = n + 1
			_spawn_in(kind, q, sector, 0.0, true)
			added += 1
			break
	print("WORLD_DECOR buracos no horizonte preenchidos: %d" % added)

## Cria no setor: o recheio (que se repete) varia a escala; os marcos são um de cada, em tamanho cheio.
func _spawn_in(kind: String, p: Vector3, sector: int, hover := 0.0, filler := false) -> Dictionary:
	var size := rng.randf_range(FILLER_SCALE.x, FILLER_SCALE.y) if filler else 1.0
	var item := _spawn(kind, p, rng.randf_range(0.0, TAU), size, 0.0, hover)
	item.sector = sector
	if kind == "basalt_caldera":
		volcano = item
	return item

## Escala do original (unidades do Meshy, ~1,9 de lado) para metros (MODELS).
func _unit_scale(kind: String, raw: AABB) -> float:
	if not MODELS.has(kind):
		return 30.0 / maxf(maxf(raw.size.x, raw.size.z), 0.001)
	var spec: Array = MODELS[kind]
	var reference := raw.size.y if spec[2] == "h" else maxf(raw.size.x, maxf(raw.size.y, raw.size.z))
	return float(spec[1]) / maxf(reference, 0.001)

# --- Mar Sombrio --------------------------------------------------------------------

## Marcos de borda: cada bioma tem a sua fileira de marcos ~BORDER_INSET graus para dentro da sua
## borda, a cada ~LANTERN_STEP m (Norte: caixas boiando; Leste: boias de sino; Sul: lanternas
## espectrais pairando; Oeste: corais coloridos pequenos, fixos, com mar calmo em volta). Nas bordas
## que dois biomas dividem ficam duas fileiras lado a lado, uma de cada. Fora do corredor da rota, das
## ilhas e dos marcos. Todas as cópias de um modelo usam a mesma malha (mesma cena instanciada).
func _place_borders() -> void:
	for sector in BORDER_MARKERS:
		var spec: Array = BORDER_MARKERS[sector]
		if not _has_kind(spec[0]):
			continue
		var path := _border_path(sector)
		var walked := 0.0
		var next := rng.randf_range(0.0, LANTERN_STEP)
		var placed := 0
		for i in range(1, path.size()):
			walked += (path[i - 1] as Vector3).angle_to(path[i]) * planet_radius
			if walked < next:
				continue
			next = walked + LANTERN_STEP + rng.randf_range(-20.0, 20.0)
			var p: Vector3 = path[i]
			if _island_distance(p) < ISLAND_CLEARANCE or _route_distance(p) < ROUTE_CLEAR + 20.0 or _too_close(p, 40.0):
				continue
			var hover: float = rng.randf_range(GHOST_HOVER.x, GHOST_HOVER.y) if float(spec[2]) < 0.0 else float(spec[2])
			var item := _spawn(spec[0], p, rng.randf_range(0.0, TAU), float(spec[1]) * rng.randf_range(0.9, 1.1), 0.0, hover)
			item.sector = sector
			item.marker = true
			placed += 1
		print("WORLD_DECOR borda %s: %d %s" % [sector_name(sector), placed, spec[0]])

## Caminho da borda de um setor (pontos densos, a cada 0,5°), já recuado para dentro dele.
func _border_path(sector: int) -> Array[Vector3]:
	var path: Array[Vector3] = []
	var inner := SECTOR_LAT - BORDER_INSET
	if sector == Sector.NORTH or sector == Sector.SOUTH:
		var ring_lat := (SECTOR_LAT + BORDER_INSET) * (1.0 if sector == Sector.NORTH else -1.0)
		for k in 721:
			path.append(_lat_lon(ring_lat, k * 0.5))
		return path
	var west := 0.0 if sector == Sector.EAST else 180.0
	var a := west + BORDER_INSET
	var b := west + 180.0 - BORDER_INSET
	# Volta fechada: borda de cima, lado leste, borda de baixo, lado oeste.
	var lon := a
	while lon <= b:
		path.append(_lat_lon(inner, lon))
		lon += 0.5
	var lat := inner
	while lat >= -inner:
		path.append(_lat_lon(lat, b))
		lat -= 0.5
	lon = b
	while lon >= a:
		path.append(_lat_lon(-inner, lon))
		lon -= 0.5
	lat = -inner
	while lat <= inner:
		path.append(_lat_lon(lat, a))
		lat += 0.5
	return path

## Pontos de mar livre no Mar Sombrio (longe dos marcos e da ilha do Contato) para o navio fantasma.
func _map_ghost_points() -> void:
	var samples := 4000
	for i in samples:
		var p := _fibonacci(i, samples, 0.0)
		if not is_in_ghost_biome(p * planet_radius, -20.0) or _island_distance(p) < ISLAND_CLEARANCE:
			continue
		var clear := true
		for item in items:
			if float(item.hover) > 0.0:
				continue
			if (item.dir as Vector3).angle_to(p) * planet_radius < float(item.radius) + 30.0:
				clear = false
				break
		if clear:
			ghost_points.append(p)

## Circuito da barbatana de tubarão (Norte): volta em lat 52°, longe das ilhas e da rota.
## Circuitos dos bichos do mar (BEASTS + a tartaruga): patrol_paths[nome] = pontos normalizados,
## beast_info[nome] = {setor, velocidade}. Confere ilhas e rota (avisa se algum trecho encosta).
func _map_beasts() -> void:
	var turtle_path: Array[Vector3] = []
	for n in 48:
		turtle_path.append(_turtle_point(TAU * n / 48.0))
	patrol_paths["turtle"] = turtle_path
	beast_info["turtle"] = {"sector": Sector.WEST, "speed": TURTLE_SPEED}
	var turtle_bad := 0
	for p in turtle_path:
		if _island_distance(p) < ISLAND_CLEARANCE + BEAST_HALF.turtle.y or _route_distance(p) < ROUTE_CLEAR + BEAST_HALF.turtle.x + 20.0:
			turtle_bad += 1
	print("WORLD_DECOR bicho turtle: %d pontos, %d perto de ilha/rota" % [turtle_path.size(), turtle_bad])
	for name in BEASTS:
		var spec: Array = BEASTS[name]
		var c: Vector2 = spec[1]
		var radii: Vector2 = spec[2]
		var path: Array[Vector3] = []
		var bad := 0
		for n in 48:
			var a := TAU * n / 48.0
			var p := _lat_lon(c.x + radii.x * sin(a), c.y + radii.y * cos(a))
			var half: Vector2 = BEAST_HALF[name]
			if _island_distance(p) < ISLAND_CLEARANCE + half.y or _route_distance(p) < ROUTE_CLEAR + half.x + 20.0 				or sector_of(p) != int(spec[0]):
				bad += 1
			path.append(p)
		patrol_paths[name] = path
		beast_info[name] = {"sector": spec[0], "speed": spec[3]}
		print("WORLD_DECOR bicho %s: %d pontos, %d perto de ilha/rota/fora do setor" % [name, path.size(), bad])

## Distância (m) até o caminho de algum bicho (circuitos de BEASTS e da tartaruga).
func _beast_distance(p: Vector3) -> float:
	var d := INF
	for name in patrol_paths:
		if name == "shark_fin":
			continue
		for q in patrol_paths[name]:
			d = minf(d, p.angle_to(q) * planet_radius)
	return d

func _map_patrols() -> void:
	var path: Array[Vector3] = []
	for n in 48:
		var p := _lat_lon(52.0, 360.0 * n / 48.0)
		if _island_distance(p) > ISLAND_CLEARANCE and _route_distance(p) > ROUTE_CLEAR + 20.0:
			path.append(p)
	patrol_paths["shark_fin"] = path

func _bearing_to(from: Vector3, to: Vector3) -> float:
	var basis := _surface_basis(from)
	var t := (to - from).slide(from).normalized()
	return rad_to_deg(basis.z.signed_angle_to(t, from))

## Névoa verde baixa em volta do barco enquanto ele está no Mar Sombrio.
func _build_mist() -> void:
	# CPUParticles3D: no renderer de compatibilidade (WebGL2) as GPUParticles3D daqui não apareciam.
	mist = CPUParticles3D.new()
	mist.name = "GhostMist"
	mist.amount = 40
	mist.lifetime = 14.0
	mist.preprocess = 14.0
	mist.local_coords = false
	mist.visible = false
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	mist.emission_box_extents = Vector3(120.0, 1.5, 120.0)
	mist.direction = Vector3.UP
	mist.spread = 60.0
	mist.initial_velocity_min = 0.2
	mist.initial_velocity_max = 0.6
	mist.gravity = Vector3.ZERO
	mist.scale_amount_min = 0.7
	mist.scale_amount_max = 1.3
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	fade.colors = PackedColorArray([Color(0.55, 0.9, 0.7, 0.0), Color(0.55, 0.9, 0.7, 0.16), Color(0.5, 0.8, 0.65, 0.13), Color(0.5, 0.8, 0.65, 0.0)])
	mist.color_ramp = fade
	var puff := QuadMesh.new()
	puff.size = Vector2.ONE * 23.0
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 6.0
	mat.albedo_texture = _soft_texture(0.9)
	puff.material = mat
	mist.mesh = puff
	add_child(mist)

func _soft_texture(alpha: float) -> GradientTexture2D:
	var soft := Gradient.new()
	soft.set_color(0, Color(1, 1, 1, alpha))
	soft.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = soft
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	return texture

## Brilho (billboard aditivo) para lanternas e cratera: barato e visível de longe.
func _glow(color: Color, size: float) -> MeshInstance3D:
	if glow_mesh == null:
		glow_mesh = QuadMesh.new()
		glow_mesh.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = color
	mat.albedo_texture = _soft_texture(1.0)
	var glow := MeshInstance3D.new()
	glow.mesh = glow_mesh
	glow.material_override = mat
	glow.scale = Vector3.ONE * size
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.visibility_range_end = DRAW_DISTANCE + 80.0
	return glow

# --- Criação --------------------------------------------------------------------

## size: escala do modelo; sink: quanto afunda (fração da altura); hover: altura no ar (m).
func _spawn(kind: String, dir: Vector3, yaw: float, size := 1.0, sink := 0.0, hover := 0.0) -> Dictionary:
	var info: Array = KINDS.get(kind, [0.33, false, null, 0.0])
	var root := Node3D.new()
	root.name = "%s_%d" % [kind, items.size()]
	add_child(root)
	# Sem o modelo no pacote principal (site): nasce sem a malha, que entra em _dress_model.
	var model: Node3D = null
	if scenes.has(kind):
		model = (scenes[kind] as PackedScene).instantiate()
		root.add_child(model)
	# Original em metros, com a linha d'água (calado) no y = 0 e centrado na base.
	var raw := _raw_bounds(kind)
	var k := _unit_scale(kind, raw) * size
	var draft: float = MODELS[kind][3] if MODELS.has(kind) else 0.1
	var water := raw.position.y + raw.size.y * draft
	var model_pos := -Vector3(raw.get_center().x, water, raw.get_center().z) * k - Vector3.UP * sink * raw.size.y * k
	var aabb := AABB(raw.position * k + model_pos, raw.size * k)
	# O mar fica calmo em volta de cada ponto fixo (main_world._update_calm_spots, raio = item.radius):
	# a onda ali é de ~CALM_WAVE m. A linha d'água de cada modelo é o calado em MODELS (acertado olhando
	# cada um no nível do mar); o modelo ainda sobe o que der sem a base aparecer no cavado calmo.
	if not bool(KINDS.get(kind, [0, false])[1]) and hover <= 0.0 and sink <= 0.0:
		var depth := -aabb.position.y
		var lift := clampf(depth - CALM_WAVE, 0.0, CALM_WAVE)
		model_pos.y += lift
		aabb.position.y += lift
		if not lift_report.has(kind):
			lift_report[kind] = "%s: acima=%.1f m, abaixo=%.1f m, subiu %.1f m, raio calmo=%.1f m" % [kind, aabb.end.y,
				depth, lift, maxf(aabb.size.x, aabb.size.z) * 0.5]
	if model:
		model.scale = Vector3.ONE * k
		model.position = model_pos
	var basis := _surface_basis(dir).rotated(dir, yaw)
	root.global_transform = Transform3D(basis, dir * (planet_radius + hover))
	var footprint := minf(aabb.size.x, aabb.size.z)
	var floating := bool(info[1]) and hover <= 0.0
	var pieces := []
	var footprint_pending := false
	if floating and float(info[0]) > 0.0:
		# Boias e caixas: um cilindro simples (camada das boias).
		var body := StaticBody3D.new()
		body.collision_layer = 8
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = maxf(0.8, footprint * float(info[0]))
		cylinder.height = maxf(4.0, aabb.end.y + 2.0)
		shape.shape = cylinder
		shape.position.y = cylinder.height * 0.5 - 2.0
		body.add_child(shape)
		root.add_child(body)
	elif hover <= 0.0:
		# Fixos: colisão pelo contorno do modelo na altura do casco, uma peça por rocha/pilar —
		# canais e vãos (pináculos gêmeos, arcos, stonehenge...) ficam livres para o barco passar.
		var body := StaticBody3D.new()
		body.name = "Footprint"
		body.collision_layer = 1
		body.collision_mask = 0
		root.add_child(body)
		if model == null and not footprint_cache.has(kind):
			footprint_pending = true
		else:
			pieces = _footprint_pieces(kind, size, model, root)
			_fill_footprint(body, pieces)
	var ghostly := kind == "spectral_lantern" and hover > 0.0
	var light: OmniLight3D = null
	if info[2] != null:
		light = OmniLight3D.new()
		light.light_color = GHOST_GREEN if ghostly else info[2]
		light.omni_range = maxf(12.0, aabb.size.y * (4.0 if ghostly else 1.3))
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.position = Vector3(0.0, aabb.position.y + aabb.size.y * float(info[3]), 0.0)
		light.visible = false
		root.add_child(light)
	var item := {"kind": kind, "root": root, "model": null, "dir": dir, "yaw": yaw, "float": floating, "light": light,
		"smoke": null, "phase": rng.randf_range(0.0, TAU), "height": aabb.end.y, "hover": hover,
		"radius": maxf(aabb.size.x, aabb.size.z) * 0.5, "player": null, "sector": sector_of(dir), "pieces": pieces,
		"casts": aabb.size.y > 8.0, "tall": aabb.end.y, "shadow_on": not limit_shadows,
		"scale": k, "size": size, "model_pos": model_pos, "aabb": aabb}
	if footprint_pending:
		item.needs_footprint = true
	if ghostly:
		# Lanterna espectral: a luz fica só DENTRO da lanterna (vidro + halo pequeno), e só à noite.
		var glow := _glow(Color(GHOST_GREEN, 0.7), aabb.size.y * 0.55)
		glow.position = Vector3(0.0, aabb.position.y + aabb.size.y * 0.72, 0.0)
		root.add_child(glow)
		item.glow = glow
	if kind in WISPS:
		var wisps := _wisps(aabb)
		root.add_child(wisps)
		item.wisps = wisps
	if kind == "obsidian_rib_spire":
		var flame := _spirit_flame(aabb)
		root.add_child(flame)
		item.flame = flame
	# Animação feita no Blender ("Idle" no GLB): loop, começo e ritmo sorteados (não sincroniza). O
	# sorteio é feito aqui, mesmo sem o modelo ainda, para a disposição seguir igual.
	if kind_idle.get(kind, false):
		item.idle_seek = rng.randf()
		item.idle_speed = rng.randf_range(0.85, 1.15)
	if model:
		_dress_model(item, model)
	else:
		pending.append(item)
	if kind in ["basalt_caldera", "volcanic_crag"]:
		if volcano_fx:
			_build_volcano_fx(item, aabb)
	items.append(item)
	return item

## O que depende da malha: escala/posição, alcance de desenho, sombra, runas, animação e a roda d'água.
func _dress_model(item: Dictionary, model: Node3D) -> void:
	var root: Node3D = item.root
	if model.get_parent() == null:
		root.add_child(model)
		root.move_child(model, 0)
	item.model = model
	var aabb: AABB = item.aabb
	model.scale = Vector3.ONE * float(item.scale)
	model.position = item.model_pos
	var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(item.casts) and bool(item.shadow_on) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var gi := mesh as GeometryInstance3D
		gi.visibility_range_end = DRAW_DISTANCE + aabb.size.length()
		gi.visibility_range_end_margin = 40.0
		gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		# Sombra só nos altos, e mesmo assim ligada/desligada em _update_shadows (perto + sol alto).
		gi.cast_shadow = shadow
	if GLOW_OF.has(item.kind):
		var before := rune_materials.size()
		_add_rune_glow(model, float(item.phase), NIGHT_GLOW[GLOW_OF[item.kind]])
		item.rune_mats = rune_materials.slice(before)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player and player.has_animation("Idle") and item.has("idle_seek"):
		player.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
		player.play("Idle")
		player.seek(float(item.idle_seek) * player.current_animation_length, true)
		player.speed_scale = float(item.idle_speed)
		item.player = player
	# Roda d'água: POI antigo, sem água caindo; a roda só gira bem devagar, como se fosse o vento
	# (Pedro, 2026-10-16). _build_waterwheel_water fica guardada, sem uso.
	if item.kind == "abandoned_stilt_waterworks" and player:
		player.speed_scale = WATERWHEEL_SPEED
	# Colisão que esperava o contorno do modelo (não estava em KIND_CACHE).
	if item.get("needs_footprint", false):
		item.erase("needs_footprint")
		item.pieces = _footprint_pieces(item.kind, float(item.size), model, root)
		var body := root.get_node_or_null("Footprint") as StaticBody3D
		if body:
			_fill_footprint(body, item.pieces)

func _bounds(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		var box: AABB = _node_transform(mi, node) * mi.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

## Colisão pelo contorno: os vértices do modelo na faixa do casco (HULL_BAND, em m em volta da
## linha d'água) viram células de FOOT_CELL m; cada grupo de células encostadas é uma peça (rocha,
## pilar); peça côncava demais é dividida em duas (até 3 vezes). Devolve contornos convexos (xz) no
## espaço do item. Um cálculo por modelo (e escala), guardado.
func _fill_footprint(body: StaticBody3D, pieces: Array) -> void:
	for hull in pieces:
		var points := PackedVector3Array()
		for q in hull:
			points.append(Vector3(q.x, -3.0, q.y))
			points.append(Vector3(q.x, FOOT_TOP, q.y))
		var convex := ConvexPolygonShape3D.new()
		convex.points = points
		var shape := CollisionShape3D.new()
		shape.shape = convex
		body.add_child(shape)

func _footprint_pieces(kind: String, size: float, model: Node3D, root: Node3D) -> Array:
	# Guardado em escala 1 (por modelo): cópias com escala sorteada só reescalam os contornos.
	if footprint_cache.has(kind):
		var scaled := []
		for hull in footprint_cache[kind]:
			var h := PackedVector2Array()
			for q in hull:
				h.append(q * size)
			scaled.append(h)
		return scaled
	var cells := {}
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if mi.mesh == null or mi.mesh is QuadMesh:
			continue
		var xf := _node_transform(mi, root)
		for s in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			var stride := maxi(1, verts.size() / 250000)
			for vi in range(0, verts.size(), stride):
				var p := xf * verts[vi]
				if p.y < HULL_BAND.x or p.y > HULL_BAND.y:
					continue
				cells[Vector2i(floori(p.x / FOOT_CELL), floori(p.z / FOOT_CELL))] = true
	var pieces := []
	var seen := {}
	for c in cells:
		if seen.has(c):
			continue
		var comp: Array[Vector2i] = []
		var stack: Array[Vector2i] = [c]
		seen[c] = true
		while not stack.is_empty():
			var cur: Vector2i = stack.pop_back()
			comp.append(cur)
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var n := cur + Vector2i(dx, dz)
					if cells.has(n) and not seen.has(n):
						seen[n] = true
						stack.append(n)
		# Pedrinha/folha solta de uma célula não segura o barco.
		if comp.size() >= 2:
			pieces += _hull_pieces(comp, 3)
	var unit := []
	for hull in pieces:
		var h := PackedVector2Array()
		for q in hull:
			h.append(q / size)
		unit.append(h)
	footprint_cache[kind] = unit
	return pieces

func _hull_pieces(comp: Array[Vector2i], depth: int) -> Array:
	var corners := PackedVector2Array()
	for c in comp:
		var o := Vector2(c) * FOOT_CELL
		corners.append(o)
		corners.append(o + Vector2(FOOT_CELL, 0))
		corners.append(o + Vector2(0, FOOT_CELL))
		corners.append(o + Vector2(FOOT_CELL, FOOT_CELL))
	var hull := Geometry2D.convex_hull(corners)
	var area := 0.0
	for i in hull.size() - 1:
		area += hull[i].x * hull[i + 1].y - hull[i + 1].x * hull[i].y
	area = absf(area) * 0.5
	var filled := comp.size() * FOOT_CELL * FOOT_CELL
	if depth <= 0 or comp.size() < 8 or filled >= area * 0.55:
		return [hull]
	# Côncava (ex.: rochas ligadas por uma faixa fina): divide no meio do eixo mais comprido.
	var lo := Vector2(INF, INF)
	var hi := -lo
	for c in comp:
		lo = lo.min(Vector2(c))
		hi = hi.max(Vector2(c))
	var along_x := hi.x - lo.x >= hi.y - lo.y
	var cut := (lo.x + hi.x) * 0.5 if along_x else (lo.y + hi.y) * 0.5
	var a: Array[Vector2i] = []
	var b: Array[Vector2i] = []
	for c in comp:
		if (float(c.x) if along_x else float(c.y)) < cut:
			a.append(c)
		else:
			b.append(c)
	var out := []
	for half in [a, b]:
		if half.size() >= 2:
			out += _hull_pieces(half, depth - 1)
	return out

## Brilho noturno: camada aditiva com a textura do próprio material (o material original não muda).
func _add_rune_glow(model: Node3D, phase: float, profile: Dictionary) -> void:
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		var source := mi.get_active_material(0) as BaseMaterial3D
		if source == null or source.albedo_texture == null:
			continue
		var overlay := ShaderMaterial.new()
		overlay.shader = RUNE_GLOW
		overlay.set_shader_parameter("albedo_map", source.albedo_texture)
		overlay.set_shader_parameter("phase", phase)
		for key in profile:
			if key == "band":
				# Faixa em frações da altura → espaço da malha.
				var box := mi.get_aabb()
				var band: Vector2 = profile.band
				overlay.set_shader_parameter("y_band", Vector2(box.position.y + box.size.y * band.x, box.position.y + box.size.y * band.y))
			else:
				overlay.set_shader_parameter(key, profile[key])
		mi.material_overlay = overlay
		rune_materials.append(overlay)

## Roda d'água: a água cai da calha (Empty "WaterSpout" do GLB) sobre as pás e respinga no pé da roda
## (Empty "WaterSplash"). O giro da roda é a animação "Idle" feita no Blender.
func _build_waterwheel_water(item: Dictionary) -> void:
	var root: Node3D = item.root
	var model: Node3D = item.model
	var spout := model.find_child("WaterSpout", true, false) as Node3D
	var splash := model.find_child("WaterSplash", true, false) as Node3D
	if spout == null or splash == null:
		push_warning("WorldDecor: roda d'água sem WaterSpout/WaterSplash")
		return
	var top := root.to_local(spout.global_position)
	var foot := root.to_local(splash.global_position)
	var fall := maxf(top.y - foot.y, 2.0)
	var stream := CPUParticles3D.new()
	stream.name = "WaterFall"
	stream.position = top
	stream.amount = 240
	stream.lifetime = sqrt(2.0 * fall / 9.8)
	stream.preprocess = stream.lifetime
	stream.local_coords = true
	stream.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	stream.emission_box_extents = Vector3(0.6, 0.1, 0.35)
	stream.direction = Vector3(0, -1, 0)
	stream.spread = 4.0
	stream.initial_velocity_min = 0.3
	stream.initial_velocity_max = 0.8
	stream.gravity = Vector3(0, -9.8, 0) + (foot - top).normalized().slide(Vector3.UP) * 1.2
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.1, 0.85, 1.0])
	fade.colors = PackedColorArray([Color(0.6, 0.84, 1.0, 0.0), Color(0.6, 0.84, 1.0, 0.9), Color(0.75, 0.92, 1.0, 0.75), Color(0.9, 0.97, 1.0, 0.0)])
	stream.color_ramp = fade
	stream.mesh = _water_quad(1.5)
	root.add_child(stream)
	var spray := CPUParticles3D.new()
	spray.name = "WaterFoam"
	spray.position = foot
	spray.amount = 80
	spray.lifetime = 0.9
	spray.preprocess = 0.9
	spray.local_coords = true
	spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	spray.emission_sphere_radius = 0.8
	spray.direction = Vector3.UP
	spray.spread = 55.0
	spray.initial_velocity_min = 2.0
	spray.initial_velocity_max = 4.5
	spray.gravity = Vector3(0, -9.8, 0)
	var puff := Gradient.new()
	puff.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	puff.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(0.95, 0.98, 1.0, 0.85), Color(1, 1, 1, 0.0)])
	spray.color_ramp = puff
	spray.mesh = _water_quad(1.3)
	root.add_child(spray)
	item.smoke = stream
	item.steam = [spray]

## Gota/jato de água (billboard macio, alfa normal).
func _water_quad(size: float) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_texture(1.0)
	quad.material = mat
	return quad

## Fogos-fátuos: luzinhas que flutuam devagar em volta da ilha (fadinhas), só à noite.
func _wisps(aabb: AABB) -> CPUParticles3D:
	var wisps := CPUParticles3D.new()
	wisps.name = "Wisps"
	wisps.amount = 22
	wisps.lifetime = 7.0
	wisps.preprocess = 7.0
	wisps.local_coords = true
	wisps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	wisps.emission_sphere_radius = maxf(aabb.size.x, aabb.size.z) * 0.38
	wisps.position = Vector3(0.0, maxf(2.0, aabb.end.y * 0.3), 0.0)
	wisps.direction = Vector3.UP
	wisps.spread = 180.0
	wisps.initial_velocity_min = 0.2
	wisps.initial_velocity_max = 0.7
	wisps.gravity = Vector3(0.0, 0.05, 0.0)
	wisps.tangential_accel_min = -0.4
	wisps.tangential_accel_max = 0.4
	wisps.damping_min = 0.05
	wisps.damping_max = 0.15
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 0.5, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.0)])
	wisps.color_ramp = fade
	var hues := Gradient.new()
	hues.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	hues.colors = PackedColorArray([Color(1.0, 0.95, 0.55), Color(0.55, 1.0, 0.85), Color(0.75, 0.75, 1.0)])
	wisps.color_initial_ramp = hues
	wisps.mesh = _glow_quad(0.9)
	wisps.visible = false
	return wisps

## Chama espiritual verde-água na copa da árvore negra (referência: References/2D/
## Meshy_AI_obsidian-rib-spire-isolated-concept.png): labaredas subindo, halo e luz.
func _spirit_flame(aabb: AABB) -> Node3D:
	var crown := Node3D.new()
	crown.name = "SpiritFlame"
	crown.position = Vector3(0.0, aabb.end.y - aabb.size.y * 0.16, 0.0)
	var flame := CPUParticles3D.new()
	flame.amount = 44
	flame.lifetime = 1.8
	flame.preprocess = 1.8
	flame.local_coords = true
	flame.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flame.emission_sphere_radius = aabb.size.x * 0.04
	flame.direction = Vector3.UP
	flame.spread = 14.0
	flame.initial_velocity_min = 2.5
	flame.initial_velocity_max = 4.5
	flame.gravity = Vector3.ZERO
	flame.tangential_accel_min = -1.5
	flame.tangential_accel_max = 1.5
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 0.6, 1.0])
	fade.colors = PackedColorArray([Color(0.6, 1.0, 0.9, 0.0), Color(0.55, 1.0, 0.88, 0.95), Color(0.25, 0.9, 0.75, 0.55), Color(0.2, 0.7, 0.65, 0.0)])
	flame.color_ramp = fade
	flame.mesh = _glow_quad(aabb.size.y * 0.045)
	crown.add_child(flame)
	var halo := _glow(Color(0.35, 1.0, 0.85, 0.35), aabb.size.y * 0.25)
	crown.add_child(halo)
	return crown

## Quad aditivo e macio (billboard de partícula) do tamanho dado.
func _glow_quad(size: float) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_texture(1.0)
	mat.disable_fog = true
	quad.material = mat
	return quad

## Transformação de node no espaço de ancestor (sem depender da árvore estar no mundo).
func _node_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf

func _surface_basis(up: Vector3) -> Basis:
	var x := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	return Basis(x, up, x.cross(up).normalized())

# --- Vulcão ----------------------------------------------------------------------

## Fumaça na cratera, rios de lava até o mar e água fervendo em volta. Tudo sai do relevo do
## próprio modelo (mapa de alturas dos vértices), então vale para o modelo novo do Pedro.
func _build_volcano_fx(item: Dictionary, aabb: AABB) -> void:
	# Sorteio próprio: quantos números a busca dos rios gasta depende do relevo do modelo (a variante
	# leve do site tem outro), e com o rng da disposição o mapa saía diferente no site.
	lava_rng.seed = hash(item.kind) ^ 20261009
	var root: Node3D = item.root
	var model: Node3D = item.model
	var grid := 56
	var heights := _height_grid(model, aabb, grid)
	var cell := Vector2(aabb.size.x / grid, aabb.size.z / grid)
	# Cratera: média das células no topo.
	var top := -INF
	for v in heights:
		top = maxf(top, v)
	var crater := Vector3.ZERO
	var count := 0
	for j in grid:
		for i in grid:
			if heights[j * grid + i] > top - aabb.size.y * 0.05:
				crater += Vector3(i, 0.0, j)
				count += 1
	crater /= maxf(count, 1)
	var ci := clampi(int(round(crater.x)), 0, grid - 1)
	var cj := clampi(int(round(crater.z)), 0, grid - 1)
	var crater_pos := Vector3(aabb.position.x + (ci + 0.5) * cell.x, heights[cj * grid + ci], aabb.position.z + (cj + 0.5) * cell.y)
	# Fumaça e brilho da cratera.
	# Chaminé: a fumaça sai do topo do modelo, em cima da cratera.
	var smoke := _volcano_smoke(Vector3(crater_pos.x, maxf(crater_pos.y, aabb.end.y - 3.0), crater_pos.z))
	root.add_child(smoke)
	item.smoke = smoke
	var crater_glow := _glow(Color(1.0, 0.45, 0.12, 0.8), aabb.size.y * 0.35)
	crater_glow.position = crater_pos + Vector3.UP * 2.0
	root.add_child(crater_glow)
	# Rios de lava.
	var ends: Array[Vector3] = []
	var steam: Array[CPUParticles3D] = []
	var lava_mat := ShaderMaterial.new()
	lava_mat.shader = LAVA_FLOW
	var made := 0
	for attempt in lava_flows * 4:
		if made >= lava_flows:
			break
		var f := made
		var bearing := TAU * (attempt % lava_flows) / lava_flows + attempt / lava_flows * 0.5 + lava_rng.randf_range(-0.3, 0.3)
		var path := _lava_path(heights, grid, Vector2i(ci, cj), Vector2(cos(bearing), sin(bearing)))
		# Só vale rio que chega perto do mar (senão ele "cairia" do ar na borda do modelo).
		if path.size() < 3 or heights[path[-1].y * grid + path[-1].x] > maxf(3.0, aabb.size.y * 0.06):
			continue
		made += 1
		var points: Array[Vector3] = []
		for c in path:
			points.append(Vector3(aabb.position.x + (c.x + 0.5) * cell.x, heights[c.y * grid + c.x] + 0.35, aabb.position.z + (c.y + 0.5) * cell.y))
		points = _chaikin(_chaikin(points))
		# Termina dentro d'água.
		var last := points[points.size() - 1]
		var out := Vector3(last.x - crater_pos.x, 0.0, last.z - crater_pos.z).normalized()
		points.append(Vector3(last.x, -0.4, last.z) + out * 3.0)
		var ribbon := MeshInstance3D.new()
		ribbon.name = "Lava_%d" % f
		ribbon.mesh = _ribbon(points, aabb.size.y * 0.05, aabb.size.y * 0.03)
		ribbon.material_override = lava_mat
		ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ribbon.visibility_range_end = DRAW_DISTANCE
		root.add_child(ribbon)
		var end := points[points.size() - 1]
		ends.append(end)
		var puff := _steam(end)
		root.add_child(puff)
		steam.append(puff)
	item.steam = steam
	# Água fervendo: disco colado nas ondas, mais forte onde a lava encontra o mar.
	var ring_r := maxf(aabb.size.x, aabb.size.z) * 0.78
	var water_mat := ShaderMaterial.new()
	water_mat.shader = LAVA_WATER
	water_mat.render_priority = 1
	water_mat.set_shader_parameter("ring_radius", ring_r)
	var spots := PackedVector4Array()
	for e in ends.slice(0, 4):
		var w: Vector3 = root.global_transform * Vector3(e.x, 0.0, e.z)
		spots.append(Vector4(w.x, w.y, w.z, aabb.size.y * 0.22))
	water_mat.set_shader_parameter("hot_spots", spots)
	water_mat.set_shader_parameter("hot_count", spots.size())
	if world.get("ocean"):
		world.ocean.register_material(water_mat)
	var water := MeshInstance3D.new()
	water.name = "BoilingWater"
	water.mesh = _ring_mesh(ring_r, 16, 72)
	water.material_override = water_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.visibility_range_end = DRAW_DISTANCE
	root.add_child(water)
	item.water = water
	print("WORLD_DECOR vulcão: cratera=%s rios=%d" % [crater_pos.snapped(Vector3.ONE * 0.1), ends.size()])

## Mapa de alturas do modelo no espaço do item: o vértice mais alto de cada célula. Os modelos
## "clean" do Meshy são fechados por baixo e não têm fumaça/nuvem pintada, então o topo é o relevo.
func _height_grid(model: Node3D, aabb: AABB, grid: int) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(grid * grid)
	heights.fill(-INF)
	var root := model.get_parent() as Node3D
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		var xf := _node_transform(mi, root)
		for s in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			# Os originais têm milhões de vértices: uma amostra de ~200 mil basta para o relevo.
			var stride := maxi(1, verts.size() / 200000)
			for vi in range(0, verts.size(), stride):
				var p := xf * verts[vi]
				var i := clampi(int((p.x - aabb.position.x) / aabb.size.x * grid), 0, grid - 1)
				var j := clampi(int((p.z - aabb.position.z) / aabb.size.z * grid), 0, grid - 1)
				heights[j * grid + i] = maxf(heights[j * grid + i], p.y)
	# Células sem vértice: herdam dos vizinhos (algumas passadas) ou ficam no nível do mar.
	for pass_i in 3:
		var copy := heights.duplicate()
		for j in grid:
			for i in grid:
				if heights[j * grid + i] > -INF:
					continue
				var sum := 0.0
				var n := 0
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var ni: int = i + d.x
					var nj: int = j + d.y
					if ni >= 0 and nj >= 0 and ni < grid and nj < grid and heights[nj * grid + ni] > -INF:
						sum += heights[nj * grid + ni]
						n += 1
				if n >= 2:
					copy[j * grid + i] = sum / n
		heights = copy
	for k in heights.size():
		if heights[k] == -INF:
			heights[k] = -1.0
	return heights

## Desce da cratera pelo caminho mais íngreme, preferindo seguir o rumo inicial (rios separados),
## até chegar ao nível do mar ou à borda do modelo.
func _lava_path(heights: PackedFloat32Array, grid: int, start: Vector2i, bearing: Vector2) -> Array[Vector2i]:
	var path: Array[Vector2i] = [start]
	var cur := start
	var visited := {start: true}
	for step in grid * 2:
		var here := heights[cur.y * grid + cur.x]
		if here < 0.6:
			break
		var best := Vector2i(-1, -1)
		var best_score := INF
		for dj in [-1, 0, 1]:
			for di in [-1, 0, 1]:
				if di == 0 and dj == 0:
					continue
				var n := Vector2i(cur.x + di, cur.y + dj)
				if n.x < 0 or n.y < 0 or n.x >= grid or n.y >= grid or visited.has(n):
					continue
				var drop := heights[n.y * grid + n.x] - here
				var dirv := Vector2(di, dj).normalized()
				# Desce (drop negativo é bom), segue o rumo e não volta para dentro.
				var score := drop * 1.0 - dirv.dot(bearing) * 1.6 + lava_rng.randf() * 0.3
				if drop > 1.5:
					score += 50.0
				if score < best_score:
					best_score = score
					best = n
		if best.x < 0:
			break
		visited[best] = true
		path.append(best)
		cur = best
		if cur.x == 0 or cur.y == 0 or cur.x == grid - 1 or cur.y == grid - 1:
			break
	return path

func _chaikin(points: Array[Vector3]) -> Array[Vector3]:
	var out: Array[Vector3] = [points[0]]
	for i in points.size() - 1:
		out.append(points[i].lerp(points[i + 1], 0.25))
		out.append(points[i].lerp(points[i + 1], 0.75))
	out.append(points[points.size() - 1])
	return out

## Fita ao longo dos pontos (largura da cratera até o mar); UV.y em metros.
func _ribbon(points: Array[Vector3], width_top: float, width_bottom: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	var side := Vector3.RIGHT
	for i in points.size():
		var prev := points[maxi(i - 1, 0)]
		var next := points[mini(i + 1, points.size() - 1)]
		var tangent := next - prev
		var flat := Vector3(tangent.x, 0.0, tangent.z)
		if flat.length() > 0.01:
			side = flat.normalized().cross(Vector3.UP)
		if i > 0:
			along += points[i].distance_to(points[i - 1])
		var t := float(i) / (points.size() - 1)
		var w := lerpf(width_top, width_bottom, t) * (0.85 + 0.3 * sin(i * 1.7))
		for s in [0, 1]:
			tool.set_uv(Vector2(s, along))
			tool.set_normal(Vector3.UP)
			tool.add_vertex(points[i] + side * (s - 0.5) * w)
	for i in points.size() - 1:
		var v := i * 2
		for k in [v, v + 1, v + 2, v + 1, v + 3, v + 2]:
			tool.add_index(k)
	return tool.commit()

func _ring_mesh(radius: float, rings: int, segments: int) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in rings + 1:
		var r := float(j) / rings
		for i in segments + 1:
			var a := TAU * i / segments
			tool.set_uv(Vector2(float(i) / segments, r))
			tool.set_normal(Vector3.UP)
			tool.add_vertex(Vector3(cos(a) * r * radius, 0.0, sin(a) * r * radius))
	var row := segments + 1
	for j in rings:
		for i in segments:
			var v := j * row + i
			for k in [v, v + 1, v + row, v + 1, v + row + 1, v + row]:
				tool.add_index(k)
	return tool.commit()

## Fumaça do vulcão: poucos tufos grandes subindo devagar (barato), alaranjados na boca.
func _volcano_smoke(at: Vector3) -> CPUParticles3D:
	var smoke := _puffs(30, 14.0, Vector2(2.0, 3.5), Vector2(9.0, 18.0),
		[Color(0.95, 0.45, 0.18, 0.0), Color(0.3, 0.27, 0.26, 0.6), Color(0.55, 0.55, 0.56, 0.0)])
	smoke.name = "Smoke"
	smoke.position = at + Vector3.UP * 1.5
	return smoke

## Vapor onde a lava entra no mar.
func _steam(at: Vector3) -> CPUParticles3D:
	var steam := _puffs(8, 4.0, Vector2(1.5, 2.5), Vector2(2.0, 5.0),
		[Color(1, 1, 1, 0.0), Color(0.95, 0.93, 0.92, 0.45), Color(1, 1, 1, 0.0)])
	steam.name = "Steam"
	steam.position = at + Vector3.UP * 0.5
	return steam

## Tufos subindo (CPUParticles3D: as GPUParticles3D não apareciam no renderer de compatibilidade).
func _puffs(amount: int, lifetime: float, speed: Vector2, size: Vector2, colors: Array) -> CPUParticles3D:
	var puffs := CPUParticles3D.new()
	puffs.amount = amount
	puffs.lifetime = lifetime
	puffs.preprocess = lifetime
	puffs.local_coords = false
	puffs.direction = Vector3.UP
	puffs.spread = 12.0
	puffs.initial_velocity_min = speed.x
	puffs.initial_velocity_max = speed.y
	puffs.gravity = Vector3.ZERO
	# O tamanho vai na própria malha: no renderer de compatibilidade a escala por partícula não
	# chega no billboard (os tufos viravam pontinhos). A escala só varia um pouco em volta disso.
	var average := (size.x + size.y) * 0.5
	puffs.scale_amount_min = size.x / average
	puffs.scale_amount_max = size.y / average
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.0))
	# A curva do CPUParticles3D vai de 0 a 1: o crescimento extra vem da escala máxima.
	puffs.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	fade.colors = PackedColorArray(colors)
	puffs.color_ramp = fade
	var puff := QuadMesh.new()
	puff.size = Vector2.ONE * average
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _soft_texture(0.8)
	puff.material = mat
	puffs.mesh = puff
	return puffs

# --- Tartaruga --------------------------------------------------------------------

func _place_turtle() -> void:
	if not scenes.has("turtle_island"):
		return
	var item := _spawn("turtle_island", _turtle_point(0.0), 0.0)
	item.sector = Sector.WEST
	turtle = {"item": item, "angle": 0.0, "time": 0.0}
	var model := (item.root as Node3D).get_child(0) as Node3D
	# Linha d'água na altura das nadadeiras (z -0,32 do modelo, origem no centro da caixa): casco e ilha
	# inteiros para fora, nadadeiras raspando a superfície, pescoço e cabeça fora (o mar em volta é
	# calmo, calm_spots), como no conceito References/2D/Meshy_AI_stone-turtle-swimming-rig-concept.png.
	model.position.y = TURTLE_WATER_Z * model.scale.x
	# Inclinada para a frente: a cabeça chega mais perto da água (as traseiras continuam na água).
	model.rotation.x = -deg_to_rad(TURTLE_PITCH_DEG)
	_build_turtle_fx(model)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player and player.has_animation("Swim"):
		player.get_animation("Swim").loop_mode = Animation.LOOP_LINEAR
		player.play("Swim")
	_add_turtle_waterfalls(model)
	# Colisão pelo contorno da tartaruga como ela fica no mar (afundada e inclinada acima, na pose do
	# nado): o contorno geral do _spawn era medido antes disso e deixava buracos (Pedro, 2026-10-18).
	get_tree().create_timer(0.6).timeout.connect(func():
		var body := (item.root as Node3D).get_node_or_null("Footprint") as StaticBody3D
		if body and is_instance_valid(model):
			BeastOutline.fill(body, BeastOutline.radii(model, item.root), -3.0, FOOT_TOP))

## Cachoeiras saindo das duas bicas do casco (os toquinhos do aro nos lados, x = ±0,94 no espaço do
## casco, na altura dos anéis): presas no nó Shell, acompanham o balanço da tartaruga.
func _add_turtle_waterfalls(model: Node) -> void:
	var shell := model.find_child("Shell", true, false) as Node3D
	if shell == null:
		return
	var unit := 1.0 / maxf((shell.global_transform.basis.get_scale().x), 0.0001)
	for side in [-1.0, 1.0]:
		var fall := GPUParticles3D.new()
		fall.name = "TurtleWaterfall"
		fall.position = Vector3(0.97 * side, -0.2, 0.0)
		fall.scale = Vector3.ONE * unit
		fall.amount = 90
		fall.lifetime = 1.6
		fall.local_coords = false
		fall.visibility_aabb = AABB(Vector3(-30, -40, -30), Vector3(60, 60, 60))
		var motion := ParticleProcessMaterial.new()
		motion.direction = Vector3(side, -0.15, 0.0)
		motion.spread = 6.0
		motion.initial_velocity_min = 2.4
		motion.initial_velocity_max = 3.2
		motion.gravity = Vector3(0, -9.8, 0)
		motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		motion.emission_sphere_radius = 0.6
		motion.scale_min = 0.8
		motion.scale_max = 1.4
		var fade := Gradient.new()
		fade.set_color(0, Color(0.85, 0.95, 1.0, 0.9))
		fade.set_color(1, Color(0.7, 0.9, 1.0, 0.0))
		var ramp := GradientTexture1D.new()
		ramp.gradient = fade
		motion.color_ramp = ramp
		fall.process_material = motion
		var drop := QuadMesh.new()
		drop.size = Vector2(0.9, 1.6)
		var paint := StandardMaterial3D.new()
		paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		paint.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		paint.vertex_color_use_as_albedo = true
		var soft := GradientTexture2D.new()
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		soft.gradient = g
		soft.fill = GradientTexture2D.FILL_RADIAL
		soft.fill_from = Vector2(0.5, 0.5)
		soft.fill_to = Vector2(0.5, 0.0)
		paint.albedo_texture = soft
		drop.material = paint
		fall.draw_pass_1 = drop
		shell.add_child(fall)

## Ponto do circuito da tartaruga (elipse em lat/lon dentro do Oeste) no ângulo a (rad).
func _turtle_point(a: float) -> Vector3:
	return _lat_lon(TURTLE_CENTER.x + TURTLE_RADII.x * sin(a), TURTLE_CENTER.y + TURTLE_RADII.y * cos(a))

func _turtle_distance(p: Vector3) -> float:
	var d := INF
	for n in 72:
		d = minf(d, p.angle_to(_turtle_point(TAU * n / 72.0)) * planet_radius)
	return d

## A tartaruga dá a volta no circuito a TURTLE_SPEED m/s (sentido anti-horário visto de fora).
func _update_turtle(delta: float) -> void:
	if turtle.is_empty():
		return
	turtle.time = float(turtle.time) + delta
	var a := float(turtle.angle)
	var step := _turtle_point(a).angle_to(_turtle_point(a + 0.01)) * planet_radius / 0.01
	turtle.angle = fposmod(a + TURTLE_SPEED * delta / maxf(step, 1.0), TAU)
	var dir := _turtle_point(float(turtle.angle))
	var next := _turtle_point(float(turtle.angle) + 0.02)
	var forward := (next - dir).slide(dir).normalized()
	var root: Node3D = (turtle.item as Dictionary).root
	var bob := sin(float(turtle.time) * 0.45) * 0.35
	var basis := Basis.looking_at(forward, dir).rotated(forward, sin(float(turtle.time) * 0.3) * 0.02)
	root.global_transform = Transform3D(basis, dir * (planet_radius + bob))
	(turtle.item as Dictionary).dir = dir
	_update_turtle_fx(root, forward, dir)

## Efeitos de água da tartaruga, como os do barco: lâmina d'água leve na frente do casco (a mesma
## BowWaveSheet do barco, esticada pelo hull_scale) e, a cada batida das nadadeiras na água, gotas
## (water_drop, as mesmas do barco) e uma ondulação no mar.
## Quanto a tartaruga é maior que o tamanho em que os efeitos foram acertados.
func _turtle_fx_k() -> float:
	return float(MODELS["turtle_island"][1]) / TURTLE_FX_SIZE

func _build_turtle_fx(model: Node3D) -> void:
	var fx := _turtle_fx_k()
	turtle.skeleton = model.find_child("Skeleton3D", true, false)
	turtle.scale = model.scale.x
	turtle.sheets = []
	for side in [-1.0, 1.0]:
		var mesh := MeshInstance3D.new()
		mesh.name = "TurtleBowSheet"
		var grid := PlaneMesh.new()
		grid.subdivide_width = 62
		grid.subdivide_depth = 22
		mesh.mesh = grid
		mesh.top_level = true
		mesh.custom_aabb = AABB(Vector3(-60, -20, -60), Vector3(120, 40, 120))
		mesh.extra_cull_margin = 60.0
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = load("res://Shaders/BowWaveSheet.gdshader")
		material.set_shader_parameter("side", side)
		material.set_shader_parameter("foam_pattern", load("res://Shaders/wind_waker_foam.png"))
		material.set_shader_parameter("ocean_radius", planet_radius)
		# Frente do casco a ~23 m do centro do casco e ~22 m de largura de cada lado.
		material.set_shader_parameter("hull_scale", Vector2(11.5, 20.0) * fx)
		material.set_shader_parameter("curl_scale", 3.0 * fx)
		material.set_shader_parameter("sheet_scale", 0.6)
		material.set_shader_parameter("boat_speed", 3.0)
		material.set_shader_parameter("contact", 1.0)
		mesh.material_override = material
		add_child(mesh)
		turtle.sheets.append(material)
	var drop_mesh := QuadMesh.new()
	drop_mesh.size = Vector2(1.2, 1.2) * fx
	var drop_material := ShaderMaterial.new()
	drop_material.shader = load("res://Shaders/water_drop.gdshader")
	drop_mesh.material = drop_material
	turtle.drop_material = drop_material
	turtle.flippers = []
	for pair in TURTLE_FLIPPERS:
		var emitter := GPUParticles3D.new()
		emitter.name = "TurtleSplash"
		emitter.top_level = true
		emitter.amount = 48
		emitter.lifetime = 1.3
		emitter.one_shot = true
		emitter.explosiveness = 0.85
		emitter.emitting = false
		emitter.local_coords = false
		emitter.visibility_aabb = AABB(Vector3(-15, -10, -15) * fx, Vector3(30, 25, 30) * fx)
		var motion := ParticleProcessMaterial.new()
		motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		motion.emission_sphere_radius = 2.5 * fx
		motion.direction = Vector3.UP
		motion.spread = 40.0
		motion.initial_velocity_min = 3.5 * sqrt(fx)
		motion.initial_velocity_max = 7.0 * sqrt(fx)
		motion.gravity = Vector3(0, -9.8, 0)
		motion.scale_min = 0.6
		motion.scale_max = 1.5
		emitter.process_material = motion
		emitter.draw_pass_1 = drop_mesh
		add_child(emitter)
		turtle.flippers.append({"tip": pair[0], "base": pair[1], "emitter": emitter, "under": false})

func _update_turtle_fx(root: Node3D, forward: Vector3, dir: Vector3) -> void:
	if not turtle.has("sheets"):
		return
	var ocean: Node = world.ocean
	var up := dir
	var right := forward.cross(up).normalized()
	var k := float(turtle.scale)
	# Centro do casco: 0,19 (unidades do modelo) atrás da origem da tartaruga.
	var shell_center: Vector3 = root.global_position - forward * 0.19 * k
	var fx := _turtle_fx_k()
	var front: Vector3 = shell_center + forward * 23.0 * fx
	var back: Vector3 = shell_center - forward * 12.0 * fx
	var daylight: float = 1.0 - (float(world.clock.night_at(root.global_position)) if world.get("clock") else 0.0)
	for material in turtle.sheets:
		var m := material as ShaderMaterial
		m.set_shader_parameter("boat_position", shell_center)
		m.set_shader_parameter("boat_forward", forward)
		m.set_shader_parameter("boat_right", right)
		m.set_shader_parameter("water_height_front", float(ocean.height_at(front)))
		m.set_shader_parameter("water_height_back", float(ocean.height_at(back)))
		m.set_shader_parameter("hull_height", float(ocean.height_at(front)) + 6.0 * fx)
		m.set_shader_parameter("daylight", daylight)
	(turtle.drop_material as ShaderMaterial).set_shader_parameter("daylight", daylight)
	var skeleton := turtle.skeleton as Skeleton3D
	if skeleton == null:
		return
	for f in turtle.flippers:
		var tip_index := skeleton.find_bone(f.tip)
		var base_index := skeleton.find_bone(f.base)
		if tip_index < 0 or base_index < 0:
			continue
		var tip_origin := skeleton.global_transform * skeleton.get_bone_global_pose(tip_index).origin
		var base_origin := skeleton.global_transform * skeleton.get_bone_global_pose(base_index).origin
		# Ponta da nadadeira ≈ início do último osso + o mesmo comprimento do osso anterior.
		var tip := tip_origin + (tip_origin - base_origin)
		var water := float(ocean.height_at(tip))
		var under := tip.length() - planet_radius < water + 0.3
		if under != bool(f.under):
			# Entrou na água: borrifo forte e ondulação. Saiu: a água escorrendo da nadadeira (borrifo
			# menor, mais para cima) e uma ondulação mais fraca.
			var emitter := f.emitter as GPUParticles3D
			var motion := emitter.process_material as ParticleProcessMaterial
			emitter.global_position = tip.normalized() * (planet_radius + water + 0.4)
			var outward := (tip - root.global_position).slide(up).normalized()
			motion.direction = (up + outward * (0.5 if under else 0.15)).normalized()
			motion.gravity = -up * 9.8
			emitter.amount_ratio = 1.0 if under else 0.55
			emitter.restart()
			if ocean.has_method("touch"):
				ocean.touch(tip, 0.9 if under else 0.45, 4.0 * fx)
		f.under = under

func _lat_lon(lat_deg: float, lon_deg: float) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	return Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)).normalized()

# --- Animação ----------------------------------------------------------------------

func _process(delta: float) -> void:
	if world == null or world.ship == null:
		return
	_update_turtle(delta)
	if streaming or not pending.is_empty():
		_attach_pending(delta)
	if not seas_tinted:
		_tint_seas()
	if not beasts_glowing:
		_glow_beasts()
	var ship_pos: Vector3 = world.ship.global_position
	var t := Time.get_ticks_msec() * 0.001
	_update_biome(ship_pos)
	if limit_shadows:
		_update_shadows(ship_pos)
	for item in items:
		var dir: Vector3 = item.dir
		var dist := ship_pos.distance_to(dir * planet_radius)
		# As lanternas do bioma ficam longe umas das outras (marcam a borda): animam de mais longe.
		var reach := DRAW_DISTANCE if float(item.hover) > 0.0 or item.kind in WIDE_ANIMATION else FLOAT_DISTANCE
		var player: AnimationPlayer = item.player
		if player:
			player.active = dist < reach
		if (item.float or float(item.hover) > 0.0) and dist < reach:
			_ride_wave(item)
		var light: OmniLight3D = item.light
		if light:
			var night: float = world.clock.night_at(dir * planet_radius)
			if float(item.hover) > 0.0:
				# Lanternas espectrais: só à noite, luz dentro da lanterna; só as próximas iluminam.
				light.visible = night > 0.3 and dist < 170.0
				light.light_energy = smoothstep(0.3, 0.8, night) * 2.2 * (0.85 + 0.15 * sin(t * 2.2 + float(item.phase)))
			else:
				light.visible = night > 0.3 and dist < 300.0
				if light.visible:
					var flicker := 1.0 + 0.15 * sin(t * (6.0 if item.kind in ["basalt_caldera", "volcanic_crag"] else 2.2) + float(item.phase))
					light.light_energy = smoothstep(0.3, 0.8, night) * 2.4 * flicker
		var glow: Node3D = item.get("glow")
		if glow:
			glow.visible = world.clock.night_at(dir * planet_radius) > 0.3 and dist < DRAW_DISTANCE
		var wisps: Node3D = item.get("wisps")
		if wisps:
			wisps.visible = world.clock.night_at(dir * planet_radius) > 0.35 and dist < 300.0
		var flame: Node3D = item.get("flame")
		if flame:
			flame.visible = dist < DRAW_DISTANCE
		var smoke: CPUParticles3D = item.smoke
		if smoke:
			# Sempre emitindo (pré-aquecidas): partícula parada vira disco no renderer de compatibilidade.
			smoke.visible = dist < 420.0
			for puff in item.get("steam", []):
				(puff as CPUParticles3D).visible = dist < 300.0

## Liga a sombra de um modelo alto só se ele está perto do barco (na tela) e o sol, ali, está alto o
## bastante para a sombra caber em SHADOW_MAX_LENGTH m: h / tan(elevação) <= limite.
func _update_shadows(ship_pos: Vector3) -> void:
	var sun: Vector3 = world.clock.sun_direction
	for item in items:
		if not item.get("casts", false):
			continue
		var dir: Vector3 = item.dir
		var on := false
		if ship_pos.distance_to(dir * planet_radius) < SHADOW_REACH + float(item.radius):
			var elevation := asin(clampf(dir.dot(sun), -1.0, 1.0))
			on = elevation > 0.02 and float(item.tall) / tan(elevation) <= SHADOW_MAX_LENGTH
		if on == bool(item.shadow_on):
			continue
		item.shadow_on = on
		var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if item.model == null:
			continue
		for mesh in (item.model as Node3D).find_children("*", "MeshInstance3D", true, false):
			(mesh as GeometryInstance3D).cast_shadow = mode

## Boia/caixas na onda e lanternas pairando acima dela: só a altura vem da onda; o balanço,
## o giro e o sino vêm da animação do Blender.
func _ride_wave(item: Dictionary) -> void:
	var root: Node3D = item.root
	var dir: Vector3 = item.dir
	var surface: Vector3 = world.ocean.surface_at(dir * planet_radius)
	var basis := _surface_basis(dir).rotated(dir, float(item.yaw))
	root.global_transform = Transform3D(basis, surface + dir * float(item.hover))

## Setor atual (sem aviso na tela: Pedro vai fazer telas próprias); névoa verde no Mar Sombrio;
## runas à noite.
func _update_biome(ship_pos: Vector3) -> void:
	var sector := sector_of(ship_pos)
	if sector != current_sector:
		if current_sector != -1:
			print("WORLD_DECOR setor %s" % sector_name(sector))
		current_sector = sector
	var inside := is_in_ghost_biome(ship_pos, 40.0 if in_ghost_biome else 0.0)
	in_ghost_biome = inside
	if mist:
		mist.visible = inside
		if inside:
			var up := ship_pos.normalized()
			mist.global_transform = Transform3D(_surface_basis(up), up * (planet_radius + 1.0))
	var night: float = world.clock.night_at(ship_pos)
	for material in rune_materials:
		material.set_shader_parameter("night", night)

# --- Carregamento por proximidade (site) --------------------------------------------

func _cached(kind: String) -> bool:
	return kind_cache.get("kinds", {}).has(kind)

func _has_kind(kind: String) -> bool:
	return scenes.has(kind) or _cached(kind)

func _model_path(kind: String) -> String:
	if MODELS.has(kind):
		return ASSETS + String(MODELS[kind][0])
	return DERIVED + kind + ".glb"

func _read_kind_cache() -> Dictionary:
	if not FileAccess.file_exists(KIND_CACHE):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(KIND_CACHE))
	return parsed if parsed is Dictionary and parsed.has("kinds") else {}

## Medidas de todos os modelos (com tudo carregado: editor ou Tests/bake_world_kinds.gd) e o pacote
## de cada um: o setor onde ele aparece, "shared" se aparece em mais de um, fora os CORE_KINDS.
func kind_cache_data() -> Dictionary:
	var sectors := {}
	for item in items:
		var list: Array = sectors.get(item.kind, [])
		if not list.has(int(item.sector)):
			list.append(int(item.sector))
		sectors[item.kind] = list
	var pack_names := {Sector.NORTH: "north", Sector.EAST: "east", Sector.SOUTH: "south", Sector.WEST: "west"}
	var kinds := {}
	for kind in scenes:
		var b := _raw_bounds(kind)
		var entry := {"path": _model_path(kind), "bounds": [b.position.x, b.position.y, b.position.z, b.size.x, b.size.y, b.size.z],
			"idle": bool(kind_idle.get(kind, false))}
		if footprint_cache.has(kind):
			var foot := []
			for hull in footprint_cache[kind]:
				var flat := []
				for q in hull:
					flat.append(snappedf(q.x, 0.0001))
					flat.append(snappedf(q.y, 0.0001))
				foot.append(flat)
			entry.foot = foot
		var used: Array = sectors.get(kind, [])
		if kind in CORE_KINDS or used.is_empty():
			entry.pack = ""
		else:
			entry.pack = pack_names[used[0]] if used.size() == 1 else "shared"
		kinds[kind] = entry
	return {"kinds": kinds, "new_kinds": new_kinds}

func save_kind_cache() -> bool:
	var text := JSON.stringify(kind_cache_data(), "\t", true)
	if FileAccess.file_exists(KIND_CACHE) and FileAccess.get_file_as_string(KIND_CACHE) == text:
		return false
	var file := FileAccess.open(KIND_CACHE, FileAccess.WRITE)
	file.store_string(text)
	return true

## Pacotes dos setores (só no site): o do setor do barco e o "shared" primeiro, depois os outros pela
## distância.
func _start_packs() -> void:
	var test_packs := false
	for arg in OS.get_cmdline_user_args():
		test_packs = test_packs or arg.begins_with("--packs=")
	if not (OS.has_feature("web") or test_packs) or asset_packs != null:
		return
	asset_packs = AssetPacks.new()
	asset_packs.name = "AssetPacks"
	add_child(asset_packs)
	asset_packs.pack_loaded.connect(_on_pack_loaded)
	# Um pacote por modelo: _attach_pending diz quais pedir (os perto do barco, o mais perto primeiro).
	asset_packs.start([])

func _anchor(sector: int) -> Vector3:
	var a: Vector2 = BIOMES[sector].anchor
	return _lat_lon(a.x, a.y)

func _on_pack_loaded(_pack: String) -> void:
	# Os modelos são pedidos conforme o barco chega perto (_attach_pending).
	stream_timer = 0.0

## Sem threads (build web normal) o carregamento em segundo plano não anda: carrega direto.
func _sync_loads() -> bool:
	return OS.has_feature("web") and not OS.has_feature("threads")

func _in_range(item: Dictionary, ship_pos: Vector3, margin: float) -> bool:
	return ship_pos.distance_to((item.dir as Vector3) * planet_radius) < load_range + margin + float(item.radius)

## Tira o modelo da cena (longe do barco); o item continua com colisão, luz e efeitos.
func _detach_model(item: Dictionary) -> void:
	for material in item.get("rune_mats", []):
		rune_materials.erase(material)
	item.erase("rune_mats")
	(item.model as Node3D).queue_free()
	item.model = null
	item.player = null
	pending.append(item)

## Carga por proximidade: pede o modelo dos itens que entraram no raio, monta poucos por quadro (os
## mais perto primeiro), tira os que saíram e solta da memória as cenas sem nenhum item perto.
func _attach_pending(delta: float) -> void:
	var ship_pos: Vector3 = world.ship.global_position
	# Site: nada de baixar/montar modelos antes de o mundo rodar liso (a página avisa; main_world
	# ready_reported) e mais STREAM_SETTLE s: o leme fica livre primeiro (Pedro, 2026-10-17: com tudo
	# carregando junto, o leme só respondia aos 62 s).
	if streaming:
		if not bool(world.get("ready_reported")):
			return
		settle_left -= delta
		if settle_left > 0.0:
			return
	stream_timer -= delta
	if stream_timer <= 0.0:
		stream_timer = 0.25
		var wanted := {}
		for item in pending:
			if not streaming or _in_range(item, ship_pos, 0.0):
				wanted[item.kind] = true
		if streaming:
			for item in items:
				if item.model != null and not (item.kind in CORE_KINDS) and not _in_range(item, ship_pos, LOAD_MARGIN):
					_detach_model(item)
				elif item.model != null:
					wanted[item.kind] = true
			for kind in scenes.keys():
				if not wanted.has(kind) and not (kind in CORE_KINDS):
					scenes.erase(kind)
		# Pacotes por modelo (site): pede os que estão no raio de carga + a folga, o mais perto primeiro.
		if asset_packs != null:
			var nearest := {}
			for item in items:
				if item.kind in CORE_KINDS:
					continue
				var d := ship_pos.distance_to((item.dir as Vector3) * planet_radius) - float(item.radius)
				if d < load_range + PREFETCH:
					nearest[item.kind] = minf(float(nearest.get(item.kind, INF)), d)
			var order: Array = nearest.keys()
			order.sort_custom(func(a: String, b: String) -> bool: return float(nearest[a]) < float(nearest[b]))
			asset_packs.want(order)
		for kind in wanted:
			var path := _model_path(kind)
			if not scenes.has(kind) and not loading.has(path) and ResourceLoader.exists(path):
				# Build web sem threads: lá carrega um modelo por quadro, logo abaixo. Com threads
				# (Web/build.ps1 -Threads) carrega em segundo plano, sem travar o quadro.
				if not _sync_loads():
					ResourceLoader.load_threaded_request(path)
				loading[path] = kind
	if _sync_loads():
		for path in loading.keys():
			scenes[loading[path]] = load(path)
			loading.erase(path)
			break
	else:
		for path in loading.keys():
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				scenes[loading[path]] = ResourceLoader.load_threaded_get(path)
				loading.erase(path)
			elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_warning("WorldDecor: não carregou %s" % path)
				loading.erase(path)
	var budget := ATTACH_PER_FRAME
	# Web sem threads: montar um modelo trava o quadro; um a cada ATTACH_GAP s, não dois por quadro.
	if _sync_loads():
		attach_wait -= delta
		budget = 1 if attach_wait <= 0.0 else 0
	var ready: Array = pending.filter(func(item: Dictionary) -> bool:
		return scenes.has(item.kind) and (not streaming or _in_range(item, ship_pos, 0.0)))
	ready.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return ship_pos.distance_squared_to(a.dir * planet_radius) < ship_pos.distance_squared_to(b.dir * planet_radius))
	for item in ready:
		if budget <= 0:
			break
		budget -= 1
		pending.erase(item)
		_dress_model(item, (scenes[item.kind] as PackedScene).instantiate())
		attach_wait = ATTACH_GAP
	# Página (?medir): os pacotes chegaram e tudo o que está no raio já está no lugar.
	if not first_near_taken:
		first_near_taken = true
		first_near = pending.filter(func(item: Dictionary) -> bool: return not streaming or _in_range(item, ship_pos, 0.0))
	var near_waiting := first_near.any(func(item: Dictionary) -> bool: return pending.has(item))
	if not sectors_marked and not near_waiting:
		sectors_marked = true
		print("WORLD_DECOR modelos no raio de carga no lugar (%d itens perto quando o mundo abriu)" % first_near.size())
		if OS.has_feature("web"):
			JavaScriptBridge.eval("window.__portfolioMark && window.__portfolioMark('sectorsPlaced')", true)
