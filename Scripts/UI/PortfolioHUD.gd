extends CanvasLayer

## HUD do portfólio no estilo editorial do "Melon Jelly" (referência do usuário):
## texto direto sobre a cena, rótulos espaçados em caixa alta, números em mono,
## botões de contorno fino e só um painel de papel por vez. Tema pirata em papel
## de carta náutica, com tons de dia e de noite (HudTheme).

signal free_sail_pressed
signal island_pressed(index: int)
signal time_attack_pressed
signal time_mode_pressed(mode: String)
signal next_track_pressed
signal panel_closed
signal start_sailing

const HudTheme = preload("res://Scripts/UI/HudTheme.gd")
const CONTENT_PATH := "res://Config/portfolio_content.json"
const ISLAND_NAMES := ["Sobre", "Experiência", "Formação", "Projetos", "Contato"]

var content: Dictionary = {}
var daylight := 1.0
var applied_daylight := -1.0
var touch := false
var root: Control

# Masthead (canto superior esquerdo, sem painel)
var masthead: VBoxContainer
var section_title: Label
var route_line_label: Label

# Carta (painel lateral discreto, recolhível)
var carta: PanelContainer
var carta_body: VBoxContainer
var carta_toggle: Button
var carta_open := true
var island_rows: Array[Button] = []
var time_buttons: Array[Button] = []
var music_button: Button

# Rodapé: estatísticas + dica + contatos
var stats_row: HBoxContainer
var stat_speed: Label
var stat_distance: Label
var cannon_label: Label
var hint_label: Label
var contacts: HBoxContainer

# Regata
var race_board: VBoxContainer
var race_timer: Label
var race_count: Label

# Painel de leitura das ilhas (paginado, sem rolagem)
var island_panel: PanelContainer
var island_kicker: Label
var island_title: Label
var island_body: VBoxContainer
var page_label: Label
var page_prev: Button
var page_next: Button
var blocks: Array[Control] = []
var page_of: Array[int] = []
var page := 0
var page_count := 1
var current_island := -1
var auto_opened := false
var dismissed_island := -1
var panel_height := 400.0

# Abertura
var intro_panel: PanelContainer
var intro_column: VBoxContainer
var intro_visible := false

# Projetos ao vivo do GitHub
var live_projects: Array = []
var projects_request: HTTPRequest

## Ilhas cujo painel já foi aberto (para a bússola sugerir a próxima).
var visited := {}

# Compatibilidade com main_world (cartão de comandos foi substituído pela dica).
var controls_card: Control

func _ready() -> void:
	layer = 4
	touch = DisplayServer.is_touchscreen_available()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PATH))
	if parsed is Dictionary:
		content = parsed
	root = Control.new()
	root.name = "HudRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_masthead()
	_build_carta()
	_build_footer()
	_build_race_board()
	_build_island_panel()
	_build_intro()
	controls_card = Control.new()
	_fetch_projects()
	set_daylight(1.0)
	get_viewport().size_changed.connect(func(): _layout(); _relayout_next_frames())
	_layout()
	_relayout_next_frames()

# --- Peças básicas ------------------------------------------------------------------

func _label(text: String, variation: String, size := 0) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if size > 0:
		label.add_theme_font_size_override("font_size", size)
	return label

func _wrap(text: String, variation: String, size := 0) -> Label:
	var label := _label(text, variation, size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _button(text: String, action: Callable, variation := "") -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if variation != "":
		button.theme_type_variation = variation
	button.pressed.connect(action)
	return button

func _link(text: String, url: String, variation := "") -> Button:
	return _button(text + "  ↗", func(): OS.shell_open(url), variation)

func _rule() -> HSeparator:
	var line := HSeparator.new()
	line.theme_type_variation = "Rule"
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line

func _stat(kicker: String) -> Array:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(_label(kicker, "KickerOver"))
	var value := _label("—", "StatOver")
	block.add_child(value)
	return [block, value]

# --- Construção ----------------------------------------------------------------------

func _build_masthead() -> void:
	masthead = VBoxContainer.new()
	masthead.add_theme_constant_override("separation", 0)
	masthead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(masthead)
	masthead.add_child(_label("PEDRO D. FERREIRA  ·  CARTA DE NAVEGAÇÃO", "KickerOver"))
	section_title = _label("Mar aberto", "TitleOver")
	masthead.add_child(section_title)
	route_line_label = _label("", "MutedOver")
	masthead.add_child(route_line_label)

func _build_carta() -> void:
	carta = PanelContainer.new()
	carta.theme_type_variation = "Specimen"
	root.add_child(carta)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	carta.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	header.add_child(_label("A CARTA", "Kicker"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	carta_toggle = _button("−", func(): _set_carta_open(not carta_open), "Bare")
	header.add_child(carta_toggle)
	carta_body = VBoxContainer.new()
	carta_body.add_theme_constant_override("separation", 6)
	column.add_child(carta_body)
	carta_body.add_child(_rule())
	carta_body.add_child(_label("ILHAS", "Kicker"))
	for i in range(ISLAND_NAMES.size()):
		var row := _button("%d   %s" % [i + 1, ISLAND_NAMES[i]], island_pressed.emit.bind(i), "Row")
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		carta_body.add_child(row)
		island_rows.append(row)
	carta_body.add_child(_rule())
	carta_body.add_child(_label("MODO", "Kicker"))
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 4)
	carta_body.add_child(modes)
	var sail := _button("Navegar", func(): free_sail_pressed.emit())
	sail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modes.add_child(sail)
	var race := _button("Regata · 3 min", func(): time_attack_pressed.emit())
	race.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modes.add_child(race)
	carta_body.add_child(_label("CÉU", "Kicker"))
	var times := HBoxContainer.new()
	times.add_theme_constant_override("separation", 4)
	carta_body.add_child(times)
	for mode in ["auto", "day", "night"]:
		var button := _button({"auto": "Ciclo", "day": "Dia", "night": "Noite"}[mode], time_mode_pressed.emit.bind(mode))
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		times.add_child(button)
		time_buttons.append(button)
	music_button = _button("Próxima música", func(): next_track_pressed.emit())
	carta_body.add_child(music_button)
	_set_carta_open(not touch)

func _set_carta_open(open: bool) -> void:
	carta_open = open
	carta_body.visible = open
	carta_toggle.text = "−" if open else "+"
	_layout()

func _build_footer() -> void:
	stats_row = HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 26)
	stats_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stats_row)
	var speed: Array = _stat("VELOCIDADE")
	stats_row.add_child(speed[0])
	stat_speed = speed[1]
	var distance: Array = _stat("PRÓXIMA ILHA")
	stats_row.add_child(distance[0])
	stat_distance = distance[1]
	var cannon: Array = _stat("CANHÃO")
	stats_row.add_child(cannon[0])
	cannon_label = cannon[1]
	hint_label = _label("", "MutedOver")
	hint_label.text = "joystick: leme  ·  FOGO: canhão  ·  dois dedos: câmera" if touch else "LEME  W A S D  ·  IMPULSO  Shift  ·  CANHÃO  R F  Espaço  ·  MAPA  M  ·  ILHAS  1–5"
	root.add_child(hint_label)
	contacts = HBoxContainer.new()
	contacts.add_theme_constant_override("separation", 6)
	root.add_child(contacts)
	var links: Dictionary = content.get("links", {})
	for item in [["LinkedIn", "linkedin"], ["GitHub", "github"], ["WhatsApp", "whatsapp"]]:
		if links.has(item[1]):
			contacts.add_child(_link(item[0], str(links[item[1]]), "Ghost"))

func _build_race_board() -> void:
	race_board = VBoxContainer.new()
	race_board.visible = false
	race_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(race_board)
	var kicker := _label("REGATA  ·  TIME ATTACK", "KickerOver")
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	race_board.add_child(kicker)
	race_timer = _label("03:00", "StatOver", 44)
	race_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	race_board.add_child(race_timer)
	race_count = _label("boias 00 / 20", "MutedOver")
	race_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	race_board.add_child(race_count)

func _build_island_panel() -> void:
	island_panel = PanelContainer.new()
	island_panel.theme_type_variation = "Sheet"
	island_panel.visible = false
	island_panel.clip_contents = true
	root.add_child(island_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	island_panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	island_kicker = _label("", "Kicker")
	header.add_child(island_kicker)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header.add_child(_button("×", func(): _close_island(), "Bare"))
	island_title = _wrap("", "Title", 30)
	column.add_child(island_title)
	column.add_child(_rule())
	island_body = VBoxContainer.new()
	island_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	island_body.add_theme_constant_override("separation", 12)
	island_body.clip_contents = true
	column.add_child(island_body)
	column.add_child(_rule())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 4)
	column.add_child(footer)
	footer.add_child(_button("‹ ilha", func(): island_pressed.emit(posmod(current_island - 1, ISLAND_NAMES.size())), "Bare"))
	var left := Control.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(left)
	page_prev = _button("‹", func(): _show_page(page - 1), "Bare")
	footer.add_child(page_prev)
	page_label = _label("1 / 1", "Mono", 12)
	footer.add_child(page_label)
	page_next = _button("›", func(): _show_page(page + 1), "Bare")
	footer.add_child(page_next)
	var right := Control.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(right)
	footer.add_child(_button("ilha ›", func(): island_pressed.emit(posmod(current_island + 1, ISLAND_NAMES.size())), "Bare"))

func _build_intro() -> void:
	intro_panel = PanelContainer.new()
	intro_panel.theme_type_variation = "Sheet"
	intro_panel.visible = false
	root.add_child(intro_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	intro_panel.add_child(column)
	intro_column = column
	column.add_child(_label(str(content.get("status", "Portfólio")).to_upper(), "Kicker"))
	column.add_child(_label(str(content.get("name", "Pedro D. Ferreira")), "Title", 60))
	column.add_child(_wrap(str(content.get("role", "")), "Heading"))
	column.add_child(_wrap(str(content.get("tagline", "")).to_upper(), "Kicker"))
	column.add_child(_wrap(str(content.get("pitch", "")), "Body"))
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 28)
	for stat in content.get("stats", []):
		var block := VBoxContainer.new()
		block.add_child(_label(str(stat.value), "Mono", 26))
		block.add_child(_label(str(stat.label), "Muted", 13))
		stats.add_child(block)
	column.add_child(stats)
	column.add_child(_rule())
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	column.add_child(actions)
	actions.add_child(_button("Zarpar e navegar", func(): start_sailing.emit(), "Primary"))
	actions.add_child(_button("Explorar as ilhas", func(): island_pressed.emit(0)))
	actions.add_child(_button("Regata · 3 min", func(): time_attack_pressed.emit()))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)
	var links: Dictionary = content.get("links", {})
	for item in [["LinkedIn", "linkedin"], ["GitHub", "github"], ["WhatsApp", "whatsapp"]]:
		if links.has(item[1]):
			row.add_child(_link(item[0], str(links[item[1]]), "Ghost"))
	column.add_child(_wrap("Toque nos controles da tela para navegar." if touch else "W A S D para navegar  ·  1–5 visita uma ilha  ·  M abre o mapa", "Mono", 12))

# --- Abertura -------------------------------------------------------------------------

func show_intro(show: bool) -> void:
	intro_visible = show
	intro_panel.visible = show
	for node in [masthead, carta, stats_row, hint_label, contacts]:
		node.visible = not show
	_layout()
	_relayout_next_frames()

func _relayout_next_frames() -> void:
	for i in range(2):
		await get_tree().process_frame
		_layout()

# --- Painel das ilhas (paginado) -------------------------------------------------------

func _block(children: Array) -> VBoxContainer:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 4)
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for child in children:
		if child != null:
			block.add_child(child)
	island_body.add_child(block)
	blocks.append(block)
	return block

func show_island(index: int, automatic := false) -> void:
	var islands: Array = content.get("islands", [])
	if index < 0 or index >= islands.size():
		return
	if intro_visible:
		show_intro(false)
	for child in island_body.get_children():
		child.queue_free()
	blocks.clear()
	var data: Dictionary = islands[index]
	current_island = index
	auto_opened = automatic
	dismissed_island = -1
	visited[index] = true
	island_kicker.text = str(data.get("kicker", "")).to_upper()
	island_title.text = str(data.get("title", ""))
	for paragraph in data.get("paragraphs", []):
		_block([_wrap(str(paragraph), "Body")])
	var facts: Array = data.get("facts", [])
	if not facts.is_empty():
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 10)
		for fact in facts:
			var cell := VBoxContainer.new()
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.add_child(_label(str(fact.label).to_upper(), "Kicker"))
			cell.add_child(_wrap(str(fact.value), "Mono"))
			grid.add_child(cell)
		_block([grid])
	for entry in data.get("entries", []):
		var parts: Array = [_label(str(entry.period), "Mono", 12), _wrap(str(entry.title), "Heading"), _label(str(entry.org).to_upper(), "Kicker")]
		if str(entry.get("text", "")) != "":
			parts.append(_wrap(str(entry.text), "Body"))
		_block(parts)
	var is_projects := str(data.get("id", "")) == "projetos"
	if is_projects and not live_projects.is_empty():
		_block([_label("ÚLTIMOS NO GITHUB  ·  ATUALIZA SOZINHO", "Kicker")])
		for project in live_projects:
			var meta: PackedStringArray = []
			if str(project.get("language", "")) != "":
				meta.append(str(project.language))
			for topic in project.get("topics", []):
				meta.append(str(topic))
			var pushed := str(project.get("pushed_at", ""))
			if pushed.length() >= 10:
				meta.append("%s/%s/%s" % [pushed.substr(8, 2), pushed.substr(5, 2), pushed.substr(0, 4)])
			var parts: Array = [_wrap(str(project.name).replace("_", " ").replace("-", " "), "Heading")]
			if str(project.get("description", "")) != "":
				parts.append(_wrap(str(project.description), "Body"))
			parts.append(_wrap("  ·  ".join(meta), "Mono"))
			parts.append(_link("Ver no GitHub", str(project.url), "Ghost"))
			_block(parts)
	else:
		for project in data.get("projects", []):
			_block([_wrap(str(project.title), "Heading"), _wrap(str(project.text), "Body"), _wrap("  ·  ".join(PackedStringArray(project.get("stack", []))), "Mono"), _link("Código no GitHub", str(project.url), "Ghost")])
	var links: Dictionary = content.get("links", {})
	var contact_buttons: Array = []
	for contact in data.get("contacts", []):
		contact_buttons.append(_link(str(contact.label), str(links.get(contact.key, ""))))
	if not contact_buttons.is_empty():
		_block(contact_buttons)
	if is_projects and links.has("github_repos"):
		_block([_link("Todos os projetos", str(links.github_repos), "Ghost")])
	island_panel.visible = true
	_layout()
	_paginate()

## Distribui os blocos em páginas que cabem no painel (leitura sem rolagem).
func _paginate() -> void:
	# Mede o "chrome" (cabeçalho, título, rodapé) com os blocos escondidos e usa a
	# altura planejada do painel: o PanelContainer cresceria com o conteúdo.
	for block in blocks:
		block.visible = false
	await get_tree().process_frame
	if not is_instance_valid(island_body):
		return
	var column := island_body.get_parent() as Control
	var chrome := column.get_combined_minimum_size().y
	var available := maxf(panel_height - 48.0 - chrome - 8.0, 120.0)
	for block in blocks:
		block.visible = true
	await get_tree().process_frame
	var used := 0.0
	page_count = 1
	page_of.clear()
	for block in blocks:
		var height := block.get_combined_minimum_size().y + 12.0
		if used > 0.0 and used + height > available:
			page_count += 1
			used = 0.0
		page_of.append(page_count - 1)
		used += height
	_show_page(0)
	_layout()
func _show_page(index: int) -> void:
	page = clampi(index, 0, page_count - 1)
	for i in range(blocks.size()):
		blocks[i].visible = i < page_of.size() and page_of[i] == page
	page_label.text = "%d / %d" % [page + 1, page_count]
	page_prev.disabled = page == 0
	page_next.disabled = page >= page_count - 1

func _close_island() -> void:
	dismissed_island = current_island
	hide_island()
	panel_closed.emit()

func hide_island() -> void:
	island_panel.visible = false
	auto_opened = false
	_layout()

## Chamado pelo jogo a cada quadro com a ilha próxima (ou -1). Abre o painel ao
## chegar perto e fecha sozinho ao se afastar, como no portfólio de referência.
func set_approach(index: int) -> void:
	if intro_visible:
		return
	if index < 0:
		dismissed_island = -1
		if island_panel.visible and auto_opened:
			hide_island()
		return
	if index == dismissed_island:
		return
	if not island_panel.visible or (auto_opened and current_island != index):
		show_island(index, true)

func _unhandled_key_input(event: InputEvent) -> void:
	if not island_panel.visible or not event.pressed or event.echo:
		return
	if event.physical_keycode in [KEY_PAGEDOWN, KEY_PERIOD]:
		_show_page(page + 1)
	elif event.physical_keycode in [KEY_PAGEUP, KEY_COMMA]:
		_show_page(page - 1)

# --- Projetos ao vivo do GitHub ---------------------------------------------------------

func _fetch_projects() -> void:
	var user := str(content.get("links", {}).get("github_user", "DATAdotPDF"))
	var url := "https://api.github.com/users/%s/repos?sort=pushed&direction=desc&per_page=30" % user
	if OS.has_feature("web"):
		url = str(JavaScriptBridge.eval("window.location.origin", true)) + "/api/projetos"
	projects_request = HTTPRequest.new()
	projects_request.timeout = 8.0
	add_child(projects_request)
	projects_request.request_completed.connect(_on_projects_loaded.bind(user))
	projects_request.request(url, PackedStringArray(["User-Agent: portfolio-data-cybersecurity", "Accept: application/vnd.github+json"]))

func _on_projects_loaded(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, user: String) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	var list: Array = []
	if parsed is Dictionary:
		list = parsed.get("projects", [])
	elif parsed is Array:
		for repo in parsed:
			if repo.get("fork", false) or str(repo.get("name", "")).to_lower() == user.to_lower():
				continue
			list.append({"name": repo.name, "description": str(repo.description) if repo.get("description") != null else "", "language": str(repo.language) if repo.get("language") != null else "", "pushed_at": str(repo.get("pushed_at", "")), "url": str(repo.get("html_url", "")), "topics": repo.get("topics", [])})
			if list.size() >= 6:
				break
	live_projects = list
	if island_panel.visible and current_island == 3:
		show_island(3, auto_opened)

# --- Estado vindo do jogo ---------------------------------------------------------------

func _distance_text(meters: float) -> String:
	return "%.1f km" % (meters / 1000.0) if meters >= 1000.0 else "%d m" % int(meters)

func set_status(section: String, distance: float, speed: float, _fps: int) -> void:
	section_title.text = section
	stat_speed.text = "%.1f m/s" % speed
	stat_distance.text = _distance_text(distance)

func set_route(target_name: String, distance: float) -> void:
	route_line_label.text = "rumo a %s · %s" % [target_name, _distance_text(distance)] if target_name != "" else ""
	for i in range(island_rows.size()):
		island_rows[i].text = "%d   %s%s" % [i + 1, ISLAND_NAMES[i], "   ✓" if visited.has(i) else ""]

func set_time_mode(mode: String) -> void:
	for i in range(time_buttons.size()):
		time_buttons[i].button_pressed = ["auto", "day", "night"][i] == mode

func set_track(name: String) -> void:
	music_button.tooltip_text = "Tocando: " + name

func set_race(active: bool, remaining: float, hits: int, total: int, finished_text := "") -> void:
	race_board.visible = active
	if not active:
		return
	var seconds := ceili(remaining)
	race_timer.text = finished_text if finished_text != "" else "%02d:%02d" % [floori(seconds / 60.0), seconds % 60]
	race_count.text = "boias %02d / %02d" % [hits, total]

func notify_player_input() -> void:
	pass

# --- Tema dia/noite e layout -------------------------------------------------------------

func set_daylight(value: float) -> void:
	daylight = value
	if absf(daylight - applied_daylight) < 0.04:
		return
	applied_daylight = daylight
	var colors := HudTheme.palette(daylight)
	var theme := HudTheme.build_theme(colors)
	var halo := Color(colors.paper, 0.9)
	var defs := [
		["Kicker", "label", 11, colors.muted, false], ["Title", "display_italic", 34, colors.ink, false],
		["Heading", "display", 22, colors.ink, false], ["Mono", "mono", 13, colors.ink, false],
		["Body", "body", 15, colors.ink, false], ["Muted", "display_italic", 15, colors.muted, false],
		# Variações "Over": texto direto sobre a cena, com halo de papel para ler sobre o mar.
		["KickerOver", "label", 11, colors.muted, true], ["TitleOver", "display_italic", 44, colors.ink, true],
		["MutedOver", "display_italic", 16, colors.muted, true], ["StatOver", "mono", 20, colors.ink, true],
	]
	for d in defs:
		theme.set_type_variation(d[0], "Label")
		theme.set_font("font", d[0], HudTheme.font(d[1]))
		theme.set_font_size("font_size", d[0], d[2])
		theme.set_color("font_color", d[0], d[3])
		if d[4]:
			theme.set_color("font_outline_color", d[0], halo)
			theme.set_constant("outline_size", d[0], 7)
	var sheet := HudTheme.paper_box(colors, 0.96)
	sheet.set_content_margin_all(24)
	theme.set_type_variation("Sheet", "PanelContainer")
	theme.set_stylebox("panel", "Sheet", sheet)
	var specimen := HudTheme.paper_box(colors, 0.88)
	specimen.shadow_size = 0
	specimen.set_content_margin_all(14)
	theme.set_type_variation("Specimen", "PanelContainer")
	theme.set_stylebox("panel", "Specimen", specimen)
	var empty := StyleBoxEmpty.new()
	for variation in ["Bare", "Row"]:
		theme.set_type_variation(variation, "Button")
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			theme.set_stylebox(state, variation, empty)
		theme.set_color("font_color", variation, colors.ink)
		theme.set_color("font_hover_color", variation, colors.accent)
		theme.set_color("font_disabled_color", variation, Color(colors.ink, 0.25))
	theme.set_font("font", "Row", HudTheme.font("display"))
	theme.set_font_size("font_size", "Row", 17)
	theme.set_font_size("font_size", "Bare", 16)
	theme.set_type_variation("Ghost", "Button")
	var ghost := HudTheme.button_box(colors, "normal")
	ghost.bg_color = Color(colors.paper, 0.55)
	var ghost_hover := ghost.duplicate()
	ghost_hover.border_color = colors.accent
	theme.set_stylebox("normal", "Ghost", ghost)
	theme.set_stylebox("hover", "Ghost", ghost_hover)
	theme.set_stylebox("pressed", "Ghost", ghost_hover)
	theme.set_font_size("font_size", "Ghost", 12)
	theme.set_type_variation("Primary", "Button")
	var primary := HudTheme.button_box(colors, "normal")
	primary.bg_color = colors.ink
	primary.border_color = colors.ink
	var primary_hover := primary.duplicate()
	primary_hover.bg_color = colors.accent
	primary_hover.border_color = colors.accent
	theme.set_stylebox("normal", "Primary", primary)
	theme.set_stylebox("hover", "Primary", primary_hover)
	theme.set_stylebox("pressed", "Primary", primary_hover)
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		theme.set_color(key, "Primary", colors.paper)
	theme.set_font_size("font_size", "Primary", 15)
	theme.set_type_variation("Rule", "HSeparator")
	var rule := StyleBoxLine.new()
	rule.color = colors.line
	rule.thickness = 1
	theme.set_stylebox("separator", "Rule", rule)
	root.theme = theme

func _layout() -> void:
	if root == null or intro_panel == null:
		return
	var screen := get_viewport().get_visible_rect().size
	var portrait := screen.x < screen.y
	var margin := 16.0 if portrait else 28.0
	masthead.size = Vector2.ZERO
	masthead.position = Vector2(margin, margin)
	section_title.add_theme_font_size_override("font_size", 30 if portrait else 44)
	# Carta: abaixo do Log Pose, à direita.
	carta.size = Vector2(0, 0)
	carta.custom_minimum_size.x = 210.0
	var carta_size := carta.get_combined_minimum_size()
	carta.position = Vector2(screen.x - carta_size.x - margin, (150.0 if portrait else 262.0))
	# Rodapé.
	stats_row.size = Vector2.ZERO
	var stats_size := stats_row.get_combined_minimum_size()
	var bottom := screen.y - margin - (250.0 if touch else 0.0)
	stats_row.position = Vector2(margin, bottom - stats_size.y)
	hint_label.size = Vector2.ZERO
	hint_label.visible = not intro_visible and not portrait
	hint_label.position = Vector2(margin, stats_row.position.y - hint_label.get_combined_minimum_size().y - 10.0)
	contacts.size = Vector2.ZERO
	var contacts_size := contacts.get_combined_minimum_size()
	contacts.position = Vector2(screen.x - contacts_size.x - margin, screen.y - contacts_size.y - margin) if not portrait else Vector2(margin, masthead.position.y + masthead.get_combined_minimum_size().y + 6.0)
	race_board.size = Vector2(240, 0)
	race_board.position = Vector2((screen.x - 240.0) * 0.5, margin)
	# Painel da ilha: direita (paisagem) ou gaveta inferior (retrato). A carta some.
	stats_row.visible = not intro_visible and not (portrait and island_panel.visible)
	carta.visible = not intro_visible and not island_panel.visible
	if portrait:
		# Entre o cabeçalho e os controles de toque.
		var top := masthead.position.y + masthead.get_combined_minimum_size().y + contacts_size.y + 16.0
		panel_height = screen.y - top - (300.0 if touch else margin)
		island_panel.position = Vector2(8.0, top)
		island_panel.size = Vector2(screen.x - 16.0, panel_height)
	else:
		var width := minf(440.0, screen.x * 0.38)
		var top := 262.0
		panel_height = screen.y - top - contacts_size.y - margin * 2.0
		island_panel.position = Vector2(screen.x - width - margin, top)
		island_panel.size = Vector2(width, panel_height)
	island_title.add_theme_font_size_override("font_size", 26 if portrait else 30)
	# Abertura.
	var intro_width := (screen.x - margin * 2.0) if portrait else minf(620.0, screen.x - margin * 2.0)
	intro_column.custom_minimum_size.x = intro_width - 48.0
	intro_panel.size = Vector2.ZERO
	if portrait:
		intro_panel.size = Vector2(screen.x - margin * 2.0, 0.0)
		intro_panel.position = Vector2(margin, screen.y - intro_panel.get_combined_minimum_size().y - margin)
	else:
		intro_panel.size = Vector2(intro_width, 0.0)
		intro_panel.position = Vector2(margin * 2.0, (screen.y - intro_panel.get_combined_minimum_size().y) * 0.5)
