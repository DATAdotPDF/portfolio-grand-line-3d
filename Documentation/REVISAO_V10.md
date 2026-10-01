# Revisão 10 — Fase 3 (escala, ondas, ilhas, vento, web)

## Fonte única de configuração

`Config/world_layout.tres` (classe `WorldLayout`) guarda raio do planeta, vento global, ondas, spawn e as cinco âncoras (`IslandAnchor`: `lat_deg`, `lon_deg`, `rotation_offset_deg`, `submersion`, `plate_clearance`). O nó raiz `MainWorld` expõe o mesmo recurso no Inspector. Mudar qualquer valor reposiciona ilhas, placas, chalupa, câmeras, esfera, leito e colisão no editor, sem Play.

- Raio atual: 800 m (livre; ondas escalam junto com `scale_waves_with_radius`).
- Ilhas: Sobre lat 90, Contato lat −90, Experiência/Formação/Projetos no equador (lon 0/120/240).
- `Scripts/WorldScale.gd`: matemática compartilhada (lat/lon → normal, base com Y radial sem degenerar nos polos, vento, componentes de onda).

## Ilhas

`IslandDistributor.gd` mede o AABB real de cada modelo em runtime/editor e coloca a base medida `submersion` metros abaixo do nível médio. As submersões vêm da medição do perfil da base (`Tests/measure_island_pedestals.gd`): o raio horizontal fica constante (parede do pedestal) até ~3,0 m em Experiência, ~3,75 m em Contato, ~2,3 m em Formação; Sobre e Projetos têm borda baixa/inclinada.

| Ilha | submersion |
| --- | ---: |
| Sobre | 1,2 m |
| Experiência | 3,0 m |
| Formação | 2,3 m |
| Projetos | 1,0 m |
| Contato | 3,6 m |

A placa fica `plate_clearance` (3,5 m) acima do topo medido. A câmera de visita usa `frame_island(chão da ilha, teto da placa, largura)` com fator 1,6 e ajuste pelo FOV/aspecto (funciona em tela em pé).

## Oceano

- `Shaders/ocean_waves.gdshaderinc`: Gerstner com deslocamento tangente, cinco componentes derivadas do eixo do vento. Fase = `k · dot(p, d)` em espaço de mundo; cada componente some suavemente onde `d` fica paralelo à normal (evita os anéis concêntricos do "bola de golfe"). Esses dois pontos calmos formam o "Calm Belt", longe das ilhas.
- `ocean.gdshader`: esfera NUNCA deformada; ondas só em normal/cor no fragment.
- `ocean_patch.gdshader` + `Scripts/OceanPatch.gd`: grade de 240 m de raio que acompanha a chalupa (também no editor) e desloca vértices de verdade; o deslocamento zera antes da borda, onde a esfera é descartada.
- `SphericalOceanSimulation.gd`: espelho exato em CPU (mesma fonte de parâmetros), com inversão do deslocamento horizontal para a altura sob o barco.
- Toon: bandas suaves de altura, linha de crista suave, espuma só na costa (profundidade) e na esteira (duas linhas que se abrem). Mouse: pacotes de onda circulares amortecidos, rastro contínuo ao arrastar.
- Cores calibradas para Compatibility (sem HDR); especular GGX para o brilho vítreo.

## Vento

`WindManager` (autoload) com rajadas; eixo vindo do layout. Vela, física da chalupa (72–100% conforme ângulo, × intensidade local), fitas de vento e ondas usam o mesmo campo.

## Web / mobile

- Renderer do projeto: `gl_compatibility` (o export Web do Godot 4.7 é WebGL 2).
- Controles de toque (`TouchControls.gd`), UI em retrato, HUD que quebra linha.
- Cópias otimizadas em `Assets/Optimized/` (originais intactos): ilhas ~60 mil triângulos, texturas Basis Universal (base 2048 nas ilhas/chalupa, normal ≤1024, metallic-roughness 512).
- Música fora do `.pck` na web: tocada por `<audio>` a partir de `music/` (manifesto `Config/music_playlist.json`). A faixa da trilha de Wind Waker fica fora da web por direitos autorais.
- Build atual: `index.pck` 69,9 MB, `index.wasm` 37,7 MB (8,8 MB com brotli).

## Verificação

- `Tests/v10_preview.gd` gera capturas em `Documentation/Previews/v10_*.png` (barco, lateral, ondulações, cinco ilhas, globo, mobile).
- Execução headless e no navegador (WebGL 2) sem erros de script; `WORLD_READY radius=800`.
