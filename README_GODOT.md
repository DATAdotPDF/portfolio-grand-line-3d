# Portfólio náutico — protótipo Godot

Abra `project.godot` e pressione F5. A cena principal é `MainWorld.tscn`.

## Controles

- W/S: avançar e recuar, com aceleração e desaceleração.
- A/D: virar a chalupa.
- Shift + W: acelerar de 4,2 m/s até 12,5 m/s.
- Arrastar com botão direito: girar a câmera que acompanha o barco.
- Segure o botão esquerdo na água: mover a superfície. Arraste para deslocar a interação.
- M: pausar ou retomar a lista aleatória de músicas.
- Q/E: girar o canhão. R/F: elevar/abaixar. Espaço: disparar.
- Botões Ciclo, Dia e Noite: escolher a iluminação.
- L: habilitar/desabilitar a lamparina, que acende durante a noite local.

## Escala atual

Uma unidade corresponde a um metro. Oceano esférico com raio de 90 m. Chalupa com 4,8 m de comprimento. Ilhas com 20, 22, 22, 22 e 16 m de largura. Sobre fica próximo ao polo norte, Contato próximo ao polo sul, e as outras três ilhas ficam em latitudes próximas ao equador e longitudes separadas.

Os GLBs originais são preservados. A escala é calculada com as dimensões importadas, e cada ilha tem um ajuste de linha d'água. As duas imagens PNG de planeta são referências visuais, não mapas de textura.

## Organização

- `Scripts/main_world.gd`: monta a cena, posiciona os assets, liga câmera, iluminação, controles visuais e efeitos.
- `Scripts/sloop.gd`: navegação tangente à esfera, colisão e flutuação amortecida em quatro pontos.
- `Scripts/waves.gd`: parâmetros e fases de ondas, consultas da superfície, rastro e cliques.
- `Shaders/ocean_shared.gdshaderinc`: funções e parâmetros compartilhados entre água e spray.
- `Shaders/ocean.gdshader`: superfície, normais, espuma de crista e costa, rastro e perturbações do mouse.
- `Shaders/BowWaveSheet.gdshader`: duas folhas curvas presas à proa, com espuma correndo pelos UVs e desaparecimento gradual nas extremidades.
- `Shaders/radial_sky.gdshader`: céu orientado pela posição do barco no planeta.

A cena é construída ao iniciar. Durante a execução, a árvore **Remota** do editor mostra os nós gerados. As ilhas têm colisores sólidos de triângulos e áreas de aproximação separadas. Paredes verticais seguem a interseção dos modelos com o nível médio do oceano. Não existe mais a exclusão circular distante. O porto recebe a remoção da faixa de água incorporada em uma cópia da malha, identificada por altura e cor da textura. Os GLBs não são alterados. Não há simulação volumétrica de fluidos: as ondas são analíticas, e o casco usa uma resposta de flutuação controlada.

## Verificação

Execute com o binário Godot instalado:

```powershell
& 'D:\Godot\Godot.exe' --headless --path . --fixed-fps 60 --script Tests/revision_v3.gd
```

O teste cobre repouso, velocidade com Shift, permanência na superfície, formação e desaparecimento do rastro, interação por clique e arraste, bloqueio nas cinco ilhas por quatro direções, estabilidade no hemisfério oposto, fases das ondas, iluminação e música.

## Estado desta etapa

Base de navegação e água funcional, com capturas verificadas no renderizador D3D12. O efeito da proa combina folhas curvas, gotas com gravidade radial e rastro. É uma adaptação ao planeta, não uma reprodução idêntica de Seagazer.

A vela ainda faz parte da malha única da chalupa. O shader reage à direção do vento e recebe a Jolly Roger projetada pelo próprio material. Simulação de pano, atracação automática e conteúdo do currículo nas ilhas ainda precisam de uma etapa própria. Os GLBs originais somam centenas de MB; otimização para distribuição web ainda não foi feita.

Referências: https://jettelly.com/blog/making-seagazer-s-bow-spray-feel-like-part-of-the-ocean e https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html

## Ajustes de ambiente

`DayNightCycle.gd`, registrado em Autoload, mantém o relógio global. A duração inicial é 1.800 segundos. `DayNightCycle.set_time(valor, congelar)` permite receber um horário definido pela futura aplicação web. `night_at(posicao)` calcula a noite local em cada ilha. A fase avança durante o jogo, sem vínculo com o relógio do visitante.

Músicas em `Assets/Sound`, embaralhadas sem repetir dentro da rodada, a -18 dB. A tecla M pausa, e N ou o botão “Próxima música” pula para outra faixa. Os SFX ficam em `Assets/Sound/SFX`.

Confira `Documentation/REVISAO_APLICADA.md` para mudanças e limites. A espuma costeira usa profundidade dos objetos visíveis. Não calcula reflexão física das ondas no terreno.

## Revisão mais recente

Veja `Documentation/REVISAO_MAR_E_ILHAS.md` para o ciclo global, vento, céu, efeitos das cinco ilhas, isolamento do Poneglyph e limites. A revisão anterior fica registrada como histórico. Capturas e resultados dos testes estão em `Documentation`.


## Revisão 3

Confira `Documentation/REVISAO_V3.md`. Foram adicionados mar Gerstner radial/tangencial, placas com nomes por proximidade, canhão controlável, 21 alvos, pontuação, Dia/Noite/Ciclo, lista de músicas e animações de peças das ilhas. Os GLBs originais continuam preservados.

## Revisão 5

Confira `Documentation/REVISAO_V5.md`. O canhão agora usa carruagem e tubo separados, som de acerto em duas camadas e mira/recuo próprios. As placas mostram somente o nome de cada ilha. Os alvos costeiros ficam a 15, 20 e 25 m da costa. As ondas locais usam dispersão de águas profundas. O renderizador Compatibility foi testado. O preset `Web` usa WebGL 2 sem threads, mas a exportação depende dos modelos Web da mesma versão do Godot, ausentes nesta máquina.

Para repetir as verificações da revisão 5: `& 'D:\Godot\Godot.exe' --path . --rendering-method gl_compatibility --rendering-driver opengl3 --script res://Tests/v5_check.gd`. O resultado vai para `Documentation/v5_check.log`.

## Revisão 6

Confira `Documentation/REVISAO_V6.md`. As duas folhas da onda da proa são filhas da chalupa e usam duas alturas do mar por quadro, em vez de recalcular a superfície para cada vértice. Gotas raras saem da proa quando o barco supera 3 m/s. O canhão gira só no eixo vertical do tubo; a carruagem permanece parada. Os SFX fornecidos foram ligados ao tiro, impactos e ambiente. O teste atual é `Tests/v6_check.gd`.

## Revisão 7

Confira `Documentation/REVISAO_V7.md`. O globo e a água têm raio de 280 m. Cinco marcadores em `MainWorld.tscn` distribuem as ilhas sem alterar suas peças internas. O Log Pose no canto superior direito aponta para a ilha mais próxima e acompanha o giro do barco. A Jolly Roger na vela foi colocada na orientação correta. O teste atual é `Tests/v7_check.gd`.

## Revisão 8

Confira `Documentation/REVISAO_V8.md` para a configuração atual: globo de 200 m, cinco ilhas na rota pentagonal, 20 alvos, cinco novas placas 3D leves, fitas de vento com laço de 4 s e espuma costeira animada. O teste atual é `Tests/v8_check.gd`. As revisões anteriores documentam o histórico.
