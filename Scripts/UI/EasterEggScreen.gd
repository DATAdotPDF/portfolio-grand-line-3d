extends CanvasLayer

## Cartão dos easter eggs (navio fantasma → Baú do Davy Jones; kraken → naufrágio): folha de
## papel no meio da tela com chamada, título, texto, números da viagem e links do Pedro.
## O barco fica parado enquanto o cartão está aberto; "Voltar ao mar" fecha e chama on_close.

const HudTheme = preload("res://Scripts/UI/HudTheme.gd")
const CONTENT_PATH := "res://Config/portfolio_content.json"

var world: Node3D
var panel: PanelContainer
var on_close := Callable()

func _ready() -> void:
	layer = 20
	visible = false

## stats: [[rótulo, valor], ...]
func show_card(kicker: String, title: String, paragraphs: Array, stats: Array, close_text: String, closed: Callable) -> void:
	on_close = closed
	for child in get_children():
		child.queue_free()
	var colors := HudTheme.palette(1.0)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.theme = HudTheme.build_theme(colors)
	add_child(center)
	panel = PanelContainer.new()
	var box := HudTheme.paper_box(colors, 0.97)
	box.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", box)
	var screen := get_viewport().get_visible_rect().size
	panel.custom_minimum_size = Vector2(minf(560.0, screen.x - 32.0), 0)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	column.add_child(_label(kicker.to_upper(), HudTheme.font("label"), 11, colors.accent))
	var heading := _label(title, HudTheme.font("display_italic"), 34 if screen.x > 600 else 26, colors.ink)
	column.add_child(heading)
	if not stats.is_empty():
		var grid := GridContainer.new()
		grid.columns = mini(stats.size(), 3)
		grid.add_theme_constant_override("h_separation", 22)
		column.add_child(grid)
		for stat in stats:
			var cell := VBoxContainer.new()
			cell.add_theme_constant_override("separation", 0)
			var caption := _label(String(stat[0]).to_upper(), HudTheme.font("label"), 9, colors.muted)
			var value := _label(String(stat[1]), HudTheme.font("mono"), 18, colors.ink)
			# Números não quebram linha (no grid sem largura mínima viravam uma letra por linha).
			caption.autowrap_mode = TextServer.AUTOWRAP_OFF
			value.autowrap_mode = TextServer.AUTOWRAP_OFF
			cell.add_child(caption)
			cell.add_child(value)
			grid.add_child(cell)
	for text in paragraphs:
		column.add_child(_label(text, HudTheme.font("body"), 15, colors.ink))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	var links: Dictionary = {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PATH))
	if parsed is Dictionary:
		links = parsed.get("links", {})
	for entry in [["LinkedIn ↗", "linkedin"], ["GitHub ↗", "github"]]:
		if links.has(entry[1]):
			var url: String = links[entry[1]]
			var link := Button.new()
			link.text = entry[0]
			link.pressed.connect(func(): _open(url))
			row.add_child(link)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var close := Button.new()
	close.text = close_text
	close.pressed.connect(close_card)
	row.add_child(close)
	visible = true
	if world and world.ship:
		world.ship.set("enabled", false)

func close_card() -> void:
	visible = false
	if world and world.ship:
		world.ship.set("enabled", true)
	if on_close.is_valid():
		on_close.call()

func _label(text: String, font: Font, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _open(url: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.open(%s, '_blank', 'noopener')" % JSON.stringify(url), true)
	else:
		OS.shell_open(url)

## Formatos da viagem para os cartões.
static func format_duration(seconds: float) -> String:
	var total := int(seconds)
	if total < 60:
		return "%d s" % total
	if total < 3600:
		return "%d min %02d s" % [total / 60, total % 60]
	return "%d h %02d min" % [total / 3600, (total % 3600) / 60]

static func format_distance(meters: float) -> String:
	return ("%.1f km" % (meters / 1000.0)) if meters >= 1000.0 else ("%d m" % int(meters))
