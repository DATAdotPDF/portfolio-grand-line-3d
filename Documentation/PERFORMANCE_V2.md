# Medição exploratória de desempenho

Godot 4.7.2, D3D12, RTX 3060 Ti. Janela solicitada: 1280 × 720. VSync desativado apenas durante a medição. Aquecimento de 4 segundos, amostra de 10 segundos, barco parado no polo de referência. Medição feita em execução iniciada com janela oculta.

| Medida | Versão anterior | Versão revisada |
|---|---:|---:|
| Mediana entre callbacks de fim de desenho | 1,855 ms | 0,659 ms |
| Percentil 95 | 2,186 ms | 0,774 ms |
| Percentil 99 | 2,436 ms | 0,901 ms |
| Primitivas reportadas | 4.157.404 | 747.555 |
| Chamadas de desenho reportadas | 14 | 14 |

Os tempos são cadência dos callbacks do Godot. Não são uma medida isolada do tempo da GPU nem uma promessa de FPS apresentados na tela. As ilhas mudaram de posição e a carga visível também mudou. A comparação inclui as alterações de cena e não separa o ganho de cada ajuste.

Essa medição não reproduziu o relato de FPS baixo durante navegação interativa. O contador na tela permite conferir o comportamento na janela de jogo. Os testes funcionais cobrem movimento e colisão, mas não substituem uma captura longa do engasgo na configuração usada pelo visitante.

Foram reduzidas a malha do oceano, as operações repetidas por pixel e a complexidade visível das malhas alteradas por meio de níveis de detalhe. Câmera e ondas passaram a usar interpolação entre passos da física.
