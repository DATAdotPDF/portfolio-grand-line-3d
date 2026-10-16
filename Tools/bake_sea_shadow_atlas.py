import bpy, numpy as np, sys, json, os
args = sys.argv[sys.argv.index("--")+1:]
src_dir, out_png, flips_json = args[0], args[1], args[2]
flips = json.loads(flips_json)  # nome -> graus extras (0 ou 180)
NAMES = [("tubarao", "Meshy_AI_shark-soft-underwater-shadow-texture.png"),
	("arraia", "Meshy_AI_giant-manta-ray-soft-shadow-texture.png"),
	("baleia", "Meshy_AI_whale-soft-underwater-shadow-texture.png"),
	("tubarao_baleia", "Meshy_AI_whale-shark-soft-shadow-texture.png"),
	("kraken", "Meshy_AI_kraken-leviathan-topdown-shadow.png"),
	("foca", "Meshy_AI_single-seal-soft-shadow-texture.png"),
	("golfinho", "Meshy_AI_single-dolphin-soft-shadow-texture.png")]
CELL = 256
def load(path):
	img = bpy.data.images.load(path)
	w, h = img.size
	px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1, :, :3]
	return px
def smooth(e0, e1, x):
	t = np.clip((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t)
def rotate(m, deg):
	h, w = m.shape
	a = np.radians(deg); c, s = np.cos(a), np.sin(a)
	n = int(np.ceil(np.hypot(h, w)))
	yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
	xx -= n / 2; yy -= n / 2
	sx = c * xx + s * yy + w / 2; sy = -s * xx + c * yy + h / 2
	x0 = np.floor(sx).astype(int); y0 = np.floor(sy).astype(int)
	fx = sx - x0; fy = sy - y0
	def at(y, x):
		ok = (x >= 0) & (x < w) & (y >= 0) & (y < h)
		return np.where(ok, m[np.clip(y, 0, h-1), np.clip(x, 0, w-1)], 0.0)
	return (at(y0, x0) * (1-fx) * (1-fy) + at(y0, x0+1) * fx * (1-fy) + at(y0+1, x0) * (1-fx) * fy + at(y0+1, x0+1) * fx * fy)
def resize(m, W, H):
	h, w = m.shape
	ys = (np.arange(H) + 0.5) * h / H - 0.5; xs = (np.arange(W) + 0.5) * w / W - 0.5
	# média por caixa (reduz serrilhado) com amostragem bilinear simples
	y0 = np.clip(np.floor(ys).astype(int), 0, h-2); x0 = np.clip(np.floor(xs).astype(int), 0, w-2)
	fy = (ys - y0)[:, None]; fx = (xs - x0)[None, :]
	return (m[y0][:, x0] * (1-fx) * (1-fy) + m[y0][:, x0+1] * fx * (1-fy) + m[y0+1][:, x0] * (1-fx) * fy + m[y0+1][:, x0+1] * fx * fy)
atlas = np.zeros((CELL * 2, CELL * 4), dtype=np.float32)
info = {}
for i, (name, fn) in enumerate(NAMES):
	px = load(os.path.join(src_dir, fn))
	lum = px @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
	border = np.concatenate([lum[0], lum[-1], lum[:, 0], lum[:, -1]])
	bg = float(np.median(border)); dark = float(np.percentile(lum, 1.0))
	d = (bg - lum) / max(bg - dark, 1e-3)
	# Fundo turquesa/halo some; corpo fica sólido com borda macia.
	lo = 0.62 if name == "tubarao_baleia" else 0.45
	mask = smooth(lo, 0.9, d)
	# blur leve via redução posterior; eixo principal pelos momentos
	ys, xs = np.mgrid[0:mask.shape[0], 0:mask.shape[1]]
	wsum = mask.sum(); cx = (mask * xs).sum() / wsum; cy = (mask * ys).sum() / wsum
	cxx = (mask * (xs - cx) ** 2).sum() / wsum; cyy = (mask * (ys - cy) ** 2).sum() / wsum; cxy = (mask * (xs - cx) * (ys - cy)).sum() / wsum
	ang = 0.5 * np.degrees(np.arctan2(2 * cxy, cxx - cyy))  # eixo maior vs x
	rot = float(flips[name])
	r = rotate(mask, -rot)
	on = np.argwhere(r > 0.05)
	(y0, x0), (y1, x1) = on.min(0), on.max(0) + 1
	r = r[y0:y1, x0:x1]
	h, w = r.shape
	pad = int(max(h, w) * 0.03) + 2
	r = np.pad(r, pad)
	h, w = r.shape
	cell = resize(r, CELL, CELL)
	cy_, cx_ = divmod(i, 4)
	atlas[cy_*CELL:(cy_+1)*CELL, cx_*CELL:(cx_+1)*CELL] = cell
	info[name] = {"cell": i, "aspect_w_over_h": round(w / h, 3), "rot": round(rot, 1)}
out = bpy.data.images.new("atlas", atlas.shape[1], atlas.shape[0], alpha=False)
rgba = np.ones((atlas.shape[0], atlas.shape[1], 4), dtype=np.float32)
rgba[..., 0] = rgba[..., 1] = rgba[..., 2] = atlas
out.pixels = rgba[::-1].ravel()
out.filepath_raw = out_png; out.file_format = "PNG"; out.save()
print("ATLAS " + json.dumps(info))
