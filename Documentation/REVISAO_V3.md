# Revisão 3 aplicada — 30/09/2026

Projeto: D:/Godot/Projects/portifolio-pedro-ferreira-3d-2026.

## Mudanças

- Esfera de leito a 86 m, água separada a 90 m e cinco ilhas independentes.
- Ondas Gerstner em 12 regiões sobrepostas com deslocamento radial e tangencial. Altura de barco, alvos e impactos usa inversão do mesmo campo. Normais seguem a superfície deformada.
- Máscara de espuma derivada dos 75 círculos do estudo Wind Waker enviado pelo usuário, com projeção triplanar. Espuma aparece nas cristas, costa, esteira e impactos.
- Barreira circular distante removida. Paredes na linha d'água do próprio modelo impedem o barco de subir nas ilhas. Dados da costa ficam em cache local, invalidado quando o arquivo ou ajuste de posição/escala muda.
- Canhão na chalupa: Q/E gira, R/F eleva, Espaço dispara. Projétil herda velocidade do barco, sofre gravidade radial, consulta o mar ondulado e usa detecção varrida de impacto.
- Três alvos por ilha e seis no oceano, 21 no total. Flutuação, giro de impacto, lascas, splash e contador de acertos. Um mesmo alvo não pontua repetidamente no mesmo impacto.
- Placas GLB + Label3D, com os cinco títulos pedidos, texto dimensionado para o pergaminho, flutuação e revelação a menos de 35 m da costa. Consulta de proximidade usa amostras da costa em células de 25 cm. A colisão mantém todos os segmentos.
- Botões Ciclo/Dia/Noite. Modos manuais acompanham o hemisfério do barco. Ciclo mantém o relógio global com duração de 1.800 s.
- Todas as músicas da pasta Sound entram em rodadas embaralhadas. M pausa/retoma.
- Luz do farol parte do eixo interno da lanterna, com feixe rotativo e brilho noturno. Den Den Mushi separado em cópia de malha e animado por proximidade.
- Dois canhões do forte separados, com recuo, fumaça e som procedural discreto. Ouro dos tesouros recebe resposta metálica e fagulhas. Poneglyph e lampiões mantêm animação e resposta dia/noite.

## Validação

80 verificações automatizadas passaram em `Tests/revision_v3.gd`, incluindo colisão nas cinco ilhas por quatro lados com Shift, flutuação, toque/arraste da água, ciclo, música, balística, acertos, alvos e animações. Registro: `v3_tests_final.log`.

Capturas D3D12 revisadas para as cinco ilhas, dia/noite, navegação e canhão. Medição a 1280x720, RTX 3060 Ti, limite de 75 FPS, três tomadas de 5 segundos após 3 segundos de aquecimento:

| Local | Quadro mediano | Quadro p95 | GPU mediana |
|---|---:|---:|---:|
| Sobre | 13,337 ms | 13,500 ms | 3,391 ms |
| Experiência | 13,328 ms | 15,502 ms | 3,733 ms |
| Contato à noite | 13,334 ms | 13,571 ms | 3,776 ms |

A medição automatizada usa janela iniciada oculta, barco parado e efeitos ativos. Não demonstra desempenho no navegador, em outros computadores ou durante toda a navegação. GPU medida pelo RenderingServer; os intervalos de quadro incluem o limitador. Dados em `v3_performance.json`.

## Limites

A água é uma superfície analítica animada, não um solver volumétrico. A espuma costeira usa profundidade visual e não simula reflexão das ondas pelas rochas. A geometria original é preservada, com separação de partes feita durante a montagem da cena. O carregamento inicial ainda monta modelos grandes, colisores e cópias de malhas. A versão web, compressão dos assets e telas do currículo continuam fora desta revisão.

## Referências

- https://en.wikipedia.org/wiki/Trochoidal_wave
- https://github.com/emilje/godot-water-shader (estudo; nenhum código copiado)
- https://jettelly.com/blog/making-seagazer-s-bow-spray-feel-like-part-of-the-ocean
- https://docs.godotengine.org/en/stable/classes/class_renderingserver.html
- Shader Wind Waker fornecido pelo usuário: https://www.shadertoy.com/view/3tKBDz
