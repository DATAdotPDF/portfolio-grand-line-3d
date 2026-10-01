extends RefCounted

## Paleta e tipografia do HUD: "papel" de carta náutica com tom pirata.
## Dia = pergaminho com tinta sépia e acento carmim; noite = carta azul-marinho
## com tinta creme e acento dourado. Tudo interpola pelo daylight do jogo.

const DAY := {
	"paper": Color("efe4cc"), "paper_edge": Color("d9c9a6"), "ink": Color("2b2118"),
	"muted": Color("7a6a55"), "line": Color(0.17, 0.13, 0.09, 0.28), "accent": Color("9e1b2b"),
	"gold": Color("b8893b"), "shadow": Color(0.12, 0.08, 0.03, 0.22),
}
const NIGHT := {
	"paper": Color("1d2537"), "paper_edge": Color("2c3752"), "ink": Color("efe4cc"),
	"muted": Color("a9b3c7"), "line": Color(0.94, 0.89, 0.8, 0.26), "accent": Color("e7a44a"),
	"gold": Color("e7c27a"), "shadow": Color(0.0, 0.0, 0.0, 0.35),
}

static var _fonts := {}

static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var result: Font
	match kind:
		"display":
			result = load("res://Assets/Fonts/IMFellEnglish-Regular.ttf")
		"display_italic":
			result = load("res://Assets/Fonts/IMFellEnglish-Italic.ttf")
		"mono":
			var mono := FontVariation.new()
			mono.base_font = load("res://Assets/Fonts/JetBrainsMono-Variable.ttf")
			mono.variation_opentype = {"wght": 500}
			result = mono
		"label":
			var label := FontVariation.new()
			label.base_font = load("res://Assets/Fonts/Inter-Variable.ttf")
			label.variation_opentype = {"wght": 600}
			label.spacing_glyph = 2
			result = label
		_:
			var body := FontVariation.new()
			body.base_font = load("res://Assets/Fonts/Inter-Variable.ttf")
			body.variation_opentype = {"wght": 420}
			result = body
	_fonts[kind] = result
	return result

static func palette(daylight: float) -> Dictionary:
	# Troca curta entre dia e noite: o meio-termo creme/azul fica "lamacento" e ilegível.
	var t := smoothstep(0.38, 0.62, clampf(daylight, 0.0, 1.0))
	var out := {}
	for key in DAY.keys():
		out[key] = (NIGHT[key] as Color).lerp(DAY[key], t)
	return out

## StyleBox de "folha de papel": borda fina, cantos quase retos, sombra curta.
static func paper_box(colors: Dictionary, alpha := 0.94) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(colors.paper, alpha)
	box.border_color = colors.line
	box.set_border_width_all(1)
	box.set_corner_radius_all(2)
	box.shadow_color = colors.shadow
	box.shadow_size = 6
	box.shadow_offset = Vector2(0, 3)
	box.set_content_margin_all(14)
	return box

static func button_box(colors: Dictionary, state: String) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(colors.paper, 0.78 if state == "normal" else 0.95)
	if state == "pressed":
		box.bg_color = Color(colors.ink, 0.12)
	box.border_color = colors.accent if state == "hover" else Color(colors.ink, 0.42)
	box.set_border_width_all(1)
	box.set_corner_radius_all(1)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	return box

static func build_theme(colors: Dictionary) -> Theme:
	var theme := Theme.new()
	theme.default_font = font("body")
	theme.default_font_size = 15
	theme.set_color("font_color", "Label", colors.ink)
	for state in ["normal", "hover", "pressed", "focus"]:
		theme.set_stylebox(state, "Button", button_box(colors, "hover" if state == "focus" else state))
	theme.set_stylebox("hover_pressed", "Button", button_box(colors, "pressed"))
	theme.set_color("font_color", "Button", colors.ink)
	theme.set_color("font_hover_color", "Button", colors.accent)
	theme.set_color("font_pressed_color", "Button", colors.accent)
	theme.set_color("font_hover_pressed_color", "Button", colors.accent)
	theme.set_font("font", "Button", font("label"))
	theme.set_font_size("font_size", "Button", 13)
	theme.set_stylebox("panel", "PanelContainer", paper_box(colors))
	theme.set_color("default_color", "RichTextLabel", colors.ink)
	theme.set_font("normal_font", "RichTextLabel", font("body"))
	theme.set_font("italics_font", "RichTextLabel", font("display_italic"))
	theme.set_font("bold_font", "RichTextLabel", font("label"))
	theme.set_font("mono_font", "RichTextLabel", font("mono"))
	theme.set_font_size("normal_font_size", "RichTextLabel", 15)
	theme.set_font_size("mono_font_size", "RichTextLabel", 13)
	theme.set_font_size("bold_font_size", "RichTextLabel", 12)
	theme.set_font_size("italics_font_size", "RichTextLabel", 20)
	theme.set_stylebox("panel", "TooltipPanel", paper_box(colors))
	theme.set_color("font_color", "TooltipLabel", colors.ink)
	return theme
