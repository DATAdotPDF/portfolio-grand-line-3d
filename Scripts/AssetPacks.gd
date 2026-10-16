extends Node

## Pacotes de modelos por setor (só no site). O pacote principal traz ilhas, navio, mar e interface; os
## modelos dos biomas vêm em world-<setor>.pck, baixados em segundo plano depois que o mundo abre, um
## por vez, na ordem pedida (o setor do barco primeiro). Cada pacote baixado fica no navegador
## (user://, IndexedDB): na próxima visita só baixa de novo se a versão mudou.
## Config/world_packs.json é escrito pelo Web/build_variant.ps1: pasta no site + arquivo, versão e
## tamanho de cada pacote.

signal pack_loaded(pack: String)

const MANIFEST := "res://Config/world_packs.json"
const CACHE_DIR := "user://packs"

var manifest := {}
var queue: Array = []
var current := ""
var base_url := ""
var local_dir := ""
var http: HTTPRequest
## Site: o download é um fetch do navegador (anda na velocidade da rede; o HTTPRequest lia um
## pedaço por quadro, e com a aba em segundo plano ou num celular lento demorava minutos).
var fetching := false

func start(order: Array) -> void:
	if not FileAccess.file_exists(MANIFEST):
		push_warning("AssetPacks: sem %s" % MANIFEST)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not parsed is Dictionary:
		return
	manifest = parsed
	var packs: Dictionary = manifest.get("packs", {})
	for pack in order:
		if packs.has(pack):
			queue.append(pack)
	if OS.has_feature("web"):
		base_url = str(JavaScriptBridge.eval("new URL('.', window.location.href).href", true))
	else:
		# Teste fora do navegador: --packs=<pasta com os .pck> (Tests/stress_sail.gd no espelho do site).
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--packs="):
				local_dir = arg.trim_prefix("--packs=")
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	if not OS.has_feature("web"):
		http = HTTPRequest.new()
		http.use_threads = true
		add_child(http)
		http.request_completed.connect(_on_downloaded)
	_next()

func _local_path(pack: String) -> String:
	return "%s/%s-%s.pck" % [CACHE_DIR, pack, manifest.packs[pack].version]

func _next() -> void:
	if queue.is_empty():
		current = ""
		print("ASSET_PACKS todos carregados")
		return
	current = queue.pop_front()
	var entry: Dictionary = manifest.packs[current]
	if not local_dir.is_empty():
		_mount(local_dir.path_join(entry.file))
		return
	var local := _local_path(current)
	if FileAccess.file_exists(local) and FileAccess.open(local, FileAccess.READ).get_length() == int(entry.size):
		_mount(local)
		return
	# Versões antigas deste pacote saem do navegador.
	for file in DirAccess.get_files_at(CACHE_DIR):
		if file.begins_with(current + "-"):
			DirAccess.remove_absolute(CACHE_DIR + "/" + file)
	var url := "%s%s/%s?v=%s" % [base_url, manifest.get("dir", "packs"), entry.file, entry.version]
	print("ASSET_PACKS baixando %s (%.1f MB)" % [current, float(entry.size) / 1048576.0])
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""window.__portfolioPack = { done: false };
			fetch(%s).then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.arrayBuffer(); })
			.then(function (b) { window.__portfolioPack = { done: true, ok: true, data: new Uint8Array(b) }; })
			.catch(function (e) { window.__portfolioPack = { done: true, ok: false, error: String(e) }; });""" % JSON.stringify(url), true)
		fetching = true
		return
	var error := http.request(url)
	if error != OK:
		push_warning("AssetPacks: não pediu %s (%d)" % [url, error])
		_next()

func _process(_delta: float) -> void:
	if not fetching or not bool(JavaScriptBridge.eval("window.__portfolioPack.done", true)):
		return
	fetching = false
	if not bool(JavaScriptBridge.eval("window.__portfolioPack.ok", true)):
		push_warning("AssetPacks: falhou %s (%s)" % [current, JavaScriptBridge.eval("window.__portfolioPack.error", true)])
		_next()
		return
	# Uint8Array vira PackedByteArray na volta do eval.
	var body: PackedByteArray = JavaScriptBridge.eval("window.__portfolioPack.data", true)
	JavaScriptBridge.eval("window.__portfolioPack = null;", true)
	_store(body)

## O corpo vem na memória e é gravado aqui (no navegador o download_file do HTTPRequest não gravava).
func _on_downloaded(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_warning("AssetPacks: falhou %s (resultado %d, HTTP %d)" % [current, result, code])
		_next()
		return
	_store(body)

func _store(body: PackedByteArray) -> void:
	var local := _local_path(current)
	if body.size() != int(manifest.packs[current].size):
		push_warning("AssetPacks: tamanho errado %s (%d bytes)" % [current, body.size()])
		_next()
		return
	var file := FileAccess.open(local, FileAccess.WRITE)
	if file == null:
		push_warning("AssetPacks: não gravou %s (%d)" % [local, FileAccess.get_open_error()])
		_next()
		return
	file.store_buffer(body)
	file.close()
	_mount(local)

func _mount(local: String) -> void:
	if not local_dir.is_empty():
		# Teste: um intervalo entre os pacotes, como se estivessem baixando.
		await get_tree().create_timer(1.0).timeout
	if ProjectSettings.load_resource_pack(local, false):
		print("ASSET_PACKS %s carregado" % current)
		pack_loaded.emit(current)
	else:
		var f := FileAccess.open(local, FileAccess.READ)
		push_warning("AssetPacks: pacote inválido %s (%d bytes, início %s)" % [local, f.get_length() if f else -1, f.get_buffer(8).hex_encode() if f else "-"])
		DirAccess.remove_absolute(local)
	_next()
