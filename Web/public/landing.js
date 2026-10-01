// Landing do portfólio: conteúdo legível na hora + globo leve em Three.js.
// O mundo 3D (Godot, /world/) é pré-carregado em segundo plano quando faz sentido.
import * as THREE from "three";

const ISLAND_FALLBACK = [
	{ id: "sobre", name: "Sobre", lat: 90, lon: 0 },
	{ id: "experiencia", name: "Experiência", lat: 0, lon: 0 },
	{ id: "formacao", name: "Formação", lat: 0, lon: 120 },
	{ id: "projetos", name: "Projetos", lat: 0, lon: 240 },
	{ id: "contato", name: "Contato", lat: -90, lon: 0 },
];
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;

// --- Tema dia/noite pelo horário local (igual ao clima do jogo) ---------------------
const root = document.documentElement;
const themeButton = document.getElementById("theme-toggle");
function applyTheme(theme) {
	root.dataset.theme = theme;
	themeButton.textContent = theme === "night" ? "☀ Dia" : "☾ Noite";
	document.querySelector('meta[name="theme-color"]').content = theme === "night" ? "#1d2537" : "#efe4cc";
	globeTheme?.(theme);
}
let savedTheme = null;
try { savedTheme = localStorage.getItem("carta-theme"); } catch (_) {}
const hour = new Date().getHours();
let globeTheme = null;
applyTheme(savedTheme || (hour >= 18 || hour < 6 ? "night" : "day"));
themeButton.addEventListener("click", () => {
	const next = root.dataset.theme === "night" ? "day" : "night";
	applyTheme(next);
	try { localStorage.setItem("carta-theme", next); } catch (_) {}
});

// --- Conteúdo ---------------------------------------------------------------------------
const el = (tag, attrs = {}, ...children) => {
	const node = document.createElement(tag);
	for (const [key, value] of Object.entries(attrs)) {
		if (key === "class") node.className = value;
		else node.setAttribute(key, value);
	}
	for (const child of children.flat()) {
		if (child == null) continue;
		node.append(child instanceof Node ? child : document.createTextNode(String(child)));
	}
	return node;
};

function renderContent(content) {
	document.querySelectorAll("[data-content]").forEach((node) => {
		const value = content[node.dataset.content];
		if (value) node.textContent = value;
	});
	document.querySelectorAll("[data-link]").forEach((node) => {
		const url = content.links?.[node.dataset.link];
		if (url) node.href = url;
	});
	const stats = document.getElementById("stats");
	for (const stat of content.stats || []) {
		stats.append(el("div", {}, el("dt", {}, stat.label), el("dd", {}, stat.value)));
	}
	const sections = document.getElementById("sections");
	for (const island of content.islands || []) {
		const body = el("div", { class: "chart-body" });
		for (const text of island.paragraphs || []) body.append(el("p", {}, text));
		if (island.facts) {
			body.append(el("dl", { class: "facts" }, island.facts.map((fact) =>
				el("div", {}, el("dt", { class: "kicker" }, fact.label), el("dd", {}, fact.value)))));
		}
		for (const entry of island.entries || []) {
			body.append(el("article", { class: "entry" },
				el("p", { class: "period" }, entry.period),
				el("div", {}, el("h3", {}, entry.title), el("p", { class: "kicker" }, entry.org), entry.text ? el("p", {}, entry.text) : null)));
		}
		for (const project of island.projects || []) {
			body.append(el("article", { class: "project" },
				el("h3", {}, project.title), el("p", {}, project.text),
				el("ul", { class: "stack" }, (project.stack || []).map((tag) => el("li", {}, tag))),
				el("a", { class: "hair small", href: project.url, target: "_blank", rel: "noopener" }, "Código no GitHub ↗")));
		}
		const visit = el("div", { class: "visit" });
		for (const contact of island.contacts || []) {
			visit.append(el("a", { class: "hair", href: content.links[contact.key], target: "_blank", rel: "noopener" }, `${contact.label} ↗`));
		}
		visit.append(el("a", { class: "hair", href: `/world/?ilha=${island.id}` }, "⚓ Visitar esta ilha no mundo 3D"));
		body.append(visit);
		sections.append(el("section", { class: "chart", id: island.id },
			el("header", {}, el("p", { class: "kicker" }, island.kicker), el("h2", {}, island.title)), body));
	}
}

// --- Globo -----------------------------------------------------------------------------
function latLon(lat, lon) {
	const a = THREE.MathUtils.degToRad(lat), b = THREE.MathUtils.degToRad(lon);
	return new THREE.Vector3(Math.cos(a) * Math.cos(b), Math.sin(a), Math.cos(a) * Math.sin(b));
}

function startGlobe(islands, content) {
	const canvas = document.getElementById("globe");
	const pins = document.getElementById("pins");
	let renderer;
	try {
		renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
	} catch (_) {
		canvas.replaceWith(el("p", { class: "faint" }, "Seu navegador não abriu o globo 3D, mas todo o conteúdo está logo abaixo."));
		return;
	}
	renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
	const scene = new THREE.Scene();
	const camera = new THREE.PerspectiveCamera(32, 1, 0.1, 50);
	camera.position.set(0, 0.6, 4.6);
	camera.lookAt(0, 0, 0);
	const globe = new THREE.Group();
	globe.rotation.z = 0.32;
	scene.add(globe);

	// Mar toon: bandas de swell suaves (mesma ideia do shader do jogo, em escala de globo).
	const sea = new THREE.ShaderMaterial({
		uniforms: { time: { value: 0 }, deep: { value: new THREE.Color("#0b5d78") }, shallow: { value: new THREE.Color("#12a1ad") },
			sky: { value: new THREE.Color("#f4ecd8") }, light: { value: new THREE.Vector3(0.5, 0.7, 0.6).normalize() } },
		vertexShader: `varying vec3 vN; varying vec3 vP; varying vec3 vV;
			void main(){ vN = normalize(normalMatrix * normal); vP = position; vec4 mv = modelViewMatrix * vec4(position,1.0); vV = -mv.xyz; gl_Position = projectionMatrix * mv; }`,
		fragmentShader: `uniform float time; uniform vec3 deep; uniform vec3 shallow; uniform vec3 sky; uniform vec3 light;
			varying vec3 vN; varying vec3 vP; varying vec3 vV;
			void main(){
				float swell = sin(dot(vP, vec3(9.0, 3.0, 5.0)) - time * 0.8) * 0.5 + 0.5;
				swell = (floor(swell * 3.0) + smoothstep(0.42, 0.58, fract(swell * 3.0))) / 3.0;
				vec3 color = mix(deep, shallow, 0.35 + 0.5 * swell);
				float diffuse = smoothstep(-0.1, 0.25, dot(normalize(vN), light));
				color *= mix(0.55, 1.05, diffuse);
				float fresnel = pow(1.0 - clamp(dot(normalize(vN), normalize(vV)), 0.0, 1.0), 3.0);
				gl_FragColor = vec4(mix(color, sky, fresnel * 0.55), 1.0);
				#include <colorspace_fragment>
			}`,
	});
	globe.add(new THREE.Mesh(new THREE.SphereGeometry(1, 96, 64), sea));
	const ring = new THREE.Mesh(new THREE.RingGeometry(1.08, 1.085, 128), new THREE.MeshBasicMaterial({ color: "#2b2118", transparent: true, opacity: 0.25, side: THREE.DoubleSide }));
	ring.rotation.x = Math.PI / 2;
	globe.add(ring);

	// Ilhas: montinhos de areia + ponto de mira; etiquetas são botões HTML (acessíveis).
	const islandMat = new THREE.MeshLambertMaterial({ color: "#e8d3a2" });
	const grassMat = new THREE.MeshLambertMaterial({ color: "#5f9b52" });
	const markers = [];
	for (const island of islands) {
		const normal = latLon(island.lat, island.lon);
		const holder = new THREE.Object3D();
		holder.position.copy(normal);
		holder.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), normal);
		const sand = new THREE.Mesh(new THREE.CylinderGeometry(0.1, 0.12, 0.03, 20), islandMat);
		const hill = new THREE.Mesh(new THREE.ConeGeometry(0.065, 0.08, 12), grassMat);
		hill.position.y = 0.04;
		holder.add(sand, hill);
		globe.add(holder);
		const data = (content.islands || []).find((item) => item.id === island.id);
		const pin = el("button", { class: "pin", type: "button", title: data ? data.title : island.name }, `[ ${island.name} ]`);
		pin.addEventListener("click", () => document.getElementById(island.id)?.scrollIntoView({ behavior: reducedMotion ? "auto" : "smooth" }));
		pins.append(pin);
		markers.push({ holder, pin, normal });
	}
	// Chalupa: um pontinho com vela que circula o globo.
	const ship = new THREE.Group();
	const hull = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.02, 0.022), new THREE.MeshLambertMaterial({ color: "#6b4426" }));
	const sail = new THREE.Mesh(new THREE.PlaneGeometry(0.03, 0.04), new THREE.MeshBasicMaterial({ color: "#f6efe0", side: THREE.DoubleSide }));
	sail.position.y = 0.03;
	ship.add(hull, sail);
	globe.add(ship);
	scene.add(new THREE.HemisphereLight("#fff6e0", "#24405a", 1.4));
	const sun = new THREE.DirectionalLight("#fff2d6", 1.2);
	sun.position.set(2, 3, 3);
	scene.add(sun);

	globeTheme = (theme) => {
		const night = theme === "night";
		sea.uniforms.deep.value.set(night ? "#08263f" : "#0b5d78");
		sea.uniforms.shallow.value.set(night ? "#1a7f8c" : "#12a1ad");
		sea.uniforms.sky.value.set(night ? "#2c3752" : "#f4ecd8");
		ring.material.color.set(night ? "#efe4cc" : "#2b2118");
	};
	globeTheme(root.dataset.theme);

	let dragging = false, lastX = 0, velocity = reducedMotion ? 0 : 0.0025;
	canvas.addEventListener("pointerdown", (event) => { dragging = true; lastX = event.clientX; canvas.setPointerCapture(event.pointerId); });
	canvas.addEventListener("pointermove", (event) => { if (!dragging) return; velocity = (event.clientX - lastX) * 0.004; lastX = event.clientX; });
	canvas.addEventListener("pointerup", () => { dragging = false; });

	const resize = () => {
		const rect = canvas.getBoundingClientRect();
		renderer.setSize(rect.width, rect.height, false);
		camera.aspect = rect.width / Math.max(rect.height, 1);
		camera.updateProjectionMatrix();
	};
	new ResizeObserver(resize).observe(canvas);
	resize();

	const projected = new THREE.Vector3();
	const worldNormal = new THREE.Vector3();
	const clock = new THREE.Clock();
	let visible = true;
	new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; }).observe(canvas);
	renderer.setAnimationLoop(() => {
		if (!visible) return;
		const t = clock.getElapsedTime();
		sea.uniforms.time.value = t;
		globe.rotation.y += velocity;
		if (!dragging && !reducedMotion) velocity += (0.0025 - velocity) * 0.02;
		const shipNormal = latLon(18 * Math.sin(t * 0.21), t * 9);
		ship.position.copy(shipNormal.multiplyScalar(1.005));
		ship.lookAt(latLon(18 * Math.sin((t + 0.1) * 0.21), (t + 0.1) * 9).multiplyScalar(1.005));
		ship.up.copy(shipNormal.normalize());
		renderer.render(scene, camera);
		const rect = canvas.getBoundingClientRect();
		for (const marker of markers) {
			marker.holder.getWorldPosition(projected);
			worldNormal.copy(projected).normalize();
			const facing = worldNormal.dot(camera.position.clone().normalize());
			projected.project(camera);
			marker.pin.style.left = `${(projected.x * 0.5 + 0.5) * rect.width}px`;
			marker.pin.style.top = `${(-projected.y * 0.5 + 0.5) * rect.height}px`;
			marker.pin.classList.toggle("hidden", facing < 0.15);
			marker.pin.tabIndex = facing < 0.15 ? -1 : 0;
		}
	});
}

// --- Pré-carga do mundo 3D --------------------------------------------------------------
// Desktop com boa conexão: baixa o jogo em segundo plano enquanto a pessoa lê, para o
// "Zarpar" abrir quase na hora. Celular / economia de dados: só ao clicar.
function preloadWorld() {
	const status = document.getElementById("world-status");
	const connection = navigator.connection || {};
	const slow = connection.saveData || /(^|-)2g|3g/.test(connection.effectiveType || "");
	const small = matchMedia("(max-width: 900px)").matches;
	if (slow || small) {
		status.textContent = "Mundo 3D · ~80 MB, baixa quando você zarpar (melhor no Wi-Fi)";
		return;
	}
	const files = ["/world/index.wasm", "/world/index.pck"];
	let loaded = 0, total = 0;
	const update = () => { status.textContent = total ? `Mundo 3D · preparando ${Math.min(99, Math.round(loaded / total * 100))}%` : "Mundo 3D · preparando…"; };
	Promise.all(files.map(async (file) => {
		const response = await fetch(file);
		if (!response.ok || !response.body) throw new Error(file);
		total += Number(response.headers.get("Content-Length")) || 0;
		const reader = response.body.getReader();
		for (;;) {
			const { done, value } = await reader.read();
			if (done) break;
			loaded += value.length;
			update();
		}
	})).then(() => {
		status.textContent = "Mundo 3D · pronto para zarpar ⚓";
	}).catch(() => {
		status.textContent = "Mundo 3D · disponível ao zarpar";
	});
}

async function main() {
	const content = await fetch("/portfolio_content.json").then((r) => r.json()).catch(() => ({}));
	renderContent(content);
	let islands = ISLAND_FALLBACK;
	try {
		const world = await fetch("/world_config.json").then((r) => r.json());
		islands = (world.islands || []).map((island, index) => {
			const p = island.mount.position;
			const length = Math.hypot(p[0], p[1], p[2]) || 1;
			const lat = Math.asin(p[1] / length) * 180 / Math.PI;
			const lon = Math.atan2(p[2], p[0]) * 180 / Math.PI;
			return { id: ISLAND_FALLBACK[index].id, name: island.title || ISLAND_FALLBACK[index].name, lat, lon };
		});
		if (!islands.length) islands = ISLAND_FALLBACK;
	} catch (_) {}
	startGlobe(islands, content);
	const idle = window.requestIdleCallback || ((fn) => setTimeout(fn, 2500));
	addEventListener("load", () => idle(preloadWorld, { timeout: 4000 }));
}
main();
