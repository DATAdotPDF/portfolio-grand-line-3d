extends CanvasLayer

## HUD náutica "Clean / Glassmorphism" (referência: References/Meshy_AI_clean-
## nautical-hud-concept.png). Tudo 2D, StyleBoxFlat procedural (zero texturas),
## ícones vetoriais (HudIcon). As ilhas abrem um cartão de PERGAMINHO vertical
## (mais alto que largo, como o painel do Melon) com leitura paginada.
## Desktop: carta à direita, telemetria na base, Log Pose no canto inferior esquerdo.
## Mobile (<768 px ou retrato): carta vira um botão-selo; ilha vira gaveta inferior.

signal free_sail_pressed
signal island_pressed(index: int)
signal time_attack_pressed
signal time_mode_pressed(mode: String)
signal next_track_pressed
signal prev_track_pressed
signal toggle_music_pressed
signal panel_closed
signal start_sailing
signal challenge_confirmed
signal map_pressed
signal graphics_pressed(mode: String)

const Icon = preload("res://Scripts/UI/HudIcon.gd")
const CONTENT_PATH := "res://Config/portfolio_content.json"
const ISLAND_NAMES := ["Sobre", "Experiência", "Formação", "Projetos", "Contato"]

const ABYSS := Color("080f1e")
const GLASS := Color(0.114, 0.145, 0.216, 0.9)
const GLASS_EDGE := Color(0.937, 0.894, 0.8, 0.3)
const GOLD := Color("e7c27a")
const WHITE := Color("efe4cc")
const MIST := Color("a9b3c7")
const PAPER := Color("f2e6c8")
const PAPER_EDGE := Color("c9b48a")
const INK := Color("2b2118")
const INK_MUTED := Color("7a6a55")
const ACCENT := Color("9e1b2b")

var content: Dictionary = {}
var daylight := 1.0
var touch := false
var mobile := false
var root: Control
var fonts := {}

var dest_box: HBoxContainer
var dest_name: Label
var dest_sub: Label
var wind_box: VBoxContainer
var wind_label: Label
var carta: PanelContainer
var carta_open := false
var carta_button: Button
## Globo (só no toque): abre/fecha o mapa 3D, como a tecla M.
var map_button: Button
## Celular: painel da ilha recolhido mostra só o título e deixa a ilha à vista.
var panel_collapsed := false
var peek_button: Button
var island_extra: Array[Control] = []
var graphics_buttons := {}
var graphics_note: Label
var toast: PanelContainer
var toast_label: Label
var toast_tween: Tween
var island_rows: Array[Button] = []
var island_distances: Array[Label] = []
var mode_buttons: Array[Button] = []
var time_buttons: Array[Button] = []
var music_title: Label
var music_play_icon: Control
var telemetry: PanelContainer
var stat_speed: Label
var stat_distance: Label
var cannon_label: Label
var keys_box: HBoxContainer
var race_board: PanelContainer
var race_timer: Label
var race_count: Label
var island_panel: PanelContainer
var island_kicker: Label
var island_title: Label
var island_body: VBoxContainer
var page_label: Label
var page_prev: Button
var page_next: Button
var island_tabs: Array[Button] = []
var page_pager: HBoxContainer
var blocks: Array[Control] = []
var page_of: Array[int] = []
var page := 0
var page_count := 1
var panel_height := 400.0
var current_island := -1
var auto_opened := false
var dismissed_island := -1
var intro_panel: PanelContainer
var intro_column: VBoxContainer
var intro_visible := false
var map_layer: Control
var map_markers: Array[Control] = []
var map_hint: Label
var you_marker: Label
var live_projects: Array = []
var projects_request: HTTPRequest
## Ilhas já lidas (a bússola sugere a próxima).
var visited := {}
var controls_card: Control
var challenge_box: PanelContainer

func _ready() -> void:
	layer = 10
	touch = DisplayServer.is_touchscreen_available()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PATH))
	if parsed is Dictionary:
		content = parsed
	_load_fonts()
	root = Control.new()
	root.name = "SafeArea"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _build_theme()
	add_child(root)
	_build_destination()
	_build_wind()
	_build_carta()
	_build_telemetry()
	_build_race_board()
	_build_island_panel()
	_build_map_layer()
	_build_intro()
	_build_challenge_box()
	controls_card = Control.new()
	_fetch_projects()
	get_viewport().size_changed.connect(func(): _layout(); _relayout_next_frames())
	_layout()
	_relayout_next_frames()

# --- Estilo -----------------------------------------------------------------------

func _load_fonts() -> void:
	var base: Font = load("res://Assets/Fonts/Inter-Variable.ttf")
	var sans := FontVariation.new()
	sans.base_font = base
	sans.variation_opentype = {"wght": 400}
	var medium := FontVariation.new()
	medium.base_font = base
	medium.variation_opentype = {"wght": 560}
	var caps := FontVariation.new()
	caps.base_font = base
	caps.variation_opentype = {"wght": 500}
	caps.spacing_glyph = 3
	var mono := FontVariation.new()
	mono.base_font = load("res://Assets/Fonts/JetBrainsMono-Variable.ttf")
	mono.variation_opentype = {"wght": 500}
	fonts = {"sans": sans, "medium": medium, "caps": caps, "mono": mono,
		"serif": load("res://Assets/Fonts/IMFellEnglish-Regular.ttf"), "serif_italic": load("res://Assets/Fonts/IMFellEnglish-Italic.ttf")}

func _box(bg: Color, edge: Color, radius: int, pad: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = edge
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(pad)
	box.anti_aliasing = true
	return box

func _build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = fonts.sans
	theme.default_font_size = 14
	theme.set_color("font_color", "Label", WHITE)
	var normal := _box(Color(0, 0, 0, 0), Color(WHITE, 0.32), 1, 7)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	var hover := normal.duplicate()
	hover.border_color = Color(GOLD, 0.7)
	var active := normal.duplicate()
	active.bg_color = Color(GOLD, 0.12)
	active.border_color = GOLD
	for state in ["normal", "focus", "disabled"]:
		theme.set_stylebox(state, "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", active)
	theme.set_stylebox("hover_pressed", "Button", active)
	theme.set_color("font_color", "Button", WHITE)
	theme.set_color("font_hover_color", "Button", GOLD)
	theme.set_color("font_pressed_color", "Button", GOLD)
	theme.set_color("font_hover_pressed_color", "Button", GOLD)
	theme.set_color("font_disabled_color", "Button", Color(WHITE, 0.3))
	theme.set_font("font", "Button", fonts.medium)
	theme.set_font_size("font_size", "Button", 13)
	var empty := StyleBoxEmpty.new()
	theme.set_type_variation("Row", "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		theme.set_stylebox(state, "Row", empty)
	theme.set_font("font", "Row", fonts.sans)
	theme.set_font_size("font_size", "Row", 16)
	theme.set_type_variation("IconButton", "Button")
	var round := _box(Color(0, 0, 0, 0), Color(WHITE, 0.32), 1, 6)
	theme.set_stylebox("normal", "IconButton", round)
	theme.set_stylebox("hover", "IconButton", hover)
	theme.set_stylebox("pressed", "IconButton", active)
	theme.set_type_variation("Glass", "PanelContainer")
	var glass := _box(GLASS, GLASS_EDGE, 1, 20)
	glass.shadow_color = Color(0, 0, 0, 0.25)
	glass.shadow_size = 12
	theme.set_stylebox("panel", "Glass", glass)
	theme.set_type_variation("Pill", "PanelContainer")
	var pill := _box(GLASS, GLASS_EDGE, 1, 10)
	pill.content_margin_left = 22
	pill.content_margin_right = 22
	theme.set_stylebox("panel", "Pill", pill)
	theme.set_type_variation("Parchment", "PanelContainer")
	var parchment := _box(PAPER, PAPER_EDGE, 6, 26)
	parchment.shadow_color = Color(0, 0, 0, 0.3)
	parchment.shadow_size = 10
	parchment.shadow_offset = Vector2(0, 4)
	theme.set_stylebox("panel", "Parchment", parchment)
	var labels := [
		["Caps", fonts.caps, 11, MIST], ["Title", fonts.serif_italic, 30, WHITE], ["Gold", fonts.serif, 24, WHITE],
		["Stat", fonts.mono, 18, WHITE], ["Small", fonts.sans, 12, MIST], ["Body", fonts.sans, 14, WHITE],
		["Mono", fonts.mono, 12, MIST],
		["Heading", fonts.serif, 20, WHITE], ["Read", fonts.sans, 14, Color("d9dde6")], ["Accent", fonts.caps, 11, GOLD],
		["PCaps", fonts.caps, 11, INK_MUTED], ["PTitle", fonts.serif_italic, 30, INK], ["PHeading", fonts.serif, 21, INK],
		["PBody", fonts.sans, 14, INK], ["PMono", fonts.mono, 12, INK_MUTED],
	]
	for l in labels:
		theme.set_type_variation(l[0], "Label")
		if not str(l[0]).begins_with("P"):
			# Sombra leve: texto sobre o céu claro do dia continua legível.
			theme.set_color("font_shadow_color", l[0], Color(0.05, 0.07, 0.13, 0.45))
			theme.set_constant("shadow_offset_x", l[0], 0)
			theme.set_constant("shadow_offset_y", l[0], 1)
			theme.set_constant("shadow_outline_size", l[0], 2)
		theme.set_font("font", l[0], l[1])
		theme.set_font_size("font_size", l[0], l[2])
		theme.set_color("font_color", l[0], l[3])
	theme.set_type_variation("Ink", "Button")
	var ink := _box(Color(0, 0, 0, 0), Color(INK, 0.4), 4, 7)
	ink.content_margin_left = 12
	ink.content_margin_right = 12
	var ink_hover := ink.duplicate()
	ink_hover.border_color = ACCENT
	for state in ["normal", "focus", "disabled"]:
		theme.set_stylebox(state, "Ink", ink)
	theme.set_stylebox("hover", "Ink", ink_hover)
	var ink_active := ink.duplicate()
	ink_active.bg_color = Color(INK, 0.9)
	ink_active.border_color = INK
	theme.set_stylebox("pressed", "Ink", ink_active)
	theme.set_stylebox("hover_pressed", "Ink", ink_active)
	theme.set_color("font_hover_pressed_color", "Ink", PAPER)
	theme.set_color("font_color", "Ink", INK)
	theme.set_color("font_hover_color", "Ink", ACCENT)
	theme.set_color("font_pressed_color", "Ink", PAPER)
	theme.set_color("font_disabled_color", "Ink", Color(INK, 0.25))
	theme.set_type_variation("Rule", "HSeparator")
	var rule := StyleBoxLine.new()
	rule.color = Color(1, 1, 1, 0.14)
	theme.set_stylebox("separator", "Rule", rule)
	theme.set_type_variation("PRule", "HSeparator")
	var prule := StyleBoxLine.new()
	prule.color = Color(INK, 0.22)
	theme.set_stylebox("separator", "PRule", prule)
	theme.set_type_variation("Primary", "Button")
	var primary := _box(WHITE, WHITE, 1, 9)
	primary.content_margin_left = 18
	primary.content_margin_right = 18
	var primary_hover := primary.duplicate()
	primary_hover.bg_color = GOLD
	primary_hover.border_color = GOLD
	theme.set_stylebox("normal", "Primary", primary)
	theme.set_stylebox("hover", "Primary", primary_hover)
	theme.set_stylebox("pressed", "Primary", primary_hover)
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		theme.set_color(key, "Primary", ABYSS)
	theme.set_font_size("font_size", "Primary", 14)
	return theme

# --- Peças ---------------------------------------------------------------------------

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
	if action.is_valid():
		button.pressed.connect(action)
	return button

## Botão com ícone vetorial (+ texto opcional).
func _icon_button(kind: String, text: String, action: Callable) -> Button:
	var button := _button(("      " + text) if text != "" else "", action, "" if text != "" else "IconButton")
	button.custom_minimum_size = Vector2(34, 32) if text == "" else Vector2(0, 32)
	var icon := Icon.new(kind, 14.0, GOLD)
	icon.position = Vector2(12, 9) if text != "" else Vector2(10, 9)
	button.add_child(icon)
	return button

func _rule(paper := false) -> HSeparator:
	var line := HSeparator.new()
	line.theme_type_variation = "PRule" if paper else "Rule"
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line

func _link(text: String, url: String, variation := "") -> Button:
	return _button(text + "  ↗", func(): OS.shell_open(url), variation)

func _vsep() -> VSeparator:
	var sep := VSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color(1, 1, 1, 0.16)
	line.vertical = true
	sep.add_theme_stylebox_override("separator", line)
	return sep

# --- Construção ----------------------------------------------------------------------

func _build_destination() -> void:
	dest_box = HBoxContainer.new()
	dest_box.add_theme_constant_override("separation", 14)
	dest_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dest_box)
	dest_box.add_child(Icon.new("compass", 40.0, GOLD))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	dest_box.add_child(column)
	dest_name = _label("Mar aberto", "Title")
	dest_name.add_theme_font_override("font", fonts.serif)
	column.add_child(dest_name)
	dest_sub = _label("", "Caps")
	column.add_child(dest_sub)

func _build_wind() -> void:
	wind_box = VBoxContainer.new()
	wind_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(wind_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	wind_box.add_child(row)
	row.add_child(Icon.new("wind", 16.0, MIST))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	row.add_child(column)
	column.add_child(_label("VENTO", "Caps", 9))
	wind_label = _label("—", "Body", 13)
	column.add_child(wind_label)

func _build_carta() -> void:
	carta = PanelContainer.new()
	carta.theme_type_variation = "Glass"
	root.add_child(carta)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	carta.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	header.add_child(_label("A CARTA", "Caps", 13))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header.add_child(Icon.new("boat", 16.0, GOLD))
	column.add_child(_rule())
	for i in range(ISLAND_NAMES.size()):
		var row := HBoxContainer.new()
		column.add_child(row)
		var button := _button("%d.   %s" % [i + 1, ISLAND_NAMES[i]], island_pressed.emit.bind(i), "Row")
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(button)
		island_rows.append(button)
		var distance := _label("", "Mono", 11)
		row.add_child(distance)
		island_distances.append(distance)
	column.add_child(_rule())
	column.add_child(_label("MODO", "Caps"))
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 6)
	column.add_child(modes)
	var sail := _icon_button("boat", "Navegar", func(): free_sail_pressed.emit())
	var race := _icon_button("flag", "Desafio", func(): time_attack_pressed.emit())
	for b in [sail, race]:
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		modes.add_child(b)
		mode_buttons.append(b)
	sail.button_pressed = true
	column.add_child(_label("CICLO", "Caps"))
	var times := HBoxContainer.new()
	times.add_theme_constant_override("separation", 6)
	column.add_child(times)
	for entry in [["auto", "cycle", "Auto"], ["day", "sun", "Dia"], ["night", "moon", "Noite"]]:
		var button := _icon_button(entry[1], entry[2], time_mode_pressed.emit.bind(entry[0]))
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		times.add_child(button)
		time_buttons.append(button)
	column.add_child(_label("GRÁFICOS", "Caps"))
	var quality := HBoxContainer.new()
	quality.add_theme_constant_override("separation", 4)
	column.add_child(quality)
	for entry in [["auto", "Auto"], ["alto", "Alto"], ["medio", "Médio"], ["baixo", "Baixo"]]:
		var button := _button(entry[1], graphics_pressed.emit.bind(entry[0]))
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 12)
		quality.add_child(button)
		graphics_buttons[entry[0]] = button
	graphics_note = _label("", "Mono", 11)
	column.add_child(graphics_note)
	column.add_child(_rule())
	column.add_child(_label("CONTROLES", "Caps"))
	var guide := _wrap(_controls_text(), "Small", 12)
	guide.visible = false
	var guide_button := _button("Ver como jogar", Callable())
	guide_button.pressed.connect(func():
		guide.visible = not guide.visible
		guide_button.text = "Ocultar controles" if guide.visible else "Ver como jogar"
		_relayout_next_frames())
	column.add_child(guide_button)
	column.add_child(guide)
	column.add_child(_rule())
	column.add_child(_label("MÚSICA", "Caps"))
	var player := HBoxContainer.new()
	player.add_theme_constant_override("separation", 6)
	column.add_child(player)
	player.add_child(_icon_button("prev", "", func(): prev_track_pressed.emit()))
	var toggle := _icon_button("pause", "", func(): toggle_music_pressed.emit())
	music_play_icon = toggle.get_child(0)
	player.add_child(toggle)
	player.add_child(_icon_button("next", "", func(): next_track_pressed.emit()))
	music_title = _label("—", "Small")
	music_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_title.clip_text = true
	music_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	music_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	player.add_child(music_title)
	column.add_child(_rule())
	var socials := HBoxContainer.new()
	socials.alignment = BoxContainer.ALIGNMENT_CENTER
	socials.add_theme_constant_override("separation", 6)
	column.add_child(socials)
	var links: Dictionary = content.get("links", {})
	for item in [["LinkedIn", "linkedin"], ["GitHub", "github"], ["WhatsApp", "whatsapp"]]:
		if links.has(item[1]):
			var link := _link(item[0], str(links[item[1]]))
			link.add_theme_font_size_override("font_size", 12)
			socials.add_child(link)
	carta_button = _icon_button("menu", "", func(): _set_carta_open(not carta_open))
	carta_button.custom_minimum_size = Vector2(46, 46)
	carta_button.get_child(0).position = Vector2(14, 15)
	root.add_child(carta_button)
	map_button = _icon_button("globe", "", func(): map_pressed.emit())
	map_button.custom_minimum_size = Vector2(46, 46)
	map_button.get_child(0).custom_minimum_size = Vector2(18, 18)
	map_button.get_child(0).size = Vector2(18, 18)
	map_button.get_child(0).position = Vector2(14, 14)
	map_button.visible = false
	root.add_child(map_button)

## Estado do menu de gráficos: modo escolhido + nível em uso agora.
func set_graphics_state(mode: String, tier_name: String) -> void:
	for key in graphics_buttons:
		graphics_buttons[key].button_pressed = key == mode
	if graphics_note:
		graphics_note.text = ("Automático · agora em %s" % tier_name) if mode == "auto" else ("Fixo em %s" % tier_name)

## Aviso curto no topo da tela (some sozinho).
func show_toast(text: String) -> void:
	if toast == null:
		toast = PanelContainer.new()
		toast.theme_type_variation = "Pill"
		toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		toast_label = _label("", "Small", 13)
		toast.add_child(toast_label)
		root.add_child(toast)
	toast_label.text = text
	toast.visible = true
	toast.modulate.a = 1.0
	if toast_tween:
		toast_tween.kill()
	toast_tween = create_tween()
	toast_tween.tween_interval(4.5)
	toast_tween.tween_property(toast, "modulate:a", 0.0, 0.8)
	toast_tween.tween_callback(func(): toast.visible = false)
	toast.size = Vector2.ZERO
	var screen := get_viewport().get_visible_rect().size
	toast.position = Vector2((screen.x - toast.get_combined_minimum_size().x) * 0.5, 84.0)

func _controls_text() -> String:
	if touch:
		return "\n".join([
			"Joystick esquerdo — leme e velas (no limite, acelera)",
			"Joystick direito — sobe e desce a mira do canhão",
			"IMPULSO — segure para ganhar velocidade",
			"FOGO — dispara o canhão nas boias",
			"Dois dedos — giram a câmera",
			"Globo (canto superior) — mapa 3D; arraste para girar",
			"Na ilha, 'Ver ilha' recolhe o texto",
			"Um dedo na água — faz ondas",
			"Chegue perto de uma ilha para abrir a seção"])
	return "\n".join([
		"W A S D — navegar",
		"Shift — impulso",
		"R / F — sobe e desce a mira",
		"Espaço — dispara o canhão",
		"M ou Tab — mapa  ·  1–5 — visitar ilha",
		"Arrastar na água — faz ondas",
		"Chegue perto de uma ilha para abrir a seção"])

func _set_carta_open(open: bool) -> void:
	carta_open = open
	_layout()

func _build_telemetry() -> void:
	telemetry = PanelContainer.new()
	telemetry.theme_type_variation = "Pill"
	telemetry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(telemetry)
	# No toque a barra fica compacta: cabe entre os joysticks sem cortar.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8 if touch else 16)
	telemetry.add_child(row)
	var items := [["boat", "VELOCIDADE"], ["pin", "DISTÂNCIA"], ["cannon", "CANHÃO"]]
	var values: Array[Label] = []
	for i in range(items.size()):
		if i > 0:
			row.add_child(_vsep())
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 5 if touch else 10)
		row.add_child(cell)
		cell.add_child(Icon.new(items[i][0], 13.0 if touch else 20.0, WHITE))
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 0)
		cell.add_child(column)
		column.add_child(_label(items[i][1], "Caps", 7 if touch else 9))
		var value := _label("—", "Stat", 12 if touch else 0)
		column.add_child(value)
		values.append(value)
	stat_speed = values[0]
	stat_distance = values[1]
	cannon_label = values[2]
	keys_box = HBoxContainer.new()
	keys_box.add_theme_constant_override("separation", 5)
	keys_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(keys_box)
	for entry in [[["W", "A", "S", "D"], "Leme"], [["Shift"], "Impulso"], [["R", "F"], "Mira"], [["Espaço"], "Canhão"], [["M"], "Mapa"]]:
		for key in entry[0]:
			var cap := PanelContainer.new()
			cap.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.45), 4, 3))
			cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var label := _label(key, "Small", 10)
			label.add_theme_color_override("font_color", WHITE)
			cap.add_child(label)
			keys_box.add_child(cap)
		keys_box.add_child(_label(entry[1], "Small", 11))
		var gap := Control.new()
		gap.custom_minimum_size.x = 8
		keys_box.add_child(gap)

func _build_race_board() -> void:
	race_board = PanelContainer.new()
	race_board.theme_type_variation = "Pill"
	race_board.visible = false
	race_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(race_board)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	race_board.add_child(row)
	row.add_child(Icon.new("flag", 18.0, GOLD))
	race_timer = _label("03:00", "Gold", 26)
	row.add_child(race_timer)
	row.add_child(_vsep())
	race_count = _label("boias 00 / 20", "Body")
	row.add_child(race_count)

func _build_island_panel() -> void:
	island_panel = PanelContainer.new()
	island_panel.theme_type_variation = "Glass"
	island_panel.visible = false
	island_panel.clip_contents = true
	root.add_child(island_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	island_panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	island_kicker = _label("", "Accent")
	header.add_child(island_kicker)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	peek_button = _button("Ver ilha", func(): _set_panel_collapsed(not panel_collapsed))
	peek_button.add_theme_font_size_override("font_size", 12)
	peek_button.visible = false
	header.add_child(peek_button)
	var close := _button("", func(): _close_island())
	close.custom_minimum_size = Vector2(30, 28)
	var x := Icon.new("close", 12.0, GOLD)
	x.position = Vector2(9, 8)
	close.add_child(x)
	header.add_child(close)
	island_title = _wrap("", "Title")
	column.add_child(island_title)
	column.add_child(_rule())
	island_body = VBoxContainer.new()
	island_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	island_body.add_theme_constant_override("separation", 12)
	island_body.clip_contents = true
	column.add_child(island_body)
	column.add_child(_rule())
	# Páginas da ilha atual (só aparece se algum dia o conteúdo não couber).
	var pager := HBoxContainer.new()
	pager.visible = false
	page_pager = pager
	pager.alignment = BoxContainer.ALIGNMENT_CENTER
	pager.add_theme_constant_override("separation", 8)
	column.add_child(pager)
	page_prev = _button("‹", func(): _show_page(page - 1))
	pager.add_child(page_prev)
	page_label = _label("1 / 1", "Mono")
	pager.add_child(page_label)
	page_next = _button("›", func(): _show_page(page + 1))
	pager.add_child(page_next)
	# As 5 ilhas pelo nome (a atual destacada): ir direto a qualquer uma.
	var tabs := HFlowContainer.new()
	tabs.alignment = FlowContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("h_separation", 4)
	tabs.add_theme_constant_override("v_separation", 4)
	column.add_child(tabs)
	for i in range(ISLAND_NAMES.size()):
		var tab := _button(ISLAND_NAMES[i], island_pressed.emit.bind(i))
		tab.toggle_mode = true
		tab.add_theme_font_size_override("font_size", 12)
		tabs.add_child(tab)
		island_tabs.append(tab)
	# Recolhido: ficam o cabeçalho, o título e as abas das ilhas (dá para trocar de ilha olhando).
	for child in column.get_children():
		if child != header and child != island_title and child != tabs:
			island_extra.append(child)

func _set_panel_collapsed(collapsed: bool) -> void:
	if collapsed == panel_collapsed:
		return
	panel_collapsed = collapsed
	for child in island_extra:
		if collapsed:
			child.set_meta("was_visible", child.visible)
			child.visible = false
		else:
			child.visible = bool(child.get_meta("was_visible", true))
	peek_button.text = "Ler" if collapsed else "Ver ilha"
	_layout()

func _build_map_layer() -> void:
	map_layer = Control.new()
	map_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_layer.visible = false
	root.add_child(map_layer)
	for i in range(ISLAND_NAMES.size()):
		var marker := _button(ISLAND_NAMES[i], island_pressed.emit.bind(i))
		marker.add_theme_stylebox_override("normal", _box(GLASS, Color(GOLD, 0.7), 14, 6))
		map_layer.add_child(marker)
		map_markers.append(marker)
	you_marker = _label("VOCÊ", "Caps", 11)
	you_marker.add_theme_color_override("font_color", Color("ff6070"))
	map_layer.add_child(you_marker)
	map_hint = _label("ARRASTE PARA GIRAR  ·  TOQUE NUMA ILHA" if touch else "MAPA  ·  ARRASTE PARA GIRAR O GLOBO  ·  CLIQUE NUMA ILHA  ·  M VOLTA AO BARCO", "Caps", 11 if touch else 12)
	map_layer.add_child(map_hint)

func _build_intro() -> void:
	intro_panel = PanelContainer.new()
	intro_panel.theme_type_variation = "Glass"
	intro_panel.visible = false
	root.add_child(intro_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	intro_panel.add_child(column)
	intro_column = column
	var status := _label("●  " + str(content.get("status", "Portfólio")).to_upper(), "Caps")
	column.add_child(status)
	column.add_child(_label(str(content.get("name", "Pedro D. Ferreira")), "Title", 64))
	column.add_child(_wrap(str(content.get("role", "")), "Gold", 24))
	column.add_child(_wrap(str(content.get("tagline", "")).to_upper(), "Caps"))
	column.add_child(_wrap(str(content.get("pitch", "")), "Body", 15))
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 28)
	for stat in content.get("stats", []):
		var block := VBoxContainer.new()
		block.add_child(_label(str(stat.value), "Stat", 24))
		block.add_child(_label(str(stat.label), "Small"))
		stats.add_child(block)
	column.add_child(stats)
	column.add_child(_rule())
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	column.add_child(actions)
	actions.add_child(_button("Zarpar e navegar", func(): start_sailing.emit(), "Primary"))
	actions.add_child(_button("Explorar as ilhas", func(): island_pressed.emit(0)))
	actions.add_child(_button("Desafio · 3 min", func(): time_attack_pressed.emit()))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)
	var links: Dictionary = content.get("links", {})
	for item in [["LinkedIn", "linkedin"], ["GitHub", "github"], ["WhatsApp", "whatsapp"]]:
		if links.has(item[1]):
			row.add_child(_link(item[0], str(links[item[1]])))
	column.add_child(_wrap("Toque nos controles da tela para navegar." if touch else "W A S D para navegar  ·  1–5 visita uma ilha  ·  M abre o mapa", "Mono"))

## Caixa do Desafio: explica a regra antes de começar.
func _build_challenge_box() -> void:
	challenge_box = PanelContainer.new()
	challenge_box.theme_type_variation = "Glass"
	challenge_box.visible = false
	root.add_child(challenge_box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.custom_minimum_size.x = 380
	challenge_box.add_child(column)
	column.add_child(_label("DESAFIO  ·  TIME ATTACK", "Accent"))
	column.add_child(_label("20 boias em 3 minutos", "Title", 34))
	column.add_child(_wrap("As boias do desafio estão em volta da ilha Sobre. Acerte todas com o canhão antes que o tempo acabe.", "Read"))
	var how := "Mire com o joystick direito e toque em FOGO. Navegue com o joystick esquerdo." if touch else "R e F inclinam o canhão  ·  Espaço dispara  ·  W A S D navegam"
	column.add_child(_wrap(how, "Mono"))
	column.add_child(_rule())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	row.add_child(_button("Começar", func(): challenge_box.visible = false; challenge_confirmed.emit(), "Primary"))
	row.add_child(_button("Agora não", func(): challenge_box.visible = false))

func show_challenge_box() -> void:
	if intro_visible:
		show_intro(false)
	hide_island()
	challenge_box.visible = true
	_layout()
	_relayout_next_frames()

# --- Abertura -------------------------------------------------------------------------

func show_intro(show: bool) -> void:
	intro_visible = show
	intro_panel.visible = show
	_layout()
	_relayout_next_frames()

func _relayout_next_frames() -> void:
	for i in range(2):
		await get_tree().process_frame
		_layout()

# --- Cartão de pergaminho das ilhas ----------------------------------------------------

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
	for i in range(island_tabs.size()):
		island_tabs[i].button_pressed = i == index
	island_kicker.text = str(data.get("kicker", "")).to_upper()
	island_title.text = str(data.get("title", ""))
	for paragraph in data.get("paragraphs", []):
		_block([_wrap(str(paragraph), "Read")])
	var facts: Array = data.get("facts", [])
	if not facts.is_empty():
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 8)
		for fact in facts:
			var cell := VBoxContainer.new()
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.add_child(_label(str(fact.label).to_upper(), "Accent"))
			cell.add_child(_wrap(str(fact.value), "Mono"))
			grid.add_child(cell)
		_block([grid])
	for entry in data.get("entries", []):
		var parts: Array = [_label(str(entry.period), "Mono"), _wrap(str(entry.title), "Heading"), _label(str(entry.org).to_upper(), "Accent")]
		if str(entry.get("text", "")) != "":
			parts.append(_wrap(str(entry.text), "Read"))
		_block(parts)
	var is_projects := str(data.get("id", "")) == "projetos"
	if is_projects and not live_projects.is_empty():
		_block([_label("ÚLTIMOS NO GITHUB  ·  ATUALIZA SOZINHO", "Accent")])
		for project in live_projects:
			var meta: PackedStringArray = []
			if str(project.get("language", "")) != "":
				meta.append(str(project.language))
			for topic in project.get("topics", []):
				meta.append(str(topic))
			var pushed := str(project.get("pushed_at", ""))
			if pushed.length() >= 10:
				meta.append("%s/%s/%s" % [pushed.substr(8, 2), pushed.substr(5, 2), pushed.substr(0, 4)])
			var title := _button(str(project.name).replace("_", " ").replace("-", " ") + "  ↗", OS.shell_open.bind(str(project.url)), "Row")
			title.alignment = HORIZONTAL_ALIGNMENT_LEFT
			title.add_theme_font_override("font", fonts.serif)
			title.add_theme_font_size_override("font_size", 19)
			var parts: Array = [title]
			if str(project.get("description", "")) != "":
				parts.append(_wrap(str(project.description), "Read"))
			parts.append(_wrap("  ·  ".join(meta), "Mono"))
			_block(parts)
	else:
		for project in data.get("projects", []):
			var title := _button(str(project.title) + "  ↗", OS.shell_open.bind(str(project.url)), "Row")
			title.alignment = HORIZONTAL_ALIGNMENT_LEFT
			title.add_theme_font_override("font", fonts.serif)
			title.add_theme_font_size_override("font_size", 19)
			_block([title, _wrap(str(project.text), "Read"), _wrap("  ·  ".join(PackedStringArray(project.get("stack", []))), "Mono")])
	var links: Dictionary = content.get("links", {})
	var contact_buttons: Array = []
	for contact in data.get("contacts", []):
		contact_buttons.append(_link(str(contact.label), str(links.get(contact.key, ""))))
	if not contact_buttons.is_empty():
		_block(contact_buttons)
	if is_projects and links.has("github_repos"):
		_block([_link("Todos os projetos", str(links.github_repos))])
	_set_panel_collapsed(false)
	island_panel.visible = true
	_layout()
	_fit_one_page()

## Cada seção numa página só: se não couber, reduz fonte e espaçamento até caber.
func _fit_one_page() -> void:
	page_count = 1
	page = 0
	for block in blocks:
		block.visible = true
	var scale := 1.0
	for attempt in range(7):
		_apply_read_scale(scale)
		for i in range(2):
			await get_tree().process_frame
		if not is_instance_valid(island_body):
			return
		var used := 0.0
		for block in blocks:
			used += block.get_combined_minimum_size().y + float(island_body.get_theme_constant("separation"))
		var column := island_body.get_parent() as Control
		var chrome := column.get_combined_minimum_size().y - island_body.get_combined_minimum_size().y
		var available := panel_height - 40.0 - chrome
		if used <= available:
			break
		scale -= 0.07
	_layout()

func _apply_read_scale(scale: float) -> void:
	island_body.add_theme_constant_override("separation", int(12.0 * scale))
	var sizes := {"Read": 14, "Heading": 20, "Mono": 12, "Accent": 11}
	for label in island_body.find_children("*", "Label", true, false):
		var base: int = sizes.get(str(label.theme_type_variation), 14)
		label.add_theme_font_size_override("font_size", maxi(9, int(round(base * scale))))
	for button in island_body.find_children("*", "Button", true, false):
		button.add_theme_font_size_override("font_size", maxi(11, int(round(19 * scale))))

## Distribui os blocos em páginas que cabem no cartão (leitura sem rolagem).
func _paginate() -> void:
	for block in blocks:
		block.visible = false
	await get_tree().process_frame
	if not is_instance_valid(island_body):
		return
	var column := island_body.get_parent() as Control
	var chrome := column.get_combined_minimum_size().y
	var available := maxf(panel_height - 52.0 - chrome + 8.0, 120.0)
	for block in blocks:
		block.visible = true
	for i in range(3):
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

## Ilha mais próxima quando o barco está BEM perto (ou -1): abre sozinho e fecha ao se afastar.
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

# --- GitHub ao vivo ----------------------------------------------------------------------

func _fetch_projects() -> void:
	var user := str(content.get("links", {}).get("github_user", "DATAdotPDF"))
	if OS.has_feature("web"):
		# No navegador, fetch nativo (HTTPRequest com User-Agent falhava e caía na lista fixa).
		JavaScriptBridge.eval("window.__portfolioProjects = null; fetch('/api/projetos').then(r => r.text()).then(t => { window.__portfolioProjects = t; }).catch(() => { window.__portfolioProjects = ''; });", true)
		for i in range(40):
			await get_tree().create_timer(0.25).timeout
			var result: Variant = JavaScriptBridge.eval("window.__portfolioProjects", true)
			if result != null:
				if str(result) != "":
					_on_projects_loaded(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), str(result).to_utf8_buffer(), user)
				return
		return
	var url := "https://api.github.com/users/%s/repos?sort=pushed&direction=desc&per_page=30" % user
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
			if list.size() >= 4:
				break
	live_projects = list
	if island_panel.visible and current_island == 3:
		show_island(3, auto_opened)

# --- Estado vindo do jogo -------------------------------------------------------------------

func _distance_text(meters: float) -> String:
	return "%.1f km" % (meters / 1000.0) if meters >= 1000.0 else "%d m" % int(meters)

func set_status(_section: String, distance: float, speed: float, _fps: int) -> void:
	stat_speed.text = "%.1f m/s" % speed
	stat_distance.text = _distance_text(distance)

func set_route(target_name: String, distance: float) -> void:
	dest_name.text = ("%s  ·  %s" % [target_name, _distance_text(distance)]) if target_name != "" else "Mar aberto"
	dest_sub.text = ("RUMO À %s" % target_name.to_upper()) if target_name != "" else ""

func set_island_distances(distances: Array) -> void:
	for i in range(mini(distances.size(), island_distances.size())):
		island_distances[i].text = "lida" if visited.has(i) else _distance_text(float(distances[i]))

func set_wind(text: String) -> void:
	wind_label.text = text

func set_time_mode(mode: String) -> void:
	for i in range(time_buttons.size()):
		time_buttons[i].button_pressed = ["auto", "day", "night"][i] == mode

func set_mode(regata: bool) -> void:
	if mode_buttons.size() == 2:
		mode_buttons[0].button_pressed = not regata
		mode_buttons[1].button_pressed = regata

func set_track(name: String) -> void:
	music_title.text = name

func set_music_playing(playing: bool) -> void:
	if music_play_icon:
		music_play_icon.kind = "pause" if playing else "play"

func set_race(active: bool, remaining: float, hits: int, total: int, finished_text := "") -> void:
	race_board.visible = active and not intro_visible
	set_mode(active)
	if not active:
		return
	var seconds := ceili(remaining)
	race_timer.text = finished_text if finished_text != "" else "%02d:%02d" % [floori(seconds / 60.0), seconds % 60]
	race_count.text = "boias %02d / %02d" % [hits, total]

## Mapa (M): marcadores 2D sobre as ilhas vistas do espaço.
func update_map(camera: Camera3D, islands: Array, show: bool, ship: Node3D = null) -> void:
	var was := map_layer.visible
	map_layer.visible = show and not intro_visible
	if was != map_layer.visible:
		_layout()
	if not map_layer.visible or camera == null:
		return
	for i in range(mini(islands.size(), map_markers.size())):
		var island: Node3D = islands[i]
		var to_camera := (camera.global_position - island.global_position).normalized()
		var marker := map_markers[i]
		marker.visible = island.global_position.normalized().dot(to_camera) > 0.05 and not camera.is_position_behind(island.global_position)
		if marker.visible:
			marker.size = Vector2.ZERO
			marker.position = camera.unproject_position(island.global_position) - Vector2(marker.get_combined_minimum_size().x * 0.5, 44.0)
	if ship:
		var ship_top := ship.global_position + ship.global_position.normalized() * 75.0
		you_marker.visible = ship.global_position.normalized().dot((camera.global_position - ship.global_position).normalized()) > 0.05
		you_marker.position = camera.unproject_position(ship_top) - Vector2(16, 18)
	var screen := get_viewport().get_visible_rect().size
	map_hint.size = Vector2.ZERO
	map_hint.position = Vector2((screen.x - map_hint.get_combined_minimum_size().x) * 0.5, screen.y - 46.0)

func notify_player_input() -> void:
	pass

func set_daylight(value: float) -> void:
	daylight = value

# --- Layout ----------------------------------------------------------------------------------

func _layout() -> void:
	if root == null or intro_panel == null or map_layer == null:
		return
	var screen := get_viewport().get_visible_rect().size
	mobile = screen.x < 768.0 or screen.y > screen.x
	var margin := 16.0 if mobile else 28.0
	var playing := not intro_visible and not map_layer.visible
	if map_layer.visible and island_panel.visible:
		island_panel.visible = false
	var reading := island_panel.visible
	var touch_reserve := 250.0 if touch else 0.0
	dest_box.visible = playing
	dest_box.size = Vector2.ZERO
	dest_box.position = Vector2(margin, margin)
	dest_name.add_theme_font_size_override("font_size", 20 if mobile else 28)
	wind_box.visible = playing and not mobile and not island_panel.visible
	wind_box.size = Vector2.ZERO
	wind_box.position = Vector2(screen.x - wind_box.get_combined_minimum_size().x - margin, margin)
	carta_button.visible = playing and mobile and not reading
	carta_button.position = Vector2(screen.x - 46.0 - margin, margin)
	map_button.visible = touch and not intro_visible and not reading and (playing or map_layer.visible)
	map_button.position = Vector2(screen.x - (46.0 * 2.0 + 8.0) - margin, margin) if carta_button.visible else Vector2(screen.x - 46.0 - margin, margin)
	peek_button.visible = mobile
	carta.visible = playing and not reading and (not mobile or carta_open)
	carta.size = Vector2.ZERO
	carta.custom_minimum_size.x = 300.0 if not mobile else minf(300.0, screen.x - margin * 2.0)
	var carta_size := carta.get_combined_minimum_size()
	if mobile:
		carta.position = Vector2(screen.x - carta_size.x - margin, margin + 56.0)
	else:
		carta.position = Vector2(screen.x - carta_size.x - margin, clampf((screen.y - carta_size.y) * 0.5, margin + 56.0, maxf(margin + 56.0, screen.y - carta_size.y - margin)))
	# No celular a carta aberta cobre a barra de dados: esconde a barra enquanto isso.
	telemetry.visible = playing and not (mobile and (reading or (carta_open and carta.visible)))
	telemetry.size = Vector2.ZERO
	var tel := telemetry.get_combined_minimum_size()
	if mobile:
		# Um pouco à direita do centro para não cobrir a bússola (Log Pose) no canto esquerdo.
		telemetry.position = Vector2(minf((screen.x - tel.x) * 0.5 + 18.0, screen.x - tel.x - 6.0), screen.y - tel.y - margin - touch_reserve)
	else:
		telemetry.position = Vector2(margin + 140.0, screen.y - tel.y - margin)
	keys_box.size = Vector2.ZERO
	var keys := keys_box.get_combined_minimum_size()
	keys_box.position = Vector2(telemetry.position.x + tel.x + 24.0, telemetry.position.y + (tel.y - keys.y) * 0.5)
	var keys_room := (screen.x - carta_size.x - margin * 2.0) if carta.visible and carta.position.y + carta_size.y > keys_box.position.y else screen.x - margin
	keys_box.visible = playing and not mobile and not touch and keys_box.position.x + keys.x < keys_room
	race_board.size = Vector2.ZERO
	race_board.position = Vector2((screen.x - race_board.get_combined_minimum_size().x) * 0.5, margin)
	if mobile:
		var top := screen.y * 0.16
		panel_height = screen.y - top - (touch_reserve + 8.0 if touch else margin)
		island_panel.position = Vector2(8.0, top)
		if panel_collapsed:
			# Só o título no topo: a ilha fica visível embaixo.
			island_panel.size = Vector2(screen.x - 16.0, 0.0)
			island_panel.position = Vector2(8.0, margin + 56.0)
		else:
			island_panel.size = Vector2(screen.x - 16.0, panel_height)
		island_title.add_theme_font_size_override("font_size", 24)
	else:
		var width := clampf(screen.x * 0.32, 360.0, 440.0)
		panel_height = screen.y - margin * 2.0
		island_panel.position = Vector2(screen.x - width - margin, (screen.y - panel_height) * 0.5)
		island_panel.size = Vector2(width, panel_height)
		island_title.add_theme_font_size_override("font_size", 30)
	if challenge_box:
		challenge_box.size = Vector2(440, 0)
		var box := challenge_box.get_combined_minimum_size()
		challenge_box.size = box
		challenge_box.position = (screen - box) * 0.5
	var intro_width := (screen.x - margin * 2.0) if mobile else minf(560.0, screen.x - margin * 2.0)
	intro_column.custom_minimum_size.x = intro_width - 36.0
	intro_panel.size = Vector2.ZERO
	intro_panel.size = Vector2(intro_width, 0.0)
	if mobile:
		intro_panel.position = Vector2(margin, screen.y - intro_panel.get_combined_minimum_size().y - margin)
	else:
		intro_panel.position = Vector2(margin * 2.0, (screen.y - intro_panel.get_combined_minimum_size().y) * 0.5)
