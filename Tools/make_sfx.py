# Gera os efeitos sonoros sintetizados do clima/mar (ruído filtrado, envelopes, varreduras).
# Tudo feito aqui, sem amostras de terceiros. Usa numpy (roda pelo Python do Blender):
#   D:\Blender\blender.exe -b --factory-startup -P Tools/make_sfx.py -- <pasta_saida>
# Saída: WAV 44,1 kHz mono; os loops têm as pontas cruzadas para emendar sem clique.
import sys, os, wave
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0] if argv else "Builds/SfxPreview")
# Segundo argumento opcional: lista de nomes a gerar (vírgula). Sem ele, gera tudo.
ONLY = set(argv[1].split(",")) if len(argv) > 1 else None
os.makedirs(OUT, exist_ok=True)
SR = 44100
rng = np.random.default_rng(20261006)


def t_axis(seconds):
    return np.arange(int(seconds * SR)) / SR


def white(n):
    return rng.uniform(-1.0, 1.0, n)


def pink(n):
    # Filtro de Paul Kellet (ruído rosa).
    w = white(n)
    b = np.zeros(7)
    out = np.empty(n)
    for i in range(n):
        x = w[i]
        b[0] = 0.99886 * b[0] + x * 0.0555179
        b[1] = 0.99332 * b[1] + x * 0.0750759
        b[2] = 0.96900 * b[2] + x * 0.1538520
        b[3] = 0.86650 * b[3] + x * 0.3104856
        b[4] = 0.55000 * b[4] + x * 0.5329522
        b[5] = -0.7616 * b[5] - x * 0.0168980
        out[i] = b[0] + b[1] + b[2] + b[3] + b[4] + b[5] + b[6] + x * 0.5362
        b[6] = x * 0.115926
    return out / np.max(np.abs(out))


def brown(n):
    w = white(n) * 0.02
    out = np.cumsum(w)
    out -= lowpass(out, 5.0)  # tira a deriva
    return out / (np.max(np.abs(out)) + 1e-9)


def lowpass(x, fc):
    fc = np.broadcast_to(np.asarray(fc, dtype=float), x.shape)
    a = 1.0 - np.exp(-2.0 * np.pi * fc / SR)
    y = np.empty_like(x)
    s = 0.0
    for i in range(len(x)):
        s += a[i] * (x[i] - s)
        y[i] = s
    return y


def highpass(x, fc):
    return x - lowpass(x, fc)


def bandpass(x, fc, q=1.0):
    # Filtro de estado variável (Chamberlin), frequência pode variar no tempo.
    fc = np.broadcast_to(np.asarray(fc, dtype=float), x.shape)
    f = 2.0 * np.sin(np.pi * np.minimum(fc, SR / 6) / SR)
    damp = 1.0 / q
    low = band = 0.0
    y = np.empty_like(x)
    for i in range(len(x)):
        low += f[i] * band
        high = x[i] - low - damp * band
        band += f[i] * high
        y[i] = band
    return y


def env_ad(n, attack, decay_tau):
    t = np.arange(n) / SR
    return np.where(t < attack, t / max(attack, 1e-4), np.exp(-(t - attack) / decay_tau))


def slow_noise(n, rate):
    # Ruído suave (0..1) para modulações lentas.
    k = max(2, int(n / SR * rate) + 2)
    pts = rng.uniform(0.0, 1.0, k)
    xs = np.linspace(0, n, k)
    return np.interp(np.arange(n), xs, pts)


def droplets(n, per_second, amp):
    out = np.zeros(n)
    count = int(n / SR * per_second)
    for _ in range(count):
        start = rng.integers(0, n - 2000)
        freq = rng.uniform(2200, 6000)
        length = int(SR * rng.uniform(0.008, 0.02))
        tt = np.arange(length) / SR
        out[start:start + length] += np.sin(2 * np.pi * freq * tt) * np.exp(-tt / 0.004) * amp * rng.uniform(0.3, 1.0)
    return out


def loopify(x, cross=1.0):
    # Cruza o fim com o começo: o arquivo emenda sem clique quando toca em loop.
    m = int(cross * SR)
    fade = np.linspace(0.0, 1.0, m)
    head = x[:m] * fade + x[-m:] * (1.0 - fade)
    return np.concatenate([head, x[m:-m]])


def save(name, x, peak=0.85):
    if ONLY is not None and name not in ONLY:
        return
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    data = (x * 32767).astype(np.int16)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("SFX", name, "%.1fs" % (len(x) / SR), flush=True)


# 1. Chuva leve (loop): chiado rosa + gotas esparsas.
n = int(13 * SR)
rain = highpass(lowpass(pink(n), 7000), 500) * 0.5 + droplets(n, 35, 0.25)
save("rain_light_loop", loopify(rain), 0.55)

# 2. Chuva forte (loop): mais grave e cheia + muitas gotas.
rain = highpass(lowpass(pink(n), 5000), 180) * 0.7 + lowpass(brown(n), 300) * 0.35 + droplets(n, 160, 0.2)
rain *= 0.85 + 0.15 * slow_noise(n, 0.6)
save("rain_heavy_loop", loopify(rain), 0.75)

# 3. Vento de tempestade (loop): marrom em banda que "respira" + uivo fino variando.
n = int(15 * SR)
t = t_axis(15)
lfo = 0.5 + 0.5 * np.sin(2 * np.pi * 0.13 * t) * 0.6 + 0.4 * slow_noise(n, 0.5)
body = bandpass(brown(n) + pink(n) * 0.3, 260 + 340 * lfo, 0.9)
howl = bandpass(pink(n), 520 + 380 * slow_noise(n, 0.35), 9.0) * 0.6
wind = (body * (0.6 + 0.4 * lfo) + howl * lfo) * 1.0
save("wind_storm_loop", loopify(wind, 1.5), 0.7)

# 4. Rajada (4 s): sobe, passa e some.
n = int(4.2 * SR)
t = t_axis(4.2)
sweep = np.interp(t, [0, 1.3, 4.2], [300, 1300, 380])
gust = bandpass(pink(n), sweep, 1.3)
envelope = np.interp(t, [0, 1.2, 2.2, 4.2], [0, 1, 0.7, 0])
save("wind_gust", gust * envelope, 0.8)

# 5. Trovão próximo (7 s): estalos + ronco rolando.
n = int(7 * SR)
t = t_axis(7)
crack = np.zeros(n)
for k in range(rng.integers(5, 9)):
    start = int(rng.uniform(0.0, 0.5) * SR)
    length = int(rng.uniform(0.04, 0.14) * SR)
    burst = highpass(white(length), 1500) * env_ad(length, 0.002, 0.03)
    crack[start:start + length] += burst * rng.uniform(0.5, 1.0)
rumble = lowpass(brown(n), 140 + 120 * slow_noise(n, 2.0)) * env_ad(n, 0.12, 2.2)
rumble *= 0.55 + 0.45 * slow_noise(n, 4.0)
save("thunder_near", crack * 0.9 + rumble * 1.6, 0.9)

# 6. Trovão distante (6 s): só o ronco, abafado.
n = int(6 * SR)
rumble = lowpass(brown(n), 110) * env_ad(n, 0.7, 2.0) * (0.5 + 0.5 * slow_noise(n, 3.0))
save("thunder_far", rumble, 0.7)

# 7. Ciclone (loop): rugido grave + "whoosh" girando + sub-grave pulsando.
n = int(12 * SR)
t = t_axis(12)
roar = lowpass(brown(n), 480) * 0.8
spin = bandpass(pink(n), 180 + 90 * np.sin(2 * np.pi * 0.5 * t), 2.5) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.5 * t + 1.0))
sub = np.sin(2 * np.pi * 38 * t) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.25 * t)) * 0.25
save("cyclone_loop", loopify(roar + spin + sub, 1.5), 0.8)

# 8. Whoosh do teleporte (2,8 s): ruído varrendo para cima, mais suave (topo mais baixo,
#    filtro mais aberto, entrada e saída longas).
n = int(2.8 * SR)
t = t_axis(2.8)
sweep = np.interp(t, [0, 1.8, 2.8], [180, 1600, 2100])
whoosh = lowpass(bandpass(pink(n), sweep, 0.9), 3500) * np.interp(t, [0, 1.1, 1.9, 2.8], [0, 1, 0.75, 0])
save("teleport_whoosh", whoosh, 0.6)

# 9. Borrifo da baleia (1,8 s): sopro chiado.
n = int(1.8 * SR)
blow = lowpass(highpass(white(n), 700), 6000) * env_ad(n, 0.05, 0.45)
blow += bandpass(pink(n), 900, 1.5) * env_ad(n, 0.03, 0.3) * 0.6
save("whale_blow", blow, 0.75)


# --- Água e madeira (sintetizados por física simples) -----------------------------

def bubbles(n, count, start_spread, f_lo, f_hi, amp):
    # Bolha: seno curto cuja frequência sobe enquanto ela sobe e estoura (som real de bolha).
    out = np.zeros(n)
    for _ in range(count):
        start = int(rng.uniform(0.0, start_spread) * SR)
        length = int(rng.uniform(0.03, 0.09) * SR)
        if start + length >= n:
            continue
        tt = np.arange(length) / SR
        f0 = rng.uniform(f_lo, f_hi)
        freq = f0 * (1.0 + tt * rng.uniform(4.0, 9.0))
        phase = 2 * np.pi * np.cumsum(freq) / SR
        out[start:start + length] += np.sin(phase) * np.exp(-tt / rng.uniform(0.012, 0.03)) * amp * rng.uniform(0.4, 1.0)
    return out


def water_splash(seconds, size):
    # size 0 (gota/peixe) .. 1 (casco caindo): corpo de ruído + bolhas + "cauda" de respingos.
    n = int(seconds * SR)
    body = bandpass(white(n), 900 + 1400 * (1.0 - size), 0.8) * env_ad(n, 0.004 + 0.01 * size, 0.06 + 0.18 * size)
    hiss = lowpass(highpass(white(n), 2500), 9000) * env_ad(n, 0.01, 0.1 + 0.25 * size) * 0.35
    drops = droplets(n, 25 + 60 * size, 0.08) * np.interp(np.arange(n) / SR, [0, 0.05, seconds], [0, 1, 0])
    bub = bubbles(n, int(6 + 18 * size), 0.12 + 0.3 * size, 300 + 500 * (1.0 - size), 900 + 900 * (1.0 - size), 0.35)
    return body + hiss + drops + bub


def wood_knock(seconds, pitch, softness):
    # Casco de madeira batendo: baque grave que cai de tom + ressonâncias de tábua.
    n = int(seconds * SR)
    t = np.arange(n) / SR
    freq = pitch * (1.0 + 0.6 * np.exp(-t / 0.03))
    thump = np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t / (0.09 + 0.05 * softness))
    modes = sum(np.sin(2 * np.pi * f * t) * np.exp(-t / d) * a for f, d, a in [(pitch * 2.7, 0.07, 0.35), (pitch * 4.1, 0.05, 0.22), (pitch * 6.3, 0.03, 0.12)])
    click = lowpass(white(n), 2500 - 1500 * softness) * env_ad(n, 0.001, 0.008) * 0.4
    return thump + modes + click


# 10. Proa batendo na onda: madeira grave + água, suave.
x = wood_knock(1.3, 95, 0.8) * 0.9 + water_splash(1.3, 0.7) * 0.7
save("bow_slam_heavy", lowpass(x, 5000), 0.6)

# 11. Queda depois do salto: baque mais cheio de madeira na água + espalhada.
x = wood_knock(1.6, 75, 1.0) * 1.0 + water_splash(1.6, 1.0) * 0.8
save("landing_splash", lowpass(x, 4500), 0.6)

# 12. Golfinho entrando/saindo d'água: respingo médio e natural.
save("dolphin_splash", water_splash(0.9, 0.45), 0.5)

# 13. Peixe pulando: gotinha.
save("fish_plop", water_splash(0.45, 0.08), 0.35)


# --- Navegação, tempestade e alvos (2026-10-09) ---------------------------------------

def hits(n, times, make):
    # Soma eventos curtos (make(i) devolve o trecho) nos instantes dados (s).
    out = np.zeros(n)
    for i, start_s in enumerate(times):
        piece = make(i)
        start = int(start_s * SR)
        end = min(n, start + len(piece))
        if start < n:
            out[start:end] += piece[:end - start]
    return out


# 14. Água correndo no casco (loop): chiado de água em banda + marulho grave batendo nas tábuas
#     + espuma fina + bolhas. O jogo sobe o volume e o tom com a velocidade do barco.
n = int(12 * SR)
t = t_axis(12)
swell = 0.6 + 0.25 * np.sin(2 * np.pi * t / 4.0) + 0.15 * slow_noise(n, 0.8)
rush = bandpass(pink(n), 650 + 450 * slow_noise(n, 0.5), 0.7) * swell
slosh = lowpass(brown(n), 260) * (0.5 + 0.5 * np.sin(2 * np.pi * t / 3.0 + 1.0) ** 2)
foam = lowpass(highpass(white(n), 3000), 8000) * 0.12 * swell
laps = hits(n, np.cumsum(rng.uniform(0.9, 2.2, 10)),
            lambda i: bandpass(white(int(0.35 * SR)), rng.uniform(220, 420), 1.4) * env_ad(int(0.35 * SR), 0.02, 0.07))
wash = rush * 0.9 + slosh * 0.55 + foam + laps * 0.5 + bubbles(n, 140, 11.5, 350, 1100, 0.12)
save("hull_wash_loop", loopify(lowpass(wash, 7000), 1.5), 0.7)

# 15. Vento na vela cheia (loop): sopro em banda que respira + zumbido fino do cordame.
n = int(12 * SR)
breath = 0.65 + 0.35 * slow_noise(n, 0.4)
body = bandpass(pink(n), 330 + 260 * slow_noise(n, 0.3), 0.8) * breath
rigging = bandpass(pink(n), 1050 + 250 * slow_noise(n, 0.25), 14.0) * 0.35 * slow_noise(n, 0.2)
rustle = lowpass(highpass(pink(n), 2200), 6000) * 0.08 * breath
save("sail_wind_loop", loopify(body + rigging + rustle, 1.5), 0.65)

# 16. Vela panejando (loop): lona batendo sem vento cheio (proa contra o vento); batidas rápidas
#     e irregulares de lona + estalos maiores de vez em quando.
n = int(8 * SR)
times = []
s = 0.0
while s < 7.8:
    times.append(s)
    s += rng.uniform(0.09, 0.22) if rng.random() < 0.8 else rng.uniform(0.3, 0.6)


def flap(i):
    m = int(rng.uniform(0.05, 0.12) * SR)
    big = rng.random() < 0.15
    x = bandpass(white(m), rng.uniform(800, 1800), 1.2) * env_ad(m, 0.002, 0.03 if big else 0.018)
    thump = lowpass(white(m), 180) * env_ad(m, 0.004, 0.03) * 2.0
    return (x + thump) * (1.6 if big else rng.uniform(0.4, 0.9))


luff = hits(n, times, flap) + bandpass(pink(n), 500, 0.8) * 0.12
save("sail_luff_loop", loopify(luff, 0.5), 0.6)

# 17. Mar de tempestade (loop): ondas grandes rolando (grave que sobe e desce a cada ~5 s) e
#     arrebentação com espuma na crista de cada uma.
n = int(16 * SR)
t = t_axis(16)
period = 16.0 / 3.0
phase = (t % period) / period
swell = np.sin(np.pi * phase) ** 2
roll = lowpass(brown(n), 220 + 160 * swell) * (0.45 + 0.55 * swell)
crests = hits(n, [period * k + rng.uniform(0.45, 0.6) * period for k in range(3)],
              lambda i: lowpass(highpass(pink(int(3.2 * SR)), 250), 3800) * env_ad(int(3.2 * SR), 0.35, 0.9))
foam = lowpass(highpass(white(n), 2500), 7000) * 0.1 * (0.3 + swell)
storm_sea = roll * 1.0 + crests * 0.8 + foam
save("storm_sea_loop", loopify(storm_sea, 2.0), 0.75)

# 18. Onda grande arrebentando no casco (3,5 s): baque de madeira grave + água pesada + rugido
#     de espuma que vai sumindo.
n = int(3.5 * SR)
t = t_axis(3.5)
roar = lowpass(pink(n), 2400) * env_ad(n, 0.08, 0.8)
fizz = lowpass(highpass(white(n), 3000), 9000) * np.interp(t, [0, 0.2, 1.0, 3.5], [0, 0.25, 0.15, 0])
knock = np.concatenate([wood_knock(1.5, 62, 1.0), np.zeros(n - int(1.5 * SR))])
splash_big = np.concatenate([water_splash(2.0, 1.0), np.zeros(n - int(2.0 * SR))])
save("wave_crash_big", lowpass(knock * 0.8 + splash_big * 0.8 + roar * 0.9 + fizz, 6000), 0.75)

# 19. Alvo de madeira quebrando (2,2 s): estalos secos de tábua rachando + baque + lascas caindo
#     (madeira e água) + respingo.
n = int(2.2 * SR)
crack = hits(n, sorted(rng.uniform(0.0, 0.09, 6)),
             lambda i: highpass(white(int(0.05 * SR)), 1400) * env_ad(int(0.05 * SR), 0.001, 0.012) * rng.uniform(0.6, 1.0))
rupture = np.concatenate([wood_knock(1.0, 150, 0.2), np.zeros(n - SR)])
splinters = hits(n, sorted(rng.uniform(0.15, 1.3, 16)),
                 lambda i: wood_knock(0.18, rng.uniform(380, 1300), 0.0) * rng.uniform(0.15, 0.45))
plops = hits(n, sorted(rng.uniform(0.35, 1.6, 7)), lambda i: water_splash(0.4, 0.1) * rng.uniform(0.2, 0.5))
save("buoy_break", lowpass(crack * 1.2 + rupture * 0.9 + splinters + plops, 9000), 0.85)

# 20. Raio caindo muito perto (6 s): rasgo agudo e longo, estouro, e o ronco do trovão.
n = int(6 * SR)
t = t_axis(6)
rip = highpass(white(n), 1800) * np.interp(t, [0, 0.01, 0.25, 0.45], [0, 1, 0.6, 0]) * (0.5 + 0.5 * slow_noise(n, 60))
bang = lowpass(white(n), 900) * env_ad(n, 0.003, 0.12) * 1.4
rumble = lowpass(brown(n), 160 + 140 * slow_noise(n, 2.5)) * env_ad(n, 0.25, 1.8) * (0.55 + 0.45 * slow_noise(n, 4.0))
save("thunder_crack", rip * 0.7 + bang + rumble * 1.7, 0.95)
