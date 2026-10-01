extends CanvasLayer

## Controles de toque para a versão mobile (web). Aparecem só em telas de toque
## (ou com force_visible). Um dedo fora dos controles mexe na água (mouse emulado);
## dois dedos giram a câmera.

const STICK_RADIUS := 70.0
const KNOB_RADIUS := 30.0

@export var force_visible := false
var ship: Node
var naval: Node
var camera: Node
var drive := Vector2.ZERO
var aim := Vector2.ZERO
var boost := false
var touches := {}
var drive_pad: Control
var aim_pad: Control

func _ready() -> void:
	layer = 5
	visible = false
	set_process(false)
	if force_visible or DisplayServer.is_touchscreen_available():
		enable()

## Monta os controles (chamado sozinho em telas de toque; os testes podem forçar).
func enable() -> void:
	if visible:
		return
	visible = true
	set_process(true)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	drive_pad = _make_pad(root, Control.PRESET_BOTTOM_LEFT, Vector2(36, -36), "drive")
	aim_pad = _make_pad(root, Control.PRESET_BOTTOM_RIGHT, Vector2(-36, -36), "aim")
	_make_button(root, "FOGO", true, func(): if naval: naval.call("fire"))
	var boost_button := _make_button(root, "IMPULSO", false, Callable())
	boost_button.button_down.connect(func(): boost = true)
	boost_button.button_up.connect(func(): boost = false)

func _make_pad(parent: Control, preset: int, margin: Vector2, kind: String) -> Control:
	var pad := Control.new()
	pad.custom_minimum_size = Vector2.ONE * STICK_RADIUS * 2.0
	pad.size = pad.custom_minimum_size
	var right := preset == Control.PRESET_BOTTOM_RIGHT
	pad.position = Vector2(
		(get_viewport().get_visible_rect().size.x - pad.size.x + margin.x) if right else margin.x,
		get_viewport().get_visible_rect().size.y - pad.size.y + margin.y)
	pad.set_meta("kind", kind)
	pad.set_meta("knob", Vector2.ZERO)
	pad.mouse_filter = Control.MOUSE_FILTER_STOP
	pad.draw.connect(_draw_pad.bind(pad))
	pad.gui_input.connect(_pad_input.bind(pad))
	parent.add_child(pad)
	get_viewport().size_changed.connect(func():
		var screen := get_viewport().get_visible_rect().size
		pad.position = Vector2((screen.x - pad.size.x + margin.x) if right else margin.x, screen.y - pad.size.y + margin.y))
	return pad

## Botão logo acima do joystick do mesmo lado.
func _make_button(parent: Control, text: String, right_side: bool, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(110, 64)
	button.add_theme_font_size_override("font_size", 20)
	var place := func():
		var screen := get_viewport().get_visible_rect().size
		var pad_center_x := (screen.x - 36.0 - STICK_RADIUS) if right_side else 36.0 + STICK_RADIUS
		button.position = Vector2(pad_center_x - button.size.x * 0.5, screen.y - 36.0 - STICK_RADIUS * 2.0 - 16.0 - button.size.y)
	parent.add_child(button)
	place.call()
	get_viewport().size_changed.connect(place)
	if action.is_valid():
		button.pressed.connect(action)
	return button

func _draw_pad(pad: Control) -> void:
	var center := pad.size * 0.5
	pad.draw_circle(center, STICK_RADIUS, Color(0.02, 0.1, 0.18, 0.35))
	pad.draw_arc(center, STICK_RADIUS, 0.0, TAU, 48, Color(0.9, 0.97, 1.0, 0.6), 2.0, true)
	pad.draw_circle(center + pad.get_meta("knob") * (STICK_RADIUS - KNOB_RADIUS), KNOB_RADIUS, Color(0.95, 0.85, 0.55, 0.8))

func _pad_input(event: InputEvent, pad: Control) -> void:
	var position := Vector2.INF
	var released := false
	if event is InputEventScreenTouch:
		position = event.position
		released = not event.pressed
	elif event is InputEventScreenDrag:
		position = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		position = event.position
		released = not event.pressed
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		position = event.position
	if position == Vector2.INF:
		return
	pad.accept_event()
	var value := Vector2.ZERO
	if not released:
		value = ((position - pad.size * 0.5) / (STICK_RADIUS - KNOB_RADIUS)).limit_length(1.0)
	pad.set_meta("knob", value)
	if pad.get_meta("kind") == "drive":
		drive = value
	else:
		aim = value
	pad.queue_redraw()

func _input(event: InputEvent) -> void:
	# Dois dedos fora dos controles: girar a câmera.
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
		else:
			touches.erase(event.index)
	elif event is InputEventScreenDrag and touches.size() >= 2 and camera:
		touches[event.index] = event.position
		camera.call("drag_orbit", event.relative / float(touches.size()))
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if ship:
		ship.set("virtual_throttle", -drive.y if absf(drive.y) > 0.15 else 0.0)
		ship.set("virtual_steering", drive.x if absf(drive.x) > 0.15 else 0.0)
		ship.set("virtual_boost", boost or drive.length() > 0.92)
	if naval:
		naval.set("virtual_aim", Vector2(aim.x if absf(aim.x) > 0.15 else 0.0, -aim.y if absf(aim.y) > 0.15 else 0.0))
