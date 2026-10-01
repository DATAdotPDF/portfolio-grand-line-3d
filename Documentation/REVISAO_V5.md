# Revisão 5 — canhão modular, vento e caminho web

Projeto: `D:\Godot\Projects\portifolio-pedro-ferreira-3d-2026`

## Cena

- `Scenes/DeckCannon.tscn` instancia a carruagem e o tubo a partir dos dois GLBs novos. O tubo gira pelo `PitchPivot` e recua pelo `RecoilPivot`. A base fica no lado oposto do convés, a `Y=0,204` local. O canhão mantém o pavio de 1,25 s, som de disparo, fumaça e velocidade herdada da chalupa.
- `HitSoundManager` em Autoload toca impacto de madeira na posição do alvo e um sino de confirmação na interface, com pitch entre 0,95 e 1,05. Os dois WAV foram gerados para o protótipo. Eles não são os áudios da referência de vídeo.
- Cada ilha tem 3 alvos, a aproximadamente 15, 20 e 25 m da costa medida. Há 6 alvos no alto-mar escolhidos de uma amostra Fibonacci por maior afastamento entre alvos e ilhas. Acertos ocultam colisão e malha, somam ponto e reaparecem após 20 s.
- As placas mostram `SOBRE`, `EXPERIÊNCIA`, `FORMAÇÃO`, `PROJETOS` e `CONTATO` em dourado com contorno preto. A posição continua presa à placa e a aparição depende da proximidade.
- A imagem `Assets/JollyRoger.jpeg` continha dados PNG. A cópia `Assets/JollyRoger.png` corrige a importação sem alterar o original. O shader projeta a arte na vela branca, pois `Decal` não funciona no renderizador Compatibility. A vela reage ao vento tangente local e à velocidade da chalupa. Trilhas de vento usam RibbonTrailMesh no Forward+ e quads no Compatibility.
- `Scripts/waves.gd` e `Shaders/ocean_shared.gdshaderinc` compartilham as mesmas 12 ondas locais, sem origem nos polos. A velocidade angular usa `sqrt(9,8 k)` para cada componente. O shader usa curvatura analítica aproximada das componentes para modular a espuma. A espuma da costa tem um anel aproximado e usa profundidade da cena somente no Forward+. O anel não representa a silhueta exata da costa.

## Verificação

- Godot 4.7.2, D3D12 Forward+: cena abriu sem erros após as alterações.
- Godot 4.7.2, OpenGL Compatibility: `Tests/v5_check.gd` passou 26 verificações, com `FAILURES=0`. Log em `Documentation/v5_check.log`. Capturas em `Documentation/Previews/v5_cannon.png`, `v5_deck_top.png` e `v5_cannon_elevated.png`.
- `export_presets.cfg` adiciona `Web` sem threads. A tentativa de exportação retornou código 1: faltam `web_nothreads_debug.zip` e `web_nothreads_release.zip` em `C:\Users\pedut\AppData\Roaming\Godot\export_templates\4.7.2.stable`. O projeto ainda não foi testado em navegador nem publicado como WebGL.

## Limites

- A água usa um campo analítico de ondas e perturbações. Não é uma simulação volumétrica de fluidos nem uma solução exata das equações de Euler para a soma de ondas. Os dois shaders recebidos usam fase `dot(posição_radial, tangente_local)`, que zera geometricamente; a cena conserva direções de ondas fixas por região.
- A projeção da Jolly Roger é por coordenadas do mesh original. Ajustes finos da arte e dos limites da lona ainda dependem da malha do GLB.
- Tamanho dos modelos, memória do navegador, áudio, controles e FPS da versão exportada ainda exigem teste após instalar os modelos de exportação.
