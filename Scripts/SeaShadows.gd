extends Node3D

## Encontros com animais embaixo d'água (silhuetas do atlas, shader sea_shadow).
## Como os golfinhos (e como na natureza: lá do fundo eles só veem o casco e vêm conferir,
## às vezes confundindo o barco com outro bicho): o grupo sobe do fundo ATRÁS do barco, de um
## lado, com rumo fixo (o do barco na hora), um pouco mais rápido que ele; passa ao lado do casco,
## segue à frente e mergulha. Nunca nasce em cima do barco, nunca perto dos ciclones.
## - Grupos: foca em bando de 3–4 (rápidas, em zigue-zague), arraia em bando de 5–8 (às vezes
##   gigantes; "voam" batendo as asas e brilham à noite), jubarte mãe + filhote, tubarão-baleia,
##   tubarão e kraken sozinhos.
## - Tubarão: a barbatana dorsal corta a água (marolas e espuma atrás).
## - Jubarte: borrifa água de vez em quando.
## - Passar por cima assusta: espalham e afundam um pouco (as arraias principalmente).
## - Biomas: cada setor do planeta (ilha mais próxima) tem sua mistura; kraken, tubarão-baleia
##   e jubarte têm a mesma chance em todo lugar.
## - Kraken: não é só silhueta, dispara o evento (KrakenEvent.gd) quando dá para começar.

const SHADOW := preload("res://Shaders/sea_shadow.gdshader")
const ATLAS := preload("res://Assets/SeaLife/sea_shadows_atlas.png")
const BLOW := preload("res://Assets/Sound/SFX/Generated/whale_blow.wav")
const Shore = preload("res://Scripts/Shoreline.gd")

## kind = célula do atlas; ratio = largura/comprimento da silhueta; fade = segundos subindo do fundo.
const SPECIES := {
	"tubarao": {"kind": 0, "length": 6.0, "ratio": 0.522, "speed": 3.4, "group": [1, 1], "fade": 2.0, "wiggle": 1.0},
	"arraia": {"kind": 1, "length": 4.5, "ratio": 0.997, "speed": 1.9, "group": [5, 8], "fade": 3.0, "wiggle": 0.3},
	"jubarte": {"kind": 2, "length": 38.0, "ratio": 0.693, "speed": 2.2, "group": [2, 2], "fade": 6.0, "wiggle": 0.5},
	"tubarao_baleia": {"kind": 3, "length": 48.0, "ratio": 0.475, "speed": 1.5, "group": [1, 1], "fade": 9.0, "wiggle": 0.6},
	"foca": {"kind": 5, "length": 3.0, "ratio": 0.464, "speed": 6.5, "group": [3, 4], "fade": 1.0, "wiggle": 2.4},
}
## Chances iguais no planeta todo (%).
const FIXED_WEIGHTS := {"kraken": 2.0, "tubarao_baleia": 6.0, "jubarte": 12.0}
## Os outros 80% por setor (ilha mais próxima: 0 Sobre, 1 Experiência, 2 Formação, 3 Projetos, 4 Contato).
const BIOMES := [
	{"name": "mar frio do norte", "foca": 32.0, "arraia": 20.0, "tubarao": 28.0},
	{"name": "corrente quente", "foca": 15.0, "arraia": 30.0, "tubarao": 35.0},
	{"name": "recifes rasos", "foca": 15.0, "arraia": 45.0, "tubarao": 20.0},
	{"name": "mar aberto", "foca": 15.0, "arraia": 25.0, "tubarao": 40.0},
	{"name": "mar frio do sul", "foca": 30.0, "arraia": 20.0, "tubarao": 30.0},
]

## Intervalo entre encontros (s): espaçados, para cada um ser uma surpresa.
@export var interval := Vector2(70.0, 140.0)
## Nenhum bicho a menos disso de um ciclone (só o kraken).
const CYCLONE_CLEARANCE := 180.0

var world: Node3D
var ship: Node3D
var ocean: Node
var planet_radius := 800.0
var rng := RandomNumberGenerator.new()
var groups: Array[Dictionary] = []
var timer := 45.0
var last_species := ""
## Barbatana do tubarão: modelo do Meshy (Tools/rig_creatures_blender.py), base no chão (y 0),
## 1 m de altura, frente = -Z, materiais originais.
const FIN_SCENE := preload("res://Assets/Optimized/Creatures/fin.glb")

func _ready() -> void:
	rng.randomize()

## Placa de silhueta para a célula pedida: [nó, material]. Usada também pelos golfinhos.
func make_plate(kind: int, length: float, width: float) -> Array:
	var plane := PlaneMesh.new()
	plane.size = Vector2(width, length)
	# Mais divisões nos gigantes para a placa seguir as ondas.
	plane.subdivide_width = clampi(int(width / 1.5), 8, 24)
	plane.subdivide_depth = clampi(int(length / 1.5), 16, 48)
	var material := ShaderMaterial.new()
	material.shader = SHADOW
	material.render_priority = 1
	material.set_shader_parameter("kind", kind)
	material.set_shader_parameter("shadow_atlas", ATLAS)
	material.set_shader_parameter("opacity", 0.0)
	ocean.register_material(material)
	var node := MeshInstance3D.new()
	node.mesh = plane
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.top_level = true
	add_child(node)
	return [node, material]

func free_plate(entry: Array) -> void:
	if entry.is_empty():
		return
	ocean.materials.erase(entry[1])
	(entry[0] as Node).queue_free()

func push_patch(material: ShaderMaterial) -> void:
	var patch: Node3D = world.get("ocean_patch")
	if is_instance_valid(patch):
		material.set_shader_parameter("patch_center", patch.global_position)
		material.set_shader_parameter("patch_radius", patch.patch_radius if patch.visible else 0.0)

func biome_at(point: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in world.islands.size():
		var d: float = point.normalized().angle_to(world.islands[i].global_position.normalized())
		if d < best_d:
			best_d = d
			best = i
	return clampi(best, 0, BIOMES.size() - 1)

func _coast_distance(point: Vector3) -> float:
	var best := INF
	for island in world.islands:
		if point.distance_to(island.global_position) < 400.0:
			best = minf(best, Shore.distance_to_coast(island, point))
	return best

## Perto de um ciclone (ou dentro de tempestade forte) não tem bicho.
func near_cyclone(point: Vector3) -> bool:
	var weather: Node = world.get("weather")
	if weather == null:
		return false
	for cyclone in weather.cyclones:
		if point.distance_to((cyclone.center as Vector3) * planet_radius) < CYCLONE_CLEARANCE:
			return true
	return false

func _roll(point: Vector3) -> String:
	var table := FIXED_WEIGHTS.duplicate()
	var biome: Dictionary = BIOMES[biome_at(point)]
	for key in ["foca", "arraia", "tubarao"]:
		table[key] = biome[key]
	# Variedade: a mesma espécie duas vezes seguidas fica 4× menos provável.
	if table.has(last_species) and last_species != "kraken":
		table[last_species] = float(table[last_species]) * 0.25
	var total := 0.0
	for key in table:
		total += float(table[key])
	var roll := rng.randf() * total
	for key in table:
		roll -= float(table[key])
		if roll <= 0.0:
			return key
	return "tubarao"

func _process(delta: float) -> void:
	if world == null or not is_instance_valid(ship) or ocean == null:
		return
	if "enabled" in ship and not ship.enabled:
		return
	timer -= delta
	if timer <= 0.0:
		timer = 8.0
		var here: Vector3 = ship.global_position
		var calm: bool = ocean.badness_at(here) < 1.0
		var kraken_busy: bool = world.get("kraken_event") != null and int(world.kraken_event.get("phase")) != 0
		# Longe da praia (40 m da costa: ali é o cardume de peixes) e longe de ciclones.
		if groups.is_empty() and (world.sea_life.dolphins as Array).is_empty() and calm and not kraken_busy and not near_cyclone(here) and _coast_distance(here) > 40.0:
			var species := _roll(here)
			if species == "kraken":
				var kraken: Node = world.get("kraken_event")
				if kraken and kraken.call("can_start"):
					kraken.call("start")
					timer = rng.randf_range(interval.x, interval.y) * 2.0
					return
				species = "tubarao_baleia"
			spawn(species)
			last_species = species
			timer = rng.randf_range(interval.x, interval.y)
	var night: float = world.clock.night_at(ship.global_position) if world.get("clock") else 0.0
	for i in range(groups.size() - 1, -1, -1):
		if not _update_group(groups[i], delta, night):
			_free_group(groups[i])
			groups.remove_at(i)

func _frame_at(point: Vector3, forward: Vector3) -> Array:
	var up := point.normalized()
	var f := forward.slide(up).normalized()
	return [f, up, f.cross(up).normalized()]

## Grupo novo: sobe ATRÁS do barco, de um lado, com o rumo do barco e um pouco mais rápido,
## para passar ao lado do casco (como os golfinhos). at/heading opcionais (testes).
func spawn(species: String, at := Vector3.INF, heading := Vector3.ZERO) -> Dictionary:
	var info: Dictionary = SPECIES[species]
	var frame := _frame_at(ship.global_position, ship.heading)
	var forward: Vector3 = frame[0]
	var right: Vector3 = frame[2]
	var up: Vector3 = frame[1]
	var big := species in ["jubarte", "tubarao_baleia"]
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	# Distância lateral: os grandes (jubarte, tubarão-baleia) passam por baixo do barco.
	# Tubarão-baleia passa sempre por baixo do barco; a jubarte às vezes por baixo, às vezes rente
	# ao costado; os pequenos ao lado.
	var lateral := rng.randf_range(4.5, 8.0)
	if species == "tubarao_baleia":
		lateral = rng.randf_range(0.0, 1.5)
	elif species == "jubarte":
		lateral = rng.randf_range(0.0, 2.0) if rng.randf() < 0.45 else rng.randf_range(8.0, 14.0)
	var center := at
	if center == Vector3.INF:
		# Começa logo atrás (4–12 m), já entrando no campo da câmera, e ultrapassa o barco. Os
		# gigantes começam com a cabeça uns 20 m atrás da popa e atravessam o barco inteiro.
		var behind := float(info.length) * 0.5 + rng.randf_range(15.0, 25.0) if big else rng.randf_range(4.0, 12.0)
		center = ship.global_position - forward * behind + right * side * lateral
	var dir := heading if heading != Vector3.ZERO else forward
	# Ultrapassa o barco: velocidade do barco + folga (mín. a do bicho).
	var overtake := rng.randf_range(4.0, 5.0) if big else rng.randf_range(2.5, 3.5)
	var speed := maxf(float(info.speed), absf(float(ship.drive_speed)) + overtake)
	var group := {
		"species": species, "center": center.normalized() * planet_radius, "dir": dir.slide(center.normalized()).normalized(),
		"speed": speed, "age": 0.0, "life": 60.0, "fade": float(info.fade), "members": [], "side": side,
		"blow": rng.randf_range(4.0, 8.0), "ripple": 0.0, "leaving": -1.0,
	}
	var count := rng.randi_range(int(info.group[0]), int(info.group[1]))
	var giant := species == "arraia" and rng.randf() < 0.25
	for m in count:
		var scale := 1.0
		var offset := Vector2.ZERO
		match species:
			"arraia":
				scale = (rng.randf_range(1.8, 2.4) if giant else rng.randf_range(0.8, 1.2))
				# Bando espalhado para fora (lado oposto ao barco) e ao longo do rumo.
				# Bando espalhado para fora (lado oposto ao barco) e ao longo do rumo, cada arraia no
				# seu espaço: sorteia de novo se cair em cima de outra.
				var spread := 1.6 if giant else 1.0
				var spacing := 4.5 * scale
				for attempt in 12:
					offset = Vector2(side * rng.randf_range(0.0, 11.0), rng.randf_range(-10.0, 10.0)) * spread
					var free := true
					for other in group.members:
						if (other.offset as Vector2).distance_to(offset) < spacing:
							free = false
							break
					if free:
						break
			"foca":
				# Fila solta: uma atrás da outra, levemente escalonadas para fora.
				offset = Vector2(side * rng.randf_range(0.0, 2.5), -float(m) * rng.randf_range(2.5, 3.5))
			"jubarte":
				# Mãe e filhote: o filhote nada colado, do lado de fora e um pouco atrás.
				if m == 1:
					scale = 0.45
					offset = Vector2(side * 19.0, -6.0)
		var length := float(info.length) * scale
		var plate := make_plate(int(info.kind), length, length * float(info.ratio))
		var member := {"plate": plate, "offset": offset, "scale": scale, "length": length, "phase": rng.randf_range(0.0, TAU),
			"swim": rng.randf_range(0.0, TAU), "flee": 0.0, "push": Vector3.ZERO, "pos": center, "heading": group.dir}
		if species == "tubarao":
			var fin := FIN_SCENE.instantiate() as Node3D
			fin.top_level = true
			for mesh in fin.find_children("*", "MeshInstance3D", true, false):
				(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(fin)
			member["fin"] = fin
		group.members.append(member)
	groups.append(group)
	print("SEALIFE encontro=%s x%d bioma=%s%s" % [species, count, BIOMES[biome_at(center)].name, " (gigantes)" if giant else ""])
	return group

## Mantém o bicho fora do casco: elipse em volta do barco, empurra para o lado mais perto.
func _keep_off_hull(pos: Vector3, body_width: float) -> Vector3:
	var frame := _frame_at(ship.global_position, ship.heading)
	var rel: Vector3 = pos - ship.global_position
	var along: float = rel.dot(frame[0])
	var side: float = rel.dot(frame[2])
	var half_length := 4.2 + body_width * 0.3
	var half_width := 2.6 + body_width * 0.5
	if (along / half_length) * (along / half_length) + (side / half_width) * (side / half_width) >= 1.0:
		return pos
	var wanted := half_width * sqrt(maxf(0.0, 1.0 - (along / half_length) * (along / half_length)))
	var sign_side := 1.0 if side >= 0.0 else -1.0
	return pos + (frame[2] as Vector3) * sign_side * (wanted - absf(side))

func _update_group(g: Dictionary, delta: float, night: float) -> bool:
	g.age += delta
	var center: Vector3 = g.center
	var up := center.normalized()
	var dir: Vector3 = (g.dir as Vector3).slide(up).normalized()
	g.dir = dir
	# Mergulha (fade out de 4 s) quando já passou bem à frente do barco, ou chegou perto de um
	# ciclone, ou ficou tempo demais.
	var ahead_of_ship := (center - ship.global_position).dot(ship.heading.slide(up).normalized())
	if float(g.leaving) < 0.0 and (ahead_of_ship > 18.0 + float(SPECIES[g.species].length) * 0.5 or near_cyclone(center) or g.age > 45.0):
		g.leaving = g.age
	if float(g.leaving) >= 0.0 and g.age > float(g.leaving) + 4.0:
		return false
	if center.distance_to(ship.global_position) > 160.0:
		return false
	center = (center + dir * float(g.speed) * delta).normalized() * planet_radius
	g.center = center
	var right := dir.cross(up).normalized()
	var info: Dictionary = SPECIES[g.species]
	var out_fade := 1.0 - smoothstep(float(g.leaving), float(g.leaving) + 4.0, float(g.age)) if float(g.leaving) >= 0.0 else 1.0
	var base_opacity: float = smoothstep(0.0, float(g.fade), float(g.age)) * out_fade
	var ship_pos: Vector3 = ship.global_position
	for member in g.members:
		var t: float = g.age + float(member.phase)
		var offset: Vector2 = member.offset
		var local := right * offset.x + dir * offset.y
		var heading := dir
		match g.species:
			"foca":
				# Brincalhonas: cada uma dá voltas em volta do seu lugar no bando (laços), com
				# arrancadas e mudança de sentido; de vez em quando rola de lado.
				var spin := 1.0 if int(float(member.phase) * 10.0) % 2 == 0 else -1.0
				var loop_t := t * (1.6 + 0.6 * sin(t * 0.37 + float(member.phase))) * spin
				var loop_r := 1.6 + 1.0 * sin(t * 0.5 + float(member.phase) * 2.0)
				local += (right * cos(loop_t) + dir * sin(loop_t)) * loop_r
				local += dir * maxf(0.0, sin(t * 0.8 + float(member.phase))) * 2.5
			"arraia":
				local += right * sin(t * 0.4) * 1.2 + dir * sin(t * 0.3) * 0.8
			"tubarao":
				local += right * sin(t * 0.5) * 1.5
				heading = (dir * float(g.speed) + right * cos(t * 0.5) * 0.75).normalized()
		var pos: Vector3 = center + local + (member.push as Vector3)
		# Cada bicho é um indivíduo: afasta-se dos outros do grupo (distância mínima pelo tamanho),
		# empurrando aos poucos para não dar tranco.
		var my_radius := float(member.length) * float(info.ratio) * 0.5
		for other in g.members:
			if other == member:
				continue
			var away: Vector3 = (pos - (other.pos as Vector3)).slide(up)
			var min_gap := my_radius + float(other.length) * float(info.ratio) * 0.5 + 0.6
			var gap := away.length()
			if gap < min_gap:
				var push_dir: Vector3 = away / gap if gap > 0.05 else right * (1.0 if float(member.phase) > PI else -1.0)
				member.push = (member.push as Vector3) + push_dir * (min_gap - gap) * minf(1.0, 3.0 * delta)
		pos = center + local + (member.push as Vector3)
		# Reação: passar por cima espanta (espalha e afunda um pouco).
		var flat_d := (pos - ship_pos).slide(up).length()
		var scare_radius := 4.0 + float(member.length) * 0.35
		# Os gigantes não se assustam com o barco (passam por baixo dele).
		if flat_d < scare_radius and base_opacity > 0.4 and not g.species in ["jubarte", "tubarao_baleia"]:
			member.flee = 1.0
		member.flee = maxf(0.0, float(member.flee) - delta * 0.35)
		if float(member.flee) > 0.0:
			# Foge para o lado (nunca para trás: senão fica preso atrás do barco e não passa).
			var away := (pos - ship_pos).slide(up).slide(ship.heading.slide(up).normalized())
			away = away.normalized() if away.length() > 0.1 else right
			var flee_speed := 5.0 if g.species in ["arraia", "foca"] else 2.0
			member.push = (member.push as Vector3) + away * flee_speed * float(member.flee) * delta
			heading = heading.slerp(away, float(member.flee) * 0.6).normalized()
		# Os gigantes podem passar por baixo do casco; os pequenos contornam.
		if not g.species in ["jubarte", "tubarao_baleia"]:
			pos = _keep_off_hull(pos, float(member.length) * float(info.ratio))
		pos = pos.normalized() * planet_radius
		# O corpo aponta para onde ele realmente está indo (inclui laços, desvios e fuga).
		var moved: Vector3 = (pos - (member.pos as Vector3)).slide(pos.normalized())
		if moved.length() > 0.02 * delta * 30.0:
			heading = moved.normalized()
		var old_heading: Vector3 = (member.heading as Vector3).slide(pos.normalized()).normalized()
		heading = old_heading.slerp(heading, 1.0 - exp(-6.0 * delta)).normalized()
		var turn := old_heading.signed_angle_to(heading, pos.normalized()) / maxf(delta, 0.001)
		member.curve = lerpf(float(member.get("curve", 0.0)), clampf(-turn * 0.45, -1.0, 1.0), 1.0 - exp(-5.0 * delta))
		member.pos = pos
		member.heading = heading
		var plate: Array = member.plate
		var node: MeshInstance3D = plate[0]
		var material: ShaderMaterial = plate[1]
		node.global_transform = Transform3D(Basis.looking_at(heading.slide(pos.normalized()).normalized(), pos.normalized()), pos)
		var swim_rate := 2.0 + float(g.speed) * (2.5 if g.species == "foca" else 1.0) + float(member.flee) * 4.0
		member.swim = float(member.swim) + delta * swim_rate
		var opacity := base_opacity * (1.0 - 0.55 * float(member.flee))
		material.set_shader_parameter("swim", member.swim)
		material.set_shader_parameter("opacity", opacity)
		material.set_shader_parameter("wiggle", info.wiggle)
		material.set_shader_parameter("curve", member.get("curve", 0.0))
		# Foca rolando de lado de vez em quando (~1 s a cada ~6 s).
		var roll := 0.0
		if g.species == "foca":
			roll = smoothstep(0.75, 1.0, sin(t * 1.05 + float(member.phase) * 3.0)) * absf(sin(t * 6.0))
		material.set_shader_parameter("roll", roll)
		if g.species == "arraia":
			material.set_shader_parameter("flap", 0.8 + float(member.flee) * 0.6)
			material.set_shader_parameter("glow", night)
		push_patch(material)
		if member.has("fin"):
			_update_fin(g, member, pos, heading, opacity, delta)
	if g.species == "jubarte":
		_whale_blow(g, delta, base_opacity)
	return true

## Barbatana dorsal fora d'água: sobe com a silhueta, corta a água deixando marolas e espuma.
func _update_fin(g: Dictionary, member: Dictionary, pos: Vector3, heading: Vector3, opacity: float, delta: float) -> void:
	var fin: Node3D = member.fin
	# Dorsal a ~35% do comprimento a partir do focinho (0,15 × comprimento à frente do centro).
	var rest: Vector3 = (pos + heading * float(member.length) * 0.15).normalized() * planet_radius
	# Mesmo ponto que a placa da silhueta desenha: deslocamento das ondas (Gerstner) + altura.
	var field: Vector4 = ocean.field_at(rest)
	var surface: Vector3 = (rest + Vector3(field.x, field.y, field.z)).normalized() * (planet_radius + field.w)
	var up := surface.normalized()
	var rise := smoothstep(0.35, 0.8, opacity)
	fin.visible = rise > 0.02
	var forward := heading.slide(up).normalized()
	var wobble := sin(float(member.swim) * 1.3) * 0.1
	fin.global_transform = Transform3D(Basis.looking_at(forward, up).rotated(up, wobble).scaled(Vector3(1.4, 1.4 * rise, 1.4)), surface - up * 0.05)
	g.ripple = float(g.ripple) - delta
	if rise > 0.5 and float(g.ripple) <= 0.0:
		g.ripple = 0.35
		ocean.touch(surface, 0.22, 2.4)
		var weather: Node = world.get("weather")
		if weather and weather.get("spray"):
			weather.spray.burst(surface + forward * 0.35, 2, 0.35)

## Borrifo da jubarte (mãe): coluna de água na cabeça, como o respingo do casco, para cima.
func _whale_blow(g: Dictionary, delta: float, opacity: float) -> void:
	g.blow = float(g.blow) - delta
	if float(g.blow) > 0.0 or opacity < 0.8:
		return
	g.blow = rng.randf_range(7.0, 12.0)
	var mother: Dictionary = g.members[0]
	var head: Vector3 = ocean.surface_at((mother.pos as Vector3) + (mother.heading as Vector3) * float(mother.length) * 0.3)
	var weather: Node = world.get("weather")
	if weather and weather.get("spray"):
		for i in 4:
			weather.spray.burst(head + head.normalized() * (0.3 + i * 1.2), 14, 3.4 + i * 0.6, 2.2)
	_spout_jet(head)
	var sound := AudioStreamPlayer3D.new()
	sound.stream = BLOW
	sound.unit_size = 20.0
	sound.max_distance = 140.0
	sound.pitch_scale = rng.randf_range(0.85, 1.0)
	add_child(sound)
	sound.global_position = head
	sound.play()
	sound.finished.connect(sound.queue_free)

## Jato da jubarte: as mesmas gotinhas do respingo do casco (shader water_drop), maiores e
## muitas, subindo como uma coluna de ~8–10 m e caindo de volta com a gravidade do planeta.
func _spout_jet(head: Vector3) -> void:
	var up := head.normalized()
	var drops := QuadMesh.new()
	drops.size = Vector2(0.22, 0.22)
	var source: Array = world.get("droplet_emitters") if world.get("droplet_emitters") != null else []
	if not source.is_empty():
		drops.material = (source[0] as GPUParticles3D).draw_pass_1.surface_get_material(0)
	var jet := GPUParticles3D.new()
	jet.amount = 140
	jet.lifetime = 2.2
	jet.one_shot = true
	jet.explosiveness = 0.75
	jet.local_coords = false
	jet.visibility_aabb = AABB(Vector3(-12, -4, -12), Vector3(24, 20, 24))
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.5
	motion.direction = Vector3.UP
	motion.spread = 9.0
	motion.initial_velocity_min = 9.0
	motion.initial_velocity_max = 14.0
	motion.gravity = -up * 9.8
	motion.scale_min = 0.7
	motion.scale_max = 1.6
	jet.process_material = motion
	jet.draw_pass_1 = drops
	add_child(jet)
	var x := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	jet.global_transform = Transform3D(Basis(x, up, x.cross(up)), head)
	jet.emitting = true
	jet.finished.connect(jet.queue_free)

func _free_group(g: Dictionary) -> void:
	for member in g.members:
		free_plate(member.plate)
		if member.has("fin"):
			(member.fin as Node).queue_free()
