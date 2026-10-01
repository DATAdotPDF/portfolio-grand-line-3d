extends CanvasLayer

## HUD do portfólio: carta náutica em papel (tema pirata / Seagazer / Wind Waker /
## One Piece), com tons de dia e de noite. Referências de UX: nazarejose.vercel.app
## (etiquetas de seção, cartões de onboarding, teclas desenhadas) e o artifact
## "Melon Jelly Knife" (hierarquia editorial, rótulos espaçados, números em mono).

signal free_sail_pressed
signal island_pressed(index: int)
signal time_attack_pressed
signal time_mode_pressed(mode: String)
signal next_track_pressed
signal panel_closed

const HudTheme = preload("res://Scripts/UI/HudTheme.gd")
const CONTENT_PATH := "res://Config/portfolio_content.json"
const ISLAND_NAMES := ["Sobre", "Experiência", "Formação", "Projetos", "Contato"]

var content: Dictionary = {}
var daylight := 1.0
var applied_daylight := -1.0
var root: Control
var masthead: PanelContainer
var section_title: Label
var status_label: Label
var nav_bar: HFlowContainer
var side_column: VBoxContainer
var time_buttons: Array[Button] = []
var music_button: Button
var cannon_panel: PanelContainer
var cannon_label: Label
var controls_card: PanelContainer
var controls_timer := 16.0
var race_board: PanelContainer
var race_timer: Label
var race_count: Label
var island_panel: PanelContainer
var island_scroll: ScrollContainer
var island_body: VBoxContainer
var approach_card: PanelContainer
var approach_button: Button
var approach_index := -1
var touch := false

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
	_build_nav()
	_build_side_column()
	_build_cannon_panel()
	_build_controls_card()
	_build_race_board()
	_build_island_panel()
	_build_approach_card()
	set_daylight(1.0)
	get_viewport().size_changed.connect(_layout)
	_layout()

# --- Construção ---------------------------------------------------------------

func _label(text: String, variation: String, size := 0) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	if size > 0:
		label.add_theme_font_size_override("font_size", size)
	return label

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	return button

func _build_masthead() -> void:
	masthead = PanelContainer.new()
	masthead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(masthead)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	masthead.add_child(column)
	column.add_child(_label("PEDRO D. FERREIRA  ·  CARTA DE NAVEGAÇÃO", "Kicker"))
	section_title = _label("Sobre", "Title")
	column.add_child(section_title)
	status_label = _label("—", "Mono")
	column.add_child(status_label)

func _build_nav() -> void:
	nav_bar = HFlowContainer.new()
	nav_bar.add_theme_constant_override("h_separation", 6)
	nav_bar.add_theme_constant_override("v_separation", 6)
	root.add_child(nav_bar)
	nav_bar.add_child(_button("⚓ Navegar livre", func(): free_sail_pressed.emit()))
	for i in range(ISLAND_NAMES.size()):
		nav_bar.add_child(_button("%d · %s" % [i + 1, ISLAND_NAMES[i]], island_pressed.emit.bind(i)))
	nav_bar.add_child(_button("⏱ Regata · 3 min", func(): time_attack_pressed.emit()))

func _build_side_column() -> void:
	side_column = VBoxContainer.new()
	side_column.add_theme_constant_override("separation", 6)
	side_column.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(side_column)
	var times := HBoxContainer.new()
	times.add_theme_constant_override("separation", 4)
	side_column.add_child(times)
	for mode in ["auto", "day", "night"]:
		var button := _button({"auto": "Ciclo", "day": "Dia", "night": "Noite"}[mode], time_mode_pressed.emit.bind(mode))
		button.toggle_mode = true
		times.add_child(button)
		time_buttons.append(button)
	music_button = _button("♪ Próxima música", func(): next_track_pressed.emit())
	side_column.add_child(music_button)
	var help := _button("? Comandos", func(): _show_controls(not controls_card.visible))
	side_column.add_child(help)

func _build_cannon_panel() -> void:
	cannon_panel = PanelContainer.new()
	cannon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cannon_panel)
	cannon_label = _label("", "Mono")
	cannon_panel.add_child(cannon_label)

func _keycap(text: String) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.theme_type_variation = "Keycap"
	var label := _label(text, "Mono", 13)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_child(label)
	return cap

func _build_controls_card() -> void:
	controls_card = PanelContainer.new()
	root.add_child(controls_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	controls_card.add_child(column)
	column.add_child(_label("Comandos de bordo", "Title", 24))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	column.add_child(grid)
	var rows := [
		[["W", "A", "S", "D"], "navegar"],
		[["Shift"], "impulso"],
		[["R", "F"], "inclinar o canhão"],
		[["Espaço"], "disparar"],
		[["1", "–", "5"], "visitar uma ilha"],
		[["Tab"], "ver o globo"],
		[["Esc"], "voltar ao barco"],
		[["◐ arrastar"], "esquerdo: água · direito: câmera"],
	]
	for row in rows:
		var caps := HBoxContainer.new()
		caps.add_theme_constant_override("separation", 4)
		for key in row[0]:
			caps.add_child(_keycap(key))
		grid.add_child(caps)
		grid.add_child(_label(row[1], "Body", 14))
	column.add_child(_label("Siga o Log Pose até a ilha mais próxima.", "Muted", 13))
	controls_card.visible = not touch

func _build_race_board() -> void:
	race_board = PanelContainer.new()
	race_board.visible = false
	race_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(race_board)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	race_board.add_child(column)
	var kicker := _label("REGATA  ·  TIME ATTACK", "Kicker")
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(kicker)
	race_timer = _label("03:00", "Mono", 34)
	race_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(race_timer)
	race_count = _label("Boias 00 / 20", "Mono", 14)
	race_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(race_count)

func _build_island_panel() -> void:
	island_panel = PanelContainer.new()
	island_panel.theme_type_variation = "Sheet"
	island_panel.visible = false
	root.add_child(island_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	island_panel.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	top.add_child(_button("✕ Voltar ao barco", func(): hide_island(); panel_closed.emit()))
	island_scroll = ScrollContainer.new()
	island_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	island_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(island_scroll)
	island_body = VBoxContainer.new()
	island_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	island_body.add_theme_constant_override("separation", 10)
	island_scroll.add_child(island_body)

func _build_approach_card() -> void:
	approach_card = PanelContainer.new()
	approach_card.visible = false
	root.add_child(approach_card)
	approach_button = _button("", func(): if approach_index >= 0: island_pressed.emit(approach_index))
	approach_card.add_child(approach_button)

# --- Conteúdo das ilhas -------------------------------------------------------------

func _wrap(text: String, variation: String, size := 0) -> Label:
	var label := _label(text, variation, size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _rule() -> HSeparator:
	var line := HSeparator.new()
	line.theme_type_variation = "Rule"
	return line

func _link(text: String, url: String) -> Button:
	return _button(text + "  ↗", func(): OS.shell_open(url))

func show_island(index: int) -> void:
	for child in island_body.get_children():
		child.queue_free()
	var islands: Array = content.get("islands", [])
	if index < 0 or index >= islands.size():
		return
	var data: Dictionary = islands[index]
	island_body.add_child(_label(str(data.get("kicker", "")).to_upper(), "Kicker"))
	island_body.add_child(_wrap(str(data.get("title", "")), "Title", 30))
	island_body.add_child(_rule())
	for paragraph in data.get("paragraphs", []):
		island_body.add_child(_wrap(str(paragraph), "Body"))
	for fact in data.get("facts", []):
		island_body.add_child(_label(str(fact.label).to_upper(), "Kicker"))
		island_body.add_child(_wrap(str(fact.value), "Mono"))
	for entry in data.get("entries", []):
		island_body.add_child(_rule())
		island_body.add_child(_label(str(entry.period), "Mono", 12))
		island_body.add_child(_wrap(str(entry.title), "Heading"))
		island_body.add_child(_label(str(entry.org).to_upper(), "Kicker"))
		if str(entry.get("text", "")) != "":
			island_body.add_child(_wrap(str(entry.text), "Body"))
	for project in data.get("projects", []):
		island_body.add_child(_rule())
		island_body.add_child(_wrap(str(project.title), "Heading"))
		island_body.add_child(_wrap(str(project.text), "Body"))
		island_body.add_child(_wrap("  ·  ".join(PackedStringArray(project.get("stack", []))), "Mono"))
		island_body.add_child(_link("Código no GitHub", str(project.url)))
	var links: Dictionary = content.get("links", {})
	for contact in data.get("contacts", []):
		island_body.add_child(_link(str(contact.label), str(links.get(contact.key, ""))))
	if data.get("id", "") == "projetos" and links.has("github_repos"):
		island_body.add_child(_rule())
		island_body.add_child(_link("Todos os projetos", str(links.github_repos)))
	island_panel.visible = true
	approach_card.visible = false
	_show_controls(false)
	island_scroll.scroll_vertical = 0
	_layout()

func hide_island() -> void:
	island_panel.visible = false

# --- Estado vindo do jogo ------------------------------------------------------------

func set_status(section: String, distance: float, speed: float, fps: int) -> void:
	section_title.text = section
	status_label.text = "ILHA %4.0f m   ·   VEL %4.1f m/s   ·   %d fps" % [distance, speed, fps]

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
	race_count.text = "Boias %02d / %02d" % [hits, total]

## Convite para ler a seção ao navegar perto de uma ilha (como as boias do nazarejose).
func set_approach(index: int) -> void:
	if island_panel.visible:
		index = -1
	approach_index = index
	approach_card.visible = index >= 0
	if index >= 0:
		approach_button.text = "[ %s ]   Ancorar e ler  ·  %s" % [ISLAND_NAMES[index].to_upper(), "toque" if touch else "Enter"]

func _show_controls(show: bool) -> void:
	controls_card.visible = show
	controls_timer = 0.0 if not show else 30.0
	_layout()

func notify_player_input() -> void:
	# Depois que a pessoa começa a navegar, o cartão some sozinho em alguns segundos.
	if controls_card.visible and controls_timer > 6.0:
		controls_timer = 6.0

func _process(delta: float) -> void:
	if controls_card.visible and controls_timer > 0.0:
		controls_timer -= delta
		if controls_timer <= 0.0:
			_show_controls(false)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and (event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_KP_ENTER) and approach_index >= 0:
		island_pressed.emit(approach_index)
		get_viewport().set_input_as_handled()

# --- Tema dia/noite e layout -------------------------------------------------------

func set_daylight(value: float) -> void:
	daylight = value
	if absf(daylight - applied_daylight) < 0.04:
		return
	applied_daylight = daylight
	var colors := HudTheme.palette(daylight)
	var theme := HudTheme.build_theme(colors)
	theme.set_type_variation("Kicker", "Label")
	theme.set_font("font", "Kicker", HudTheme.font("label"))
	theme.set_font_size("font_size", "Kicker", 11)
	theme.set_color("font_color", "Kicker", colors.muted)
	theme.set_type_variation("Title", "Label")
	theme.set_font("font", "Title", HudTheme.font("display_italic"))
	theme.set_font_size("font_size", "Title", 34)
	theme.set_color("font_color", "Title", colors.ink)
	theme.set_type_variation("Heading", "Label")
	theme.set_font("font", "Heading", HudTheme.font("display"))
	theme.set_font_size("font_size", "Heading", 23)
	theme.set_color("font_color", "Heading", colors.ink)
	theme.set_type_variation("Mono", "Label")
	theme.set_font("font", "Mono", HudTheme.font("mono"))
	theme.set_font_size("font_size", "Mono", 13)
	theme.set_color("font_color", "Mono", colors.ink)
	theme.set_type_variation("Body", "Label")
	theme.set_font_size("font_size", "Body", 15)
	theme.set_color("font_color", "Body", colors.ink)
	theme.set_type_variation("Muted", "Label")
	theme.set_font("font", "Muted", HudTheme.font("display_italic"))
	theme.set_font_size("font_size", "Muted", 15)
	theme.set_color("font_color", "Muted", colors.muted)
	theme.set_type_variation("Keycap", "PanelContainer")
	var cap := HudTheme.button_box(colors, "normal")
	cap.border_color = Color(colors.ink, 0.55)
	cap.set_border_width_all(1)
	cap.border_width_bottom = 3
	cap.content_margin_left = 8
	cap.content_margin_right = 8
	cap.content_margin_top = 3
	cap.content_margin_bottom = 3
	cap.bg_color = Color(colors.paper_edge, 0.6)
	theme.set_stylebox("panel", "Keycap", cap)
	theme.set_type_variation("Sheet", "PanelContainer")
	var sheet := HudTheme.paper_box(colors, 0.97)
	sheet.set_content_margin_all(22)
	sheet.border_color = Color(colors.accent, 0.55)
	theme.set_stylebox("panel", "Sheet", sheet)
	theme.set_type_variation("Rule", "HSeparator")
	var rule := StyleBoxLine.new()
	rule.color = colors.line
	rule.thickness = 1
	theme.set_stylebox("separator", "Rule", rule)
	root.theme = theme

func _layout() -> void:
	if root == null:
		return
	var screen := get_viewport().get_visible_rect().size
	var portrait := screen.x < screen.y
	var margin := 16.0 if portrait else 20.0
	masthead.position = Vector2(margin, margin)
	masthead.size = Vector2.ZERO
	section_title.add_theme_font_size_override("font_size", 26 if portrait else 34)
	# Em pé, o Log Pose (canto superior direito) ocupa ~150 px: a masthead estreita e a navegação desce.
	if portrait:
		masthead.custom_minimum_size.x = 0.0
		masthead.size = Vector2(screen.x - margin * 2.0 - 130.0, 0.0)
	var nav_top := masthead.position.y + masthead.get_combined_minimum_size().y + 10.0
	if portrait:
		nav_top = maxf(nav_top, 150.0)
	nav_bar.position = Vector2(margin, nav_top)
	nav_bar.size = Vector2(screen.x - margin * 2.0 - (0.0 if portrait else 240.0), 0.0)
	side_column.size = Vector2.ZERO
	var side_size := side_column.get_combined_minimum_size()
	if portrait:
		side_column.position = Vector2(screen.x - side_size.x - margin, nav_bar.position.y + nav_bar.get_combined_minimum_size().y + 10.0)
	else:
		side_column.position = Vector2(screen.x - side_size.x - margin, 262.0)
	cannon_panel.size = Vector2.ZERO
	cannon_panel.position = Vector2(margin, screen.y - cannon_panel.get_combined_minimum_size().y - margin - (230.0 if touch else 0.0))
	controls_card.size = Vector2.ZERO
	var card := controls_card.get_combined_minimum_size()
	controls_card.position = Vector2((screen.x - card.x) * 0.5, screen.y - card.y - margin)
	race_board.size = Vector2(220, 0)
	race_board.position = Vector2((screen.x - 220.0) * 0.5, margin)
	approach_card.size = Vector2.ZERO
	var approach := approach_card.get_combined_minimum_size()
	var approach_y := screen.y * (0.62 if portrait else 0.7)
	if controls_card.visible:
		approach_y = minf(approach_y, controls_card.position.y - approach.y - 10.0)
	approach_card.position = Vector2((screen.x - approach.x) * 0.5, approach_y)
	if portrait:
		island_panel.position = Vector2(0.0, screen.y * 0.42)
		island_panel.size = Vector2(screen.x, screen.y * 0.58)
	else:
		var width := minf(460.0, screen.x * 0.4)
		var panel_top := side_column.position.y + side_size.y + 10.0
		island_panel.position = Vector2(screen.x - width - margin, panel_top)
		island_panel.size = Vector2(width, screen.y - panel_top - margin)
