// Worker do portfólio: o mundo 3D (Godot) é a página inicial. Serve os assets
// estáticos e contorna o limite de 25 MiB por arquivo do Workers Static Assets:
//
//  /index.pck  -> concatena /pck/part-XX (manifesto /index.pck.parts.json)
//  /index.wasm -> entrega /index.wasm.br com Content-Encoding: br
//                 (o navegador descomprime; ~38 MB viram ~7 MB na rede)
//  /world/*    -> redireciona para / (links antigos), mantendo ?ilha=

const LONG_CACHE = "public, max-age=31536000, immutable";
const GITHUB_USER = "DATAdotPDF";
const PROJECTS_TTL = 900; // 15 min: cada push aparece sozinho, sem novo deploy
const PROJECTS_LIMIT = 4;

// /api/projetos: últimos repositórios públicos (sem forks, sem o repo de perfil),
// ordenados pelo último push. Cache de 1 h na borda; se o GitHub falhar, usa a
// última resposta boa guardada.
async function serveProjects(request, ctx) {
	const cache = caches.default;
	const freshKey = new Request("https://cache.local/api/projetos/fresh");
	const staleKey = new Request("https://cache.local/api/projetos/stale");
	const cached = await cache.match(freshKey);
	if (cached) return withCors(cached);
	try {
		const api = `https://api.github.com/users/${GITHUB_USER}/repos?sort=pushed&direction=desc&per_page=30`;
		const response = await fetch(api, {
			headers: { "User-Agent": "portfolio-data-cybersecurity", "Accept": "application/vnd.github+json" },
		});
		if (!response.ok) throw new Error(`GitHub ${response.status}`);
		const repos = await response.json();
		const projects = repos
			.filter((repo) => !repo.fork && !repo.archived && repo.name.toLowerCase() !== GITHUB_USER.toLowerCase())
			.slice(0, PROJECTS_LIMIT)
			.map((repo) => ({
				name: repo.name,
				description: repo.description || "",
				language: repo.language || "",
				topics: repo.topics || [],
				stars: repo.stargazers_count,
				pushed_at: repo.pushed_at,
				url: repo.html_url,
				homepage: repo.homepage || "",
			}));
		const body = JSON.stringify({ user: GITHUB_USER, updated_at: new Date().toISOString(), projects });
		const fresh = new Response(body, { headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": `public, max-age=${PROJECTS_TTL}` } });
		const stale = new Response(body, { headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "public, max-age=2592000" } });
		ctx.waitUntil(Promise.all([cache.put(freshKey, fresh.clone()), cache.put(staleKey, stale)]));
		return withCors(fresh);
	} catch (error) {
		const stale = await cache.match(staleKey);
		if (stale) return withCors(stale);
		return withCors(new Response(JSON.stringify({ user: GITHUB_USER, projects: [], error: String(error) }), {
			status: 502, headers: { "Content-Type": "application/json; charset=utf-8" },
		}));
	}
}

// /api/leaderboard: ranking permanente do Desafio (20 boias em 3 min), guardado no KV.
// GET  -> top 10.  POST {name, hits, seconds} -> grava e devolve a posição.
// Ordem: mais boias primeiro; empate, menos tempo. O jogo roda no navegador, então a
// validação só barra o absurdo (não é à prova de trapaça).
const BOARD_KEY = "top";
const BOARD_KEEP = 50;
const COURSE_BUOYS = 20;
const COURSE_SECONDS = 180;

function json(body, status = 200) {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
	});
}

async function readBoard(env) {
	const stored = await env.LEADERBOARD.get(BOARD_KEY, "json");
	return Array.isArray(stored) ? stored : [];
}

async function serveLeaderboard(request, env) {
	if (!env.LEADERBOARD) return json({ entries: [], error: "storage indisponível" }, 503);
	if (request.method === "GET") {
		return json({ entries: (await readBoard(env)).slice(0, 10) });
	}
	if (request.method !== "POST") return json({ error: "método não suportado" }, 405);
	let data;
	try {
		data = await request.json();
	} catch {
		return json({ error: "json inválido" }, 400);
	}
	const name = String(data.name || "").toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 5);
	const hits = Number(data.hits);
	const seconds = Math.round(Number(data.seconds) * 10) / 10;
	if (name.length < 1) return json({ error: "nome de 1 a 5 letras ou números" }, 400);
	if (!Number.isInteger(hits) || hits < 0 || hits > COURSE_BUOYS) return json({ error: "boias inválidas" }, 400);
	if (!Number.isFinite(seconds) || seconds < 20 || seconds > COURSE_SECONDS + 1) return json({ error: "tempo inválido" }, 400);
	if (hits < COURSE_BUOYS && seconds < COURSE_SECONDS - 1) return json({ error: "tempo inválido" }, 400);
	// Um envio por minuto por IP (o KV expira a chave sozinho).
	const ip = request.headers.get("CF-Connecting-IP") || "local";
	const limitKey = `rl:${ip}`;
	if (await env.LEADERBOARD.get(limitKey)) return json({ error: "calma, marujo: um registro por minuto" }, 429);
	await env.LEADERBOARD.put(limitKey, "1", { expirationTtl: 60 });
	const entry = { name, hits, seconds, at: new Date().toISOString().slice(0, 10) };
	const board = await readBoard(env);
	board.push(entry);
	board.sort((a, b) => b.hits - a.hits || a.seconds - b.seconds || a.at.localeCompare(b.at));
	const rank = board.indexOf(entry) + 1;
	await env.LEADERBOARD.put(BOARD_KEY, JSON.stringify(board.slice(0, BOARD_KEEP)));
	return json({ rank, entries: board.slice(0, 10) });
}

function withCors(response) {
	const copy = new Response(response.body, response);
	copy.headers.set("Access-Control-Allow-Origin", "*");
	return copy;
}

async function assetOrNull(env, request, path) {
	const response = await env.ASSETS.fetch(new Request(new URL(path, request.url), { method: "GET" }));
	return response.ok ? response : null;
}

async function servePck(env, request, ctx) {
	const manifest = await assetOrNull(env, request, "/index.pck.parts.json");
	if (!manifest) {
		return new Response("pck manifest missing", { status: 500 });
	}
	const { parts, size, version } = await manifest.json();
	const { readable, writable } = new TransformStream();
	// waitUntil mantém o Worker vivo até a última parte: sem isso a resposta era cortada no meio.
	const pump = (async () => {
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
	ctx.waitUntil(pump);
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
	async fetch(request, env, ctx) {
		const url = new URL(request.url);
		if (url.pathname === "/api/projetos") {
			return serveProjects(request, ctx);
		}
		if (url.pathname === "/api/leaderboard") {
			return serveLeaderboard(request, env);
		}
		if (url.pathname === "/index.pck") {
			return servePck(env, request, ctx);
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
