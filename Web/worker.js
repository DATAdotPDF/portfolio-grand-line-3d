// Worker do portfólio: serve os assets estáticos e contorna o limite de 25 MiB
// por arquivo do Workers Static Assets para o export do Godot em /world/.
//
//  /world/index.pck  -> concatena /world/pck/part-XX (manifesto index.pck.parts.json)
//  /world/index.wasm -> entrega /world/index.wasm.br com Content-Encoding: br
//                        (o navegador descomprime; ~38 MB viram ~9 MB na rede)

const LONG_CACHE = "public, max-age=31536000, immutable";

async function assetOrNull(env, request, path) {
	const url = new URL(path, request.url);
	const response = await env.ASSETS.fetch(new Request(url, { method: "GET" }));
	return response.ok ? response : null;
}

async function servePck(env, request) {
	const manifest = await assetOrNull(env, request, "/world/index.pck.parts.json");
	if (!manifest) {
		return new Response("pck manifest missing", { status: 500 });
	}
	const { parts, size, version } = await manifest.json();
	const { readable, writable } = new TransformStream();
	(async () => {
		try {
			for (const part of parts) {
				const response = await assetOrNull(env, request, `/world/pck/${part}`);
				if (!response) throw new Error(`missing part ${part}`);
				await response.body.pipeTo(writable, { preventClose: true });
			}
			await writable.close();
		} catch (error) {
			await writable.abort(error);
		}
	})();
	return new Response(readable, {
		headers: {
			"Content-Type": "application/octet-stream",
			"Content-Length": String(size),
			"Cache-Control": LONG_CACHE,
			"ETag": `"pck-${version}"`,
		},
	});
}

async function serveWasm(env, request) {
	const compressed = await assetOrNull(env, request, "/world/index.wasm.br");
	if (!compressed) {
		return env.ASSETS.fetch(request);
	}
	return new Response(compressed.body, {
		encodeBody: "manual",
		headers: {
			"Content-Type": "application/wasm",
			"Content-Encoding": "br",
			"Cache-Control": LONG_CACHE,
		},
	});
}

export default {
	async fetch(request, env) {
		const { pathname } = new URL(request.url);
		if (pathname === "/world/index.pck") {
			return servePck(env, request);
		}
		if (pathname === "/world/index.wasm") {
			return serveWasm(env, request);
		}
		if (pathname === "/world") {
			return Response.redirect(new URL("/world/", request.url).toString() + new URL(request.url).search, 301);
		}
		return env.ASSETS.fetch(request);
	},
};
