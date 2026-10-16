extends Control

## Desenho do mapa do mundo (Tests/world_map_render.gd preenche `data`): três painéis — a faixa do
## equador (Leste e Oeste, lat/lon) e as duas calotas (Norte e Sul, vistas de cima do polo) — com
## as 5 ilhas, as rotas, os biomas, cada item com nome e onde nada aparece no horizonte.

var data := {}

const PPD := 6.4            # pixels por grau
const BAND_LAT := 32.0      # a faixa vai de -32 a 32
const CAP_COLAT := 62.0     # as calotas vão do polo até 28° de latitude
const BAND := Rect2(40, 90, 360 * PPD, 2 * 32 * PPD)
const CAP_N := Vector2(460, 1000)
const CAP_S := Vector2(1340, 1000)
const LEGEND := Vector2(1800, 600)

const SECTOR_TINT := [Color("2f4a6b"), Color("2f5d55"), Color("2a2140"), Color("1f5a6e")]
const SECTOR_INK := [Color("9fd3ff"), Color("ffd27a"), Color("c49bff"), Color("7ff0d0")]
## Marcos de borda de cada bioma (pontos pequenos).
const MARKER_COLORS := {"cargo_crates": Color("c9925a"), "bell_buoy": Color("ff5a4e"), "spectral_lantern": Color("6dffb0"), "coral_reef": Color("ff7ad9")}

const NAMES := {
	"shattered_runed_bastion": "Bastião rúnico", "collapsed_watchtower": "Torre desabada",
	"ruined_sunken_pier": "Píer afundado", "broken_megalithic_quay": "Cais megalítico",
	"cargo_crates": "Caixas", "ocean_stonehenge": "Stonehenge", "cyclopean_stepped_cairn": "Marco escalonado",
	"abandoned_stilt_waterworks": "Palafitas", "megalithic_dolmen_ring": "Anel de dólmens",
	"bell_buoy": "Boia de sino", "basalt_caldera": "Caldeira", "volcanic_crag": "Rochedo vulcânico",
	"leviathan_jaw_arch": "Arco da mandíbula", "ship_graveyard": "Cemitério de navios",
	"floating_basalt_chain": "Monólito acorrentado", "obsidian_rib_spire": "Árvore negra",
	"spectral_lantern": "Lanterna", "limestone_coral_needle": "Agulha de calcário",
	"low_reef_arch": "Arco de recife", "stepped_basalt_reef": "Recife escalonado",
	"twin_sea_pinnacles": "Pináculos gêmeos", "turtle_island": "Tartaruga", "palm_atoll": "Atol",
	"coral_reef": "Coral", "runestone_citadel": "Cidadela das Runas", "split_monolith_runes": "Monólito rúnico",
	"half_sunken_lighthouse": "Farol antigo", "driftwood_merchant": "Vila mercante", "stilt_lookout_post": "Posto de vigia",
	"shipwreck_chest": "Naufrágio", "kraken_maw_teeth": "Bocarra do Kraken", "coral_paradise": "Paraíso de coral",
	"mushroom_grotto": "Gruta dos cogumelos", "dragon_horns_reef": "Recife chifre-de-dragão", "reef_rocks_cluster": "Rochas",
	"sea_stack_spire": "Agulha de pedra", "dark_needle_rocks": "Agulhas escuras", "balancing_tor_rock": "Pedra equilibrada",
}
const BEAST_NAMES := {"turtle": "Tartaruga gigante", "timber_whale": "Baleia de madeira", "abyssal_behemoth": "Behemoth abissal", "abyssal_obsidian": "Colosso de obsidiana"}
const BEAST_COLORS := {"turtle": Color("7ff0d0"), "timber_whale": Color("ffb35c"), "abyssal_behemoth": Color("ff6b8b"), "abyssal_obsidian": Color("b78cff")}

func _font() -> Font:
	return ThemeDB.fallback_font

func _text(pos: Vector2, s: String, size: int, color: Color, outline := true) -> void:
	if outline:
		draw_string_outline(_font(), pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.85))
	draw_string(_font(), pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

## Projeção: painel (0 faixa, 1 Norte, 2 Sul) e ponto, ou null se cai fora do painel.
func _proj(panel: int, lat: float, lon: float) -> Variant:
	if panel == 0:
		if absf(lat) > BAND_LAT:
			return null
		return Vector2(BAND.position.x + lon * PPD, BAND.position.y + (BAND_LAT - lat) * PPD)
	var colat := 90.0 - lat if panel == 1 else 90.0 + lat
	if colat > CAP_COLAT:
		return null
	var center := CAP_N if panel == 1 else CAP_S
	var a := deg_to_rad(lon)
	var sx := 1.0 if panel == 1 else -1.0
	return center + Vector2(sin(a) * sx, cos(a)) * colat * PPD

func _panels(lat: float) -> Array:
	var list := []
	if absf(lat) <= BAND_LAT:
		list.append(0)
	if lat >= 90.0 - CAP_COLAT:
		list.append(1)
	if lat <= -(90.0 - CAP_COLAT):
		list.append(2)
	return list

func _draw() -> void:
	if data.is_empty():
		return
	# Desenho em 2400×1420 (coordenadas fixas), escalado para o tamanho lógico da janela.
	draw_rect(Rect2(Vector2.ZERO, size), Color("0d1622"))
	draw_set_transform(Vector2.ZERO, 0.0, size / Vector2(2400, 1420))
	_text(Vector2(40, 50), "Mapa do mundo — 4 biomas, rotas, ilhas e todos os itens (planeta R = 800 m; 1° ≈ 14 m)", 30, Color.WHITE)
	_text(Vector2(40, 80), "Hachurado vermelho: dali o barco não vê nada no horizonte (olho a %d m; um item de altura H aparece até √(2R·olho)+√(2R·H))" % int(data.eye), 18, Color("ffb0a0"))
	_background()
	_coverage()
	_grid()
	_routes()
	_paths()
	_islands()
	_items()
	_legend()

func _background() -> void:
	# Faixa: Leste (lon 0–180) e Oeste (180–360).
	draw_rect(Rect2(BAND.position, Vector2(180 * PPD, BAND.size.y)), SECTOR_TINT[1])
	draw_rect(Rect2(BAND.position + Vector2(180 * PPD, 0), Vector2(180 * PPD, BAND.size.y)), SECTOR_TINT[3])
	# Faixa: acima/abaixo de 30° já é Norte/Sul.
	var cut := (BAND_LAT - 30.0) * PPD
	draw_rect(Rect2(BAND.position, Vector2(BAND.size.x, cut)), SECTOR_TINT[0])
	draw_rect(Rect2(BAND.position + Vector2(0, BAND.size.y - cut), Vector2(BAND.size.x, cut)), SECTOR_TINT[2])
	for c in [[CAP_N, 0, 3], [CAP_S, 2, 1]]:
		draw_circle(c[0], CAP_COLAT * PPD, SECTOR_TINT[int(c[2])])
		draw_circle(c[0], 60.0 * PPD, SECTOR_TINT[int(c[1])])
	_text(BAND.position + Vector2(20 * PPD, 40), "LESTE · " + data.sector_names[1], 24, SECTOR_INK[1])
	_text(BAND.position + Vector2(200 * PPD, 40), "OESTE · " + data.sector_names[3], 24, SECTOR_INK[3])
	_text(CAP_N + Vector2(-400, -420), "NORTE · %s (vista de cima do polo norte)" % data.sector_names[0], 22, SECTOR_INK[0])
	_text(CAP_S + Vector2(-400, -420), "SUL · %s (vista de baixo do polo sul)" % data.sector_names[2], 22, SECTOR_INK[2])

func _coverage() -> void:
	for cell in data.coverage:
		if cell[3]:
			continue
		for panel in _panels(cell[0]):
			var p = _proj(panel, cell[0], cell[1])
			if p != null:
				var s: float = cell[2] * PPD
				draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), Color(1.0, 0.25, 0.2, 0.32))

func _grid() -> void:
	for lon in range(0, 361, 30):
		var x := BAND.position.x + lon * PPD
		draw_line(Vector2(x, BAND.position.y), Vector2(x, BAND.end.y), Color(1, 1, 1, 0.12), 1.0)
		_text(Vector2(x - 12, BAND.end.y + 22), "%d°" % lon, 15, Color(1, 1, 1, 0.6), false)
	for lat in [-30, 0, 30]:
		var y: float = BAND.position.y + (BAND_LAT - float(lat)) * PPD
		draw_line(Vector2(BAND.position.x, y), Vector2(BAND.end.x, y), Color(1, 1, 1, 0.25 if lat != 0 else 0.4), 1.0)
		_text(Vector2(BAND.end.x + 6, y + 5), "%d°" % lat, 15, Color(1, 1, 1, 0.6), false)
	for c in [CAP_N, CAP_S]:
		for colat in [30.0, 60.0]:
			draw_arc(c, colat * PPD, 0, TAU, 96, Color(1, 1, 1, 0.18), 1.0)
		for lon in range(0, 360, 30):
			var panel := 1 if c == CAP_N else 2
			var p = _proj(panel, 28.0 if panel == 1 else -28.0, lon)
			_text(p - Vector2(12, -4), "%d°" % lon, 14, Color(1, 1, 1, 0.5), false)
	# Escala: 100 m.
	var px: float = 100.0 / float(data.m_per_deg) * PPD
	draw_line(Vector2(1820, 560), Vector2(1820 + px, 560), Color.WHITE, 3.0)
	_text(Vector2(1820 + px + 8, 566), "100 m", 16, Color.WHITE)

func _polyline(points: Array, color: Color, width: float, dashed := false) -> void:
	for panel in 3:
		var prev = null
		var n := 0
		for ll in points:
			var p = _proj(panel, ll.x, ll.y)
			if p != null and prev != null and (p as Vector2).distance_to(prev) < 120.0:
				if not dashed or n % 2 == 0:
					draw_line(prev, p, color, width)
			prev = p
			n += 1

func _routes() -> void:
	for route in data.routes:
		_polyline(route, Color(1, 1, 1, 0.9), 3.0)
		_polyline(route, Color(1, 1, 1, 0.12), 2.0 * data.route_clear / data.m_per_deg * PPD)

func _paths() -> void:
	_polyline(data.shark_path, Color("9fd3ff"), 1.5, true)
	for name in data.beasts:
		var pts: Array = data.beasts[name]
		_polyline(pts + [pts[0]], BEAST_COLORS.get(name, Color.WHITE), 3.0, true)
		var ll: Vector2 = pts[pts.size() / 4]
		for panel in _panels(ll.x):
			var p = _proj(panel, ll.x, ll.y)
			if p != null:
				_text(p + Vector2(6, -6), BEAST_NAMES.get(name, name), 18, BEAST_COLORS.get(name, Color.WHITE))

func _islands() -> void:
	for isl in data.islands:
		for panel in _panels(isl.lat):
			var p = _proj(panel, isl.lat, isl.lon)
			if p == null:
				continue
			draw_arc(p, data.island_clear / data.m_per_deg * PPD, 0, TAU, 64, Color(1, 1, 1, 0.45), 1.5)
			draw_circle(p, maxf(isl.radius / data.m_per_deg * PPD, 6.0), Color("f2e2b6"))
			_text(p + Vector2(10, -10), "%s (%d m alt.)" % [isl.name, int(isl.height)], 22, Color("fff3c8"))

func _items() -> void:
	for it in data.items:
		var ink: Color = SECTOR_INK[int(it.sector)]
		for panel in _panels(it.lat):
			var p = _proj(panel, it.lat, it.lon)
			if p == null:
				continue
			var r := maxf(it.radius / data.m_per_deg * PPD, 3.0)
			if it.get("marker", false):
				draw_circle(p, 4.0, MARKER_COLORS.get(it.kind, Color.WHITE))
				draw_arc(p, 4.0, 0, TAU, 12, Color(0, 0, 0, 0.6), 1.0)
				continue
			draw_circle(p, r, Color(ink, 0.55))
			draw_arc(p, r, 0, TAU, 32, ink, 1.5)
			_text(p + Vector2(r + 4, 5), "%s %dm" % [NAMES.get(it.kind, it.kind), int(it.height)], 15, ink)

func _legend() -> void:
	var y: float = LEGEND.y
	_text(Vector2(LEGEND.x, y), "Legenda", 24, Color.WHITE)
	y += 34
	var rows := [
		[Color("f2e2b6"), "Ilha principal (círculo fino = 230 m livres)"],
		[Color.WHITE, "Rota entre as ilhas (faixa clara = corredor de 40 m)"],
		[Color("c9925a"), "Borda do Norte: caixas boiando"],
		[Color("ff5a4e"), "Borda do Leste: boias de sino"],
		[Color("6dffb0"), "Borda do Sul: lanternas espectrais"],
		[Color("ff7ad9"), "Borda do Oeste: corais coloridos"],
		[Color("7ff0d0"), "Tartaruga gigante (Oeste, tracejado)"],
		[Color("ffb35c"), "Baleia de madeira (Leste)"],
		[Color("ff6b8b"), "Behemoth abissal (Sul)"],
		[Color("b78cff"), "Colosso de obsidiana (Sul)"],
		[Color("9fd3ff"), "Patrulha da barbatana de tubarão (tracejado)"],
		[Color(1.0, 0.25, 0.2, 0.6), "Sem nada à vista no horizonte"],
	]
	for row in rows:
		draw_rect(Rect2(LEGEND.x, y - 14, 22, 16), row[0])
		_text(Vector2(LEGEND.x + 32, y), row[1], 17, Color.WHITE)
		y += 28
	y += 12
	_text(Vector2(LEGEND.x, y), "Cobertura do horizonte (mar com algo à vista):", 19, Color.WHITE)
	y += 28
	for line in data.stats:
		_text(Vector2(LEGEND.x, y), line, 17, Color("ffe6a0"))
		y += 26
	y += 12
	_text(Vector2(LEGEND.x, y), "Itens: %d (texto = nome e altura acima d'água)" % data.items.size(), 17, Color.WHITE)
