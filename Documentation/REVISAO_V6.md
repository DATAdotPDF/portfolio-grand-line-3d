# Revisão 6 — proa, canhão e som

## Proa

- `Scripts/main_world.gd` cria `BowWave_Left`, `BowWave_Right` e `WaterDroplets` sob `PlayerSloop/FloatVisual`.
- Cada folha usa uma grade de 64 × 16 vértices. `Shaders/BowWaveSheet.gdshader` curva a crista para cima e para fora. A espuma corre pelos UVs e a transparência apaga o início e o fim. Em repouso as folhas desaparecem.
- O script consulta a altura da água na frente e atrás da folha uma vez por quadro. O shader interpola essas alturas entre os vértices. Assim a folha acompanha o mar sem repetir a consulta completa para cada vértice.
- `WaterDroplets` usa 12 partículas de 0,4 s e só emite acima de 3 m/s. A antiga emissão frequente de esferas por código durante a navegação foi removida. Os efeitos de impacto de bala continuam separados.

## Canhão

- `Scripts/DeckCannon.gd` mantém `rotation.y = 0`. A carruagem não gira nem recua. A orientação fixa para bombordo fica dentro do `PitchPivot`.
- R/F ajustam somente a elevação do tubo entre -3° e 30°. Q/E não controlam mais o canhão. O tiro preserva o pavio, a fumaça, o recuo do tubo e a velocidade herdada do navio.

## Áudio

- Pavio: `FUSE SFX.wav`. Disparo: `CANNON SHOT SFX.wav`. Bala em voo: `CANON BALL DOPPLER SFX.wav`. Impacto na placa: `WOOD IMPACT CANON BALL SFX.wav`, com o sino de confirmação da interface. Colisão sólida: `EXPLOSION SFX.wav`. Água: `WATER SPLASH CANON BALL SFX.wav`.
- `Scripts/SeaAmbience.gd` mantém `OCEAN AND SEAGULLS SFX.mp3` em volume baixo, posiciona `SEAGULLS OPEN SEA SFX 1.mp3` ao redor do barco, toca `WOODEN BOAT OPEN SEA SFX.mp3` quando ele se move e dispara `OCEAN WAVE CRASH SFX.mp3` na proa quando há velocidade e crista local.
- As 25 músicas em `Assets/Sound` entram numa lista embaralhada sem repetição até esvaziar. M pausa. N e o botão “Próxima música” pulam a faixa; o pulo mantém o estado de pausa.

## Verificação

- `Tests/v6_check.gd` passou em 51 verificações no Godot 4.7.2, OpenGL Compatibility. O log está em `Documentation/v6_check.log`.
- As capturas `Documentation/Previews/v6_bow_wave_port.png` e `v6_deck_top.png` mostram a folha em movimento e a carruagem no convés.
- A folha é um efeito visual deformado por shader. Não há dinâmica de fluido ou colisão individual da folha com o casco.
