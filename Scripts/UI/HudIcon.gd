extends Control

## Ícones vetoriais da HUD desenhados em código (sem texturas e sem depender de
## glifos da fonte — glifos ausentes viravam "quadradinhos" na web).

@export var kind := "compass":
	set(value):
		kind = value
		queue_redraw()
@export var color := Color("e8c172"):
	set(value):
		color = value
		queue_redraw()
@export var line := 1.6

func _init(icon_kind := "compass", icon_size := 18.0, icon_color := Color("e8c172")) -> void:
	kind = icon_kind
	color = icon_color
	custom_minimum_size = Vector2.ONE * icon_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var r := s * 0.5
	match kind:
		"compass":
			var pts := PackedVector2Array()
			for i in range(8):
				var a := TAU * float(i) / 8.0 - PI * 0.5
				var rr := r if i % 2 == 0 else r * 0.32
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			draw_colored_polygon(pts, color)
			draw_circle(c, r * 0.14, Color(0.03, 0.06, 0.12))
		"boat":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.05, -r * 0.9), c + Vector2(-r * 0.05, r * 0.35), c + Vector2(-r * 0.75, r * 0.35)]), color)
			draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.08, -r * 0.6), c + Vector2(r * 0.08, r * 0.35), c + Vector2(r * 0.6, r * 0.35)]), color)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.95, r * 0.5), c + Vector2(r * 0.95, r * 0.5), c + Vector2(r * 0.6, r * 0.85), c + Vector2(-r * 0.6, r * 0.85)]), color)
		"pin":
			draw_circle(c + Vector2(0, -r * 0.25), r * 0.5, color)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.42, -r * 0.05), c + Vector2(r * 0.42, -r * 0.05), c + Vector2(0, r * 0.95)]), color)
			draw_circle(c + Vector2(0, -r * 0.25), r * 0.2, Color(0.03, 0.06, 0.12))
		"cannon":
			draw_line(c + Vector2(-r * 0.8, r * 0.2), c + Vector2(r * 0.85, -r * 0.45), color, r * 0.45, true)
			draw_circle(c + Vector2(-r * 0.35, r * 0.45), r * 0.38, color)
		"play":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.5, -r * 0.7), c + Vector2(r * 0.75, 0), c + Vector2(-r * 0.5, r * 0.7)]), color)
		"pause":
			draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.7), Vector2(r * 0.42, r * 1.4)), color)
			draw_rect(Rect2(c + Vector2(r * 0.18, -r * 0.7), Vector2(r * 0.42, r * 1.4)), color)
		"prev", "next":
			# Triângulo apontando para o lado + barra na ponta (⏮ / ⏭).
			var d := -1.0 if kind == "prev" else 1.0
			draw_colored_polygon(PackedVector2Array([c + Vector2(d * r * 0.4, 0), c + Vector2(-d * r * 0.55, -r * 0.65), c + Vector2(-d * r * 0.55, r * 0.65)]), color)
			draw_line(c + Vector2(d * r * 0.62, -r * 0.65), c + Vector2(d * r * 0.62, r * 0.65), color, r * 0.22, true)
		"sun":
			draw_circle(c, r * 0.38, color)
			for i in range(8):
				var a := TAU * float(i) / 8.0
				draw_line(c + Vector2(cos(a), sin(a)) * r * 0.58, c + Vector2(cos(a), sin(a)) * r * 0.92, color, line, true)
		"moon":
			draw_circle(c, r * 0.72, color)
			draw_circle(c + Vector2(r * 0.34, -r * 0.24), r * 0.62, Color(0.03, 0.06, 0.12))
		"cycle":
			draw_arc(c, r * 0.7, -PI * 0.2, PI * 1.45, 24, color, line, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.6, -r * 0.65), c + Vector2(r * 0.95, -r * 0.2), c + Vector2(r * 0.3, -r * 0.15)]), color)
		"flag":
			draw_line(c + Vector2(-r * 0.6, -r * 0.9), c + Vector2(-r * 0.6, r * 0.9), color, line, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.6, -r * 0.85), c + Vector2(r * 0.8, -r * 0.5), c + Vector2(-r * 0.6, -r * 0.1)]), color)
		"wind":
			for i in range(3):
				var y := -r * 0.45 + float(i) * r * 0.45
				draw_line(c + Vector2(-r * 0.9, y), c + Vector2(r * (0.6 - 0.25 * float(i)), y), color, line, true)
		"menu":
			for i in range(3):
				draw_line(c + Vector2(-r * 0.7, -r * 0.5 + float(i) * r * 0.5), c + Vector2(r * 0.7, -r * 0.5 + float(i) * r * 0.5), color, line + 0.6, true)
		"close":
			draw_line(c + Vector2(-r * 0.55, -r * 0.55), c + Vector2(r * 0.55, r * 0.55), color, line + 0.4, true)
			draw_line(c + Vector2(r * 0.55, -r * 0.55), c + Vector2(-r * 0.55, r * 0.55), color, line + 0.4, true)
		"check":
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.6, 0), c + Vector2(-r * 0.15, r * 0.45), c + Vector2(r * 0.65, -r * 0.5)]), color, line + 0.4, true)
		"dot":
			draw_circle(c, r * 0.3, color)
