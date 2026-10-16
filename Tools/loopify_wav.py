# Blender python: crossfade the tail of a WAV into its head so it loops without a click.
# blender -b --factory-startup -P loopify.py -- in.wav out.wav cross_seconds
import sys, wave
import numpy as np
a = sys.argv[sys.argv.index("--") + 1:]
src, dst, cross = a[0], a[1], float(a[2])
w = wave.open(src)
sr, ch, n = w.getframerate(), w.getnchannels(), w.getnframes()
x = np.frombuffer(w.readframes(n), np.int16).astype(np.float64).reshape(-1, ch)
m = int(cross * sr)
fade = np.linspace(0.0, 1.0, m)[:, None]
# Equal-power crossfade.
head = x[:m] * np.sin(fade * np.pi / 2) + x[-m:] * np.cos(fade * np.pi / 2)
y = np.concatenate([head, x[m:-m]])
with wave.open(dst, "wb") as o:
    o.setnchannels(ch); o.setsampwidth(2); o.setframerate(sr)
    o.writeframes(np.clip(y, -32768, 32767).astype(np.int16).tobytes())
print("LOOP", dst, "%.2fs" % (len(y) / sr))
