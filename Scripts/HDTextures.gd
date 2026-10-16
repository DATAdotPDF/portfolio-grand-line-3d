extends Node

## Texturas originais perto do barco (só no site). O pacote do site traz os modelos com textura base
## (desktop 2048, celular 1024) para abrir rápido; quando um modelo chega perto, este nó baixa as
## texturas originais dele (desktop até 4096, celular até 2048: Tests/export_hd_textures.gd) e troca no
## material; quando o barco se afasta, volta a textura base e solta a original da memória de vídeo.
## Pedro, 2026-10-16: o navegador o mais perto possível do modelo em 4K, sem baixar a qualidade antes
## do deploy — a redução é no jogo.
## Manifesto: res://Config/hd_textures.json (Web/build_variant.ps1) = {"dir", "models": {glb: [
##   {material, prop, file, size, v}]}}. Teste fora do navegador: --hd=<pasta com desktop/ e mobile/>.

const MANIFEST := "res://Config/hd_textures.json"
const RANGE_DESKTOP := 320.0
const RANGE_MOBILE := 180.0
const MARGIN := 70.0
## Quantos modelos ao mesmo tempo com textura original (memória de vídeo).
const ACTIVE_DESKTOP := 10
const ACTIVE_MOBILE := 4
const TMP := "user://hd_tmp.res"

var world: Node3D
var models := {}
var dir := ""
var base_url := ""
var local_dir := ""
var hd_range := RANGE_DESKTOP
var max_active := ACTIVE_DESKTOP
## glb → {file: ImageTexture} (prontas) e os materiais já trocados (id → [material, prop, base]).
var loaded := {}
var swapped := {}
var queue: Array = []   # [glb, entry]
var fetching := {}      # entry em download (web)
var timer := 0.0

func _ready() -> void:
	if not FileAccess.file_exists(MANIFEST):
		set_process(false)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not parsed is Dictionary:
		set_process(false)
		return
	models = parsed.get("models", {})
	dir = str(parsed.get("dir", "hd/desktop"))
	if OS.has_feature("mobile_lite"):
		hd_range = RANGE_MOBILE
		max_active = ACTIVE_MOBILE
	if OS.has_feature("web"):
		base_url = str(JavaScriptBridge.eval("new URL('.', window.location.href).href", true))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hd="):
			local_dir = arg.trim_prefix("--hd=")
	print("HD_TEXTURES %d modelos com textura original (%s)" % [models.size(), dir])

## Modelos na cena agora: [glb, nó do modelo, distância ao barco].
func _targets(ship_pos: Vector3) -> Array:
	var out := []
	var decor: Node = world.get("world_decor")
	if decor:
		for item in decor.items:
			if item.model != null:
				out.append([decor._model_path(item.kind), item.model, ship_pos.distance_to((item.root as Node3D).global_position) - float(item.radius)])
	var beasts: Node = world.get("sea_beasts")
	if beasts:
		for beast in beasts.beasts:
			var spec: Dictionary = beasts.KINDS.get(beast.name, {})
			if spec.has("model") and is_instance_valid(beast.model):
				out.append([spec.model, beast.model, ship_pos.distance_to((beast.root as Node3D).global_position) - 150.0])
	return out

func _process(delta: float) -> void:
	if world == null or world.get("ship") == null:
		return
	if not fetching.is_empty():
		_poll_fetch()
	timer -= delta
	if timer > 0.0:
		return
	timer = 0.5
	var targets := _targets(world.ship.global_position)
	var nearest := {}
	for t in targets:
		if models.has(t[0]):
			nearest[t[0]] = minf(float(nearest.get(t[0], INF)), float(t[2]))
	var wanted: Array = nearest.keys().filter(func(glb: String) -> bool: return float(nearest[glb]) < hd_range)
	wanted.sort_custom(func(a: String, b: String) -> bool: return float(nearest[a]) < float(nearest[b]))
	wanted = wanted.slice(0, max_active)
	# Longe (ou fora da cota): volta a textura base e solta a original.
	for glb in loaded.keys():
		if not wanted.has(glb) and float(nearest.get(glb, INF)) > hd_range + MARGIN or not wanted.has(glb) and loaded.size() > max_active:
			_release(glb)
	# Perto: pede o que falta (um arquivo por vez) e troca nos modelos que já estão na cena.
	for glb in wanted:
		for entry in models[glb]:
			var have: Dictionary = loaded.get(glb, {})
			if not have.has(entry.file) and not _queued(entry.file):
				queue.append([glb, entry])
	for t in targets:
		if loaded.has(t[0]):
			_apply(t[0], t[1])
	if fetching.is_empty() and not queue.is_empty():
		_fetch(queue.pop_front())

func _queued(file: String) -> bool:
	if fetching.get("entry", {}).get("file", "") == file:
		return true
	for q in queue:
		if q[1].file == file:
			return true
	return false

func _fetch(job: Array) -> void:
	var entry: Dictionary = job[1]
	if not local_dir.is_empty():
		var image := ResourceLoader.load(local_dir.path_join(dir.get_file()).path_join(entry.file), "Image", ResourceLoader.CACHE_MODE_IGNORE) as Image
		_done(job[0], entry, image)
		return
	if not OS.has_feature("web"):
		return
	var url := "%s%s/%s?v=%s" % [base_url, dir, entry.file, entry.get("v", "")]
	JavaScriptBridge.eval("""window.__portfolioHd = { done: false };
		fetch(%s).then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.arrayBuffer(); })
		.then(function (b) { window.__portfolioHd = { done: true, ok: true, data: new Uint8Array(b) }; })
		.catch(function (e) { window.__portfolioHd = { done: true, ok: false, error: String(e) }; });""" % JSON.stringify(url), true)
	fetching = {"glb": job[0], "entry": entry}

func _poll_fetch() -> void:
	if not bool(JavaScriptBridge.eval("window.__portfolioHd && window.__portfolioHd.done", true)):
		return
	var job := fetching
	fetching = {}
	if not bool(JavaScriptBridge.eval("window.__portfolioHd.ok", true)):
		push_warning("HDTextures: falhou %s (%s)" % [job.entry.file, JavaScriptBridge.eval("window.__portfolioHd.error", true)])
		return
	var body: PackedByteArray = JavaScriptBridge.eval("window.__portfolioHd.data", true)
	JavaScriptBridge.eval("window.__portfolioHd = null;", true)
	# A imagem vem como recurso do Godot: grava, carrega e apaga (o arquivo não fica na memória).
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_buffer(body)
	f.close()
	var image := ResourceLoader.load(TMP, "Image", ResourceLoader.CACHE_MODE_IGNORE) as Image
	DirAccess.remove_absolute(TMP)
	_done(job.glb, job.entry, image)

func _done(glb: String, entry: Dictionary, image: Image) -> void:
	if image == null or image.is_empty():
		push_warning("HDTextures: imagem inválida %s" % entry.file)
		return
	var have: Dictionary = loaded.get(glb, {})
	have[entry.file] = ImageTexture.create_from_image(image)
	loaded[glb] = have
	print("HD_TEXTURES %s %s (%dx%d)" % [glb.get_file().left(32), entry.prop, image.get_width(), image.get_height()])

## Troca as texturas prontas nos materiais desse modelo (uma vez por material).
func _apply(glb: String, model: Node) -> void:
	var have: Dictionary = loaded[glb]
	var done: Dictionary = swapped.get(glb, {})
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as StandardMaterial3D
			if mat == null:
				continue
			for entry in models[glb]:
				if entry.material != mat.resource_name or not have.has(entry.file):
					continue
				var key := "%d|%s" % [mat.get_instance_id(), entry.prop]
				if done.has(key):
					continue
				done[key] = [mat, entry.prop, mat.get(entry.prop)]
				mat.set(entry.prop, have[entry.file])
	swapped[glb] = done

func _release(glb: String) -> void:
	for key in swapped.get(glb, {}):
		var rec: Array = swapped[glb][key]
		if is_instance_valid(rec[0]):
			(rec[0] as Material).set(rec[1], rec[2])
	swapped.erase(glb)
	loaded.erase(glb)
	queue = queue.filter(func(q: Array) -> bool: return q[0] != glb)
