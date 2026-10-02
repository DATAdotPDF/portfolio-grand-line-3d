// Worker do portfólio: o mundo 3D (Godot) é a página inicial. Serve os assets
// estáticos e contorna o limite de 25 MiB por arquivo do Workers Static Assets:
//
//  /index.pck  -> concatena /pck/part-XX (manifesto /index.pck.parts.json)
//  /index.wasm -> entrega /index.wasm.br com Content-Encoding: br
//                 (o navegador descomprime; ~38 MB viram ~7 MB na rede)
//  /world/*    -> redireciona para / (links antigos), mantendo ?ilha=

const LONG_CACHE = "public, max-age=31536000, immutable";

async function assetOrNull(env, request, path) {
	const response = await env.ASSETS.fetch(new Request(new URL(path, request.url), { method: "GET" }));
	return response.ok ? response : null;
}

async function servePck(env, request) {
	const manifest = await assetOrNull(env, request, "/index.pck.parts.json");
	if (!manifest) {
		return new Response("pck manifest missing", { status: 500 });
	}
	const { parts, size, version } = await manifest.json();
	const { readable, writable } = new TransformStream();
	(async () => {
		try {
			for (const part of parts) {
				const response = await assetOrNull(env, request, `/pck/${part}`);
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
	const compressed = await assetOrNull(env, request, "/index.wasm.br");
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
		const url = new URL(request.url);
		if (url.pathname === "/index.pck") {
			return servePck(env, request);
		}
		if (url.pathname === "/index.wasm") {
			return serveWasm(env, request);
		}
		if (url.pathname === "/world" || url.pathname.startsWith("/world/")) {
			return Response.redirect(new URL("/" + url.search, request.url).toString(), 301);
		}
		return env.ASSETS.fetch(request);
	},
};
