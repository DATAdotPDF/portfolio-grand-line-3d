# Plano: análise de gameplay (Wind Waker HD · Sea of Thieves)

Estudo **por observação**: o Pedro grava, eu meço os vídeos. Nada de abrir executáveis,
ISO ou arquivos dos jogos. Os vídeos ficam em `References/Gameplay/` (pasta fora do Git).

## Como gravar (vale para os dois)

- **1080p, 60 fps** se der (30 fps serve). OBS ou a gravação do próprio sistema.
- **Câmera parada** sempre que possível (sem girar enquanto mede algo) — é o que permite medir.
- HUD pode ficar; se o jogo deixar esconder, melhor em alguns trechos.
- Fale em voz alta ou anote o minuto de cada trecho (ou só siga a ordem abaixo).

## Roteiro — Wind Waker HD, Great Sea (~15 min)

| Min | Trecho | O que eu meço |
|---|---|---|
| 0–2 | Barco **parado**, vela baixa, câmera de lado e depois de trás | ritmo e altura das ondas, balanço do barco parado |
| 2–4 | **Vento a favor**, vela cheia, reta longa | aceleração, velocidade final, proa batendo na onda, esteira e espuma |
| 4–5 | **Contra o vento** e **vento de lado** | quanto a vela perde, se o barco aderna |
| 5–6 | **Curvas fechadas** para os dois lados | raio de curva, inclinação, rastro na água |
| 6–7 | Mudar o vento com a **batuta** | como o jogo mostra o vento (setas, nuvens, fitas, som) |
| 7–9 | Chegar numa **ilha** devagar | transição mar→praia, espuma na costa, escala da ilha vista do mar |
| 9–11 | **Tempestade / mar bravo** (se aparecer) e **noite** | cor da água, espuma, raios, ondas maiores |
| 11–13 | Abrir a **carta náutica**, quadrados, ilhas | como o mundo é organizado e revelado |
| 13–15 | Livre: canhão, gancho, peixe-homem, Navio Fantasma se der | ideias de interação |

## Roteiro — Sea of Thieves (~15 min, de preferência Safer Seas)

| Min | Trecho | O que eu meço |
|---|---|---|
| 0–2 | Navio **ancorado**, câmera em 3ª pessoa no convés olhando o mar | ondas (ritmo, altura, choppiness), cor funda × crista |
| 2–4 | **Vela cheia, vento a favor**, reta | aceleração, peso do navio, mergulho da proa, spray |
| 4–6 | **Ajustar a vela** em relação ao vento (de lado, contra) | pontos de vela: quanto rende em cada ângulo |
| 6–7 | **Curvas** com o leme todo | raio, adernar, atraso de resposta do leme |
| 7–9 | **Nadar**/ficar na água e olhar o navio | espuma em volta do casco, água vista de perto, transparência |
| 9–11 | Chegar numa **ilha/praia** | espuma na costa, água rasa (cor), ondas quebrando |
| 11–13 | **Pôr do sol / noite** | reflexo do sol baixo, cor da água à noite |
| 13–15 | **Tempestade** se der; nuvens; olhar para o horizonte | espuma no mar bravo, céu, neblina |

## O que eu faço com os vídeos

1. **Mapa do vídeo**: detecção de cenas (ffmpeg) + folhas de contato (1 quadro a cada N s) para achar cada trecho.
2. **Medições** (nos trechos de câmera parada):
   - **ondas**: período (tempo entre cristas passando num ponto fixo), altura relativa ao barco/mastro, quantas ondas por "grupo";
   - **barco**: ângulo de balanço/adernar (pelo mastro), atraso entre onda e barco, aceleração e velocidade (por marcas na água), raio de curva;
   - **cor**: paleta da água funda, da crista, da espuma, por hora do dia (amostragem de pixels);
   - **espuma/esteira**: onde aparece, quanto dura, forma.
3. **Comparação** com o Grand Line nos mesmos termos (gravamos o nosso jogo com o mesmo enquadramento, via Movie Maker).
4. **Relatório** `Documentation/Analise_Gameplay.md`: o que cada jogo faz, números, e uma **lista priorizada** do que implementar (custo × impacto, sempre pensando no celular).

## Ferramentas

- ffmpeg (já temos) para quadros, cenas e folhas de contato.
- `D:\Tools\universal-modder` clonado para outros casos (não usado aqui: ele é para *modificar* jogos de PC, e Sea of Thieves é online com anti-cheat).
