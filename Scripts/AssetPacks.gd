extends Node

## Um pacote por modelo dos biomas (só no site): world-<modelo>.pck. O pacote principal traz ilhas,
## navio, mar e interface; os modelos dos biomas chegam conforme o barco se aproxima: o WorldDecor diz
## quais estão perto (want), do mais perto para o mais longe, e este nó baixa um por vez.
## Antes eram 4 pacotes de setor baixados todos na abertura (~470 MB no desktop): a página travava
## (Pedro, 2026-10-17: leme aos 62 s, 1 fps logo depois).
## O pacote fica só na memória da aba (/tmp, sem IndexedDB: gravar 100 MB lá também travava); numa
## nova visita o cache HTTP do navegador devolve o arquivo sem baixar de novo (mesma versão).
## Config/world_packs.json é escrito pelo Web/build_variant.ps1: pasta no site + arquivo (ou partes
## de até 20 MiB), versão e tamanho de cada pacote. Teste fora do navegador: --packs=<pasta com os .pck>.

signal pack_loaded(pack: String)

const MANIFEST := "res://Config/world_packs.json"
const MEMORY_DIR := "/tmp/portfolio_packs"

var manifest := {}
var wanted: Array = []
var mounted := {}
var current := ""
var base_url := ""
var local_dir := ""
var fetching := false
var http: HTTPRequest
var all_wanted_marked := false

func start(order: Array = []) -> void:
	if not FileAccess.file_exists(MANIFEST):
		push_warning("AssetPacks: sem %s" % MANIFEST)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not parsed is Dictionary:
		return
	manifest = parsed
	if OS.has_feature("web"):
		base_url = str(JavaScriptBridge.eval("new URL('.', window.location.href).href", true))
		DirAccess.make_dir_recursive_absolute(MEMORY_DIR)
	else:
		# Teste fora do navegador: --packs=<pasta com os .pck inteiros> (Builds/Web*/packs-full).
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--packs="):
				local_dir = arg.trim_prefix("--packs=")
		http = HTTPRequest.new()
		http.use_threads = true
		add_child(http)
		http.request_completed.connect(_on_downloaded)
	want(order)

## Os pacotes que importam agora, do mais urgente para o menos (o WorldDecor chama a cada ~0,25 s).
func want(names: Array) -> void:
	wanted = names.filter(func(name: String) -> bool: return manifest.get("packs", {}).has(name))
	if current.is_empty():
		_next()

func is_busy() -> bool:
	return not current.is_empty()

func _next() -> void:
	current = ""
	for name in wanted:
		if not mounted.has(name):
			current = name
			break
	if current.is_empty():
		if not wanted.is_empty() and not all_wanted_marked:
			all_wanted_marked = true
			print("ASSET_PACKS modelos perto baixados (%d pacotes)" % mounted.size())
			if OS.has_feature("web"):
				JavaScriptBridge.eval("window.__portfolioMark && window.__portfolioMark('packsLoaded')", true)
		return
	var entry: Dictionary = manifest.packs[current]
	if not local_dir.is_empty():
		_mount(local_dir.path_join(entry.file))
		return
	print("ASSET_PACKS baixando %s (%.1f MB)" % [current, float(entry.size) / 1048576.0])
	var urls: Array = []
	for file in entry.get("parts", [entry.file]):
		urls.append("%s%s/%s?v=%s" % [base_url, manifest.get("dir", "packs"), file, entry.version])
	if OS.has_feature("web"):
		# fetch do navegador (anda na velocidade da rede, não do quadro) e junta as partes.
		JavaScriptBridge.eval("""window.__portfolioPack = { done: false };
			Promise.all(%s.map(function (u) { return fetch(u).then(function (r) {
				if (!r.ok) throw new Error('HTTP ' + r.status + ' ' + u); return r.arrayBuffer(); }); }))
			.then(function (list) {
				var size = list.reduce(function (n, b) { return n + b.byteLength; }, 0);
				var data = new Uint8Array(size), at = 0;
				list.forEach(function (b) { data.set(new Uint8Array(b), at); at += b.byteLength; });
				window.__portfolioPack = { done: true, ok: true, data: data }; })
			.catch(function (e) { window.__portfolioPack = { done: true, ok: false, error: String(e) }; });""" % JSON.stringify(urls), true)
		fetching = true
		return
	var error := http.request(urls[0])
	if error != OK:
		push_warning("AssetPacks: não pediu %s (%d)" % [urls[0], error])
		mounted[current] = false
		_next()

func _process(_delta: float) -> void:
	if not fetching or not bool(JavaScriptBridge.eval("window.__portfolioPack.done", true)):
		return
	fetching = false
	if not bool(JavaScriptBridge.eval("window.__portfolioPack.ok", true)):
		push_warning("AssetPacks: falhou %s (%s)" % [current, JavaScriptBridge.eval("window.__portfolioPack.error", true)])
		mounted[current] = false
		_next()
		return
	# Uint8Array vira PackedByteArray na volta do eval.
	var body: PackedByteArray = JavaScriptBridge.eval("window.__portfolioPack.data", true)
	JavaScriptBridge.eval("window.__portfolioPack = null;", true)
	_store(body)

func _on_downloaded(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_warning("AssetPacks: falhou %s (resultado %d, HTTP %d)" % [current, result, code])
		mounted[current] = false
		_next()
		return
	_store(body)

func _store(body: PackedByteArray) -> void:
	if body.size() != int(manifest.packs[current].size):
		push_warning("AssetPacks: tamanho errado %s (%d bytes)" % [current, body.size()])
		mounted[current] = false
		_next()
		return
	var local := "%s/%s.pck" % [MEMORY_DIR if OS.has_feature("web") else "user://packs", current]
	DirAccess.make_dir_recursive_absolute(local.get_base_dir())
	var file := FileAccess.open(local, FileAccess.WRITE)
	if file == null and OS.has_feature("web"):
		# Reserva: se a memória da aba (/tmp) não abrir, vai para user:// (o caminho antigo, que funciona).
		local = "user://packs/%s.pck" % current
		DirAccess.make_dir_recursive_absolute(local.get_base_dir())
		file = FileAccess.open(local, FileAccess.WRITE)
	if file == null:
		push_warning("AssetPacks: não gravou %s (%d)" % [local, FileAccess.get_open_error()])
		mounted[current] = false
		_next()
		return
	file.store_buffer(body)
	file.close()
	if local.begins_with(MEMORY_DIR) and not ProjectSettings.load_resource_pack(local, false):
		# Reserva também para a montagem: grava em user:// e tenta de novo.
		DirAccess.remove_absolute(local)
		local = "user://packs/%s.pck" % current
		DirAccess.make_dir_recursive_absolute(local.get_base_dir())
		var again := FileAccess.open(local, FileAccess.WRITE)
		if again:
			again.store_buffer(body)
			again.close()
		_mount(local)
		return
	if local.begins_with(MEMORY_DIR):
		mounted[current] = true
		print("ASSET_PACKS %s carregado" % current)
		pack_loaded.emit(current)
		_next()
		return
	_mount(local)

func _mount(local: String) -> void:
	if ProjectSettings.load_resource_pack(local, false):
		mounted[current] = true
		print("ASSET_PACKS %s carregado" % current)
		pack_loaded.emit(current)
	else:
		mounted[current] = false
		push_warning("AssetPacks: pacote inválido %s" % local)
	_next()
