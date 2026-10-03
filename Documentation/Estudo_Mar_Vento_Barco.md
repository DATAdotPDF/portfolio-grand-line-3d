# Estudo: mar, vento e barco (Sea of Thieves × Wind Waker → Grand Line)

Objetivo: ondas melhores, física mais gostosa e ideias de mundo — **só ideias e técnicas
públicas**, nada copiado (sem engenharia reversa de executáveis, sem assets extraídos).
Assets novos continuam vindo do Meshy.ai, feitos à mão por tentativa e erro.

## 1. O que as fontes dizem

### Sea of Thieves — "The Technical Art of Sea of Thieves" (Rare, SIGGRAPH 2018)

| Técnica | Como eles fazem | Dá no nosso projeto (Godot Compatibility / WebGL 2)? |
|---|---|---|
| Oceano | FFT de Tessendorf (2001) | FFT em tempo real não (sem compute shader no Compatibility). **Dá para "assar" um FFT periódico em textura** offline e amostrar no shader e na CPU (flutuação) — mesmo visual, custo baixo. |
| Cor da água | Mistura cor funda × cor de sub-superfície por ângulo de visão, direção do sol e uma **máscara de crista** tirada do deslocamento horizontal das ondas (crista = luz atravessa menos água) | **Sim, barato.** Nosso Gerstner já tem o deslocamento horizontal; a máscara sai dele. |
| Espuma | Nas cristas (método do Tessendorf: compressão/Jacobiano) **+ em volta de objetos que cortam a água** (comparação com o depth buffer), com **desfoque com realimentação** para a espuma se dispersar; misturada com texturas desenhadas por artista; mais espuma em mar tempestuoso | **Sim** (Jacobiano do Gerstner + espuma de interseção no casco/ilhas). A realimentação pede um buffer próprio — dá com SubViewport, custo médio. |
| Reflexo do sol | Especular de área para sol baixo grande (aproximação "closest point on sphere", Karis 2013) | **Sim, barato** — pôr do sol bonito na água. |
| Água rasa / respingos no convés | Simulação de superfície no GPU (Mei 2007) | Não vale o custo na web. |
| Nuvens | Geometria opaca renderizada à parte, reduzida a ¼, desfocada e composta na cena; nuvens distantes com borda "cartoon" (threshold); vento desloca e "embrulha" as nuvens em volta do jogador; zonas de alta/baixa pressão abrem/fecham o céu | **Em parte.** Vento empurrando e embrulhando as nuvens + borda cartoon ao longe: sim. |
| Cordas | Catenária analítica (CPU acha a curva, vertex shader deforma um tubo); folga configurável | **Sim** — cordame da chalupa reagindo ao balanço, barato. |
| Animação assada | Simulação no Houdini → textura de animação de vértices (Kraken) | Ideia para um bicho do mar no futuro. |

### Wind Waker — design (fontes públicas: wikis, comunidade de speedrun)

- **Vento é mecânica, não enfeite**: a vela só rende com vento a favor; o jogador **muda a direção do vento** (Wind's Requiem / batuta).
- **Mar em grade**: carta náutica dividida em quadrados, uma ilha por quadrado, mapa revelado aos poucos — dá sensação de descoberta.
- **Navio Fantasma**: só aparece **à noite**, numa ilha que depende da **fase da lua**; perto dele o céu fecha, troveja e entra uma música assombrada; só dá para entrar com a **carta certa**.

## 2. Onde estamos hoje

- Ondas: soma de Gerstner/trocoidais com grupos de onda, patch de alta resolução seguindo o barco, espelho na CPU (o barco boia na onda que se vê).
- Barco: **posto direto na superfície** (`max(centro, média do casco) + draft_offset`), balanço tirado da inclinação da onda. Estável e bonito, mas **sem peso**: não há inércia vertical, nem adernar com vento/curva, nem diferença de arrasto frente × lado.
- Vento: `WindManager` global move vela, velocidade, fitas de vento e direção do swell.

## 3. Habilidades a estudar (fontes)

1. **Ondas**
   - Tessendorf, *Simulating Ocean Water* (2001): espectro (Phillips/JONSWAP), FFT, *choppiness*, Jacobiano → espuma.
   - GPU Gems 1, cap. 1, *Effective Water Simulation from Physical Models* (Gerstner — o que já usamos): escolher amplitudes/direções **a partir de um espectro** em vez de à mão deixa o mar mais natural.
2. **Física de barco**
   - Flutuação por **vários pontos do casco** (proa, popa, bombordo, boreste) virando força + torque, com mola-amortecedor → o barco ganha **peso** e "assenta" na onda.
   - **Quilha**: arrasto pequeno para a frente, grande para o lado (o barco não derrapa).
   - **Leme** que só funciona com velocidade (curva mais aberta devagar, mais fechada rápido).
   - **Adernar**: inclinar com o vento na vela e na curva.
   - **Pontos de vela**: contra o vento quase parado, través (vento de lado) mais rápido, popa forte — e regulagem da vela.
3. **Visual**: cor de sub-superfície por máscara de crista, espuma por Jacobiano e por interseção, especular de área do sol, catenária para cordas.

## 4. Ideias de jogo (reformuladas, originais)

- **Vento controlável** (estilo Wind Waker, nosso): uma "rosa dos ventos" no HUD para escolher o vento; a vela e a velocidade respondem de verdade.
- **Navio Fantasma do portfólio**: aparece **à noite**, posição pela **fase da lua real do dia** (calculada pela data); céu fecha e muda a música; abordar revela um easter egg (lado Red Team/cyber do Pedro?).
- **Carta náutica com descoberta**: ilhotas secundárias (hobbies, certificados, bastidores) reveladas ao navegar.
- **Trocar de barco**: chalupa / outro casco feito no Meshy, cada um com física própria (rápido × estável).
- **Mais ilhas** — cuidado com o peso no celular (pacote leve tem 20 MB).

## 5. Próximo passo

Gravações de gameplay (Sea of Thieves e Wind Waker) → extrair quadros com ffmpeg e **medir**: período/altura das ondas, balanço do barco e atraso, aceleração com/sem vento, raio de curva, espuma/esteira. Com números, ajustamos o nosso mar/barco por comparação.

## Fontes
- Ang, Catling, Cifariello Ciardi, Kozin. *The Technical Art of Sea of Thieves*. SIGGRAPH 2018 Talks. https://history.siggraph.org/?p=84316
- Kozin. *Sea of Thieves: Tech Art and Shader Development*. GDC 2019. https://vimeo.com/326413164
- Tessendorf. *Simulating Ocean Water*. SIGGRAPH Course Notes, 2001.
- Fernando (ed.). *GPU Gems*, cap. 1 — Finch, *Effective Water Simulation from Physical Models*. NVIDIA, 2004.
- Wind Waker — Navio Fantasma e fases da lua: https://zelda-archive.fandom.com/wiki/Ghost_Ship_(The_Wind_Waker) · ciclo dia/noite: https://zeldaspeedruns.com/tww/general-knowledge/day-night-cycle
- Exploração dos mapas reais (estudo de construção de mundo, sem extrair nada): https://noclip.website
