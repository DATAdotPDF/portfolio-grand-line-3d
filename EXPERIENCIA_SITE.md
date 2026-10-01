# Experiência do portfólio náutico

Referências: [Nazaré José](https://nazarejose.vercel.app) para a abertura centrada no autor e a passagem para o mundo 3D. [Melon Jelly Knife](https://claude.ai/artifact/RiTbBMEqgfNwgMHMTAhf5P) para a hierarquia limpa, controles legíveis e resposta imediata a cada ação. O texto, os modelos e a direção de arte deste projeto são próprios.

## Abertura

A primeira tela mostra o nome Pedro Ferreira, uma frase curta sobre o portfólio e uma prévia do oceano com a chalupa. Há três ações visíveis: Navegar livre, Explorar ilhas e Time Attack. Nenhum movimento do barco começa antes da escolha. A cena 3D continua visível atrás da interface. Em telas pequenas, os botões ficam em uma coluna.

## Navegar livre

A câmera segue a chalupa a 12 m de distância e 5 m de altura, com FOV de 65°. A bússola aponta para a ilha mais próxima pela distância sobre a esfera. O rótulo mostra o nome dessa ilha. Aproximar-se de uma ilha revela sua placa 3D. O jogador pode arrastar a água com o botão esquerdo para criar ondas.

## Explorar ilhas

O menu lista Sobre, Experiência, Formação, Projetos e Contato. As teclas 1 a 5 fazem a mesma seleção. A câmera voa até a ilha, mantém sua base e seu topo no enquadramento e orbita devagar em 360°. Apenas a placa da ilha selecionada aparece. A placa flutua acima do ponto mais alto do modelo e conserva a face legível. A tecla 0 ou Esc devolve a câmera ao barco.

| Ilha | Foco radial | Distância de órbita | Elevação da câmera |
| --- | ---: | ---: | ---: |
| Sobre | 6 m | 38 m | 10° |
| Experiência | 9 m | 44 m | 12° |
| Formação | 7,5 m | 40 m | 10° |
| Projetos | 8 m | 42 m | 12° |
| Contato | 24 m | 68 m | 16° |

Os valores são os perfis atuais de `PortfolioCameraController.gd`. A validação visual de cada enquadramento ainda precisa ser feita no editor 3D e na vista da chalupa. A placa Contato exige mais altura por causa do farol.

As cinco placas têm nós `IslandTitleSign` em `MainWorld.tscn`. Suas alturas iniciais podem ser ajustadas pelo gizmo no editor 3D. O jogo conserva a posição gravada na cena.

## Time Attack

O objetivo é acertar com o canhão as 20 boias em 180 segundos. Cada boia tem um ID estável de `buoy_00` a `buoy_19` e conta uma única vez na partida. Boias acertadas não reaparecem enquanto esse modo estiver aberto. A tela mostra tempo restante, acertos e total. Acertar todas encerra a partida; zerar o tempo também. O botão Navegar livre sai do modo e restaura as boias.

`NavalGame.gd` emite `time_attack_finished(completed, hits, total, seconds_used, hit_events)`. Cada evento contém `target_id` e `at_seconds`. O jogo local ainda não envia esses dados ao site.

No site, o placar permanente deve ficar em um banco de dados no servidor. Uma partida começa com um ID emitido pelo servidor. O envio do resultado inclui esse ID e os eventos. O servidor confere prazo de 180 segundos, IDs únicos, ordem dos tempos e conclusão das 20 boias antes de registrar um tempo. O ranking principal ordena partidas completas pelo menor tempo. Nome de exibição e resultado só aparecem após o envio ser aceito. Um placar guardado apenas no navegador não atende ao requisito de permanência.

## Controles mostrados na interface

| Ação | Controle |
| --- | --- |
| Acelerar e frear | W e S |
| Virar a chalupa | A e D |
| Impulso | Shift |
| Girar o canhão | Q e E |
| Inclinar o canhão | R e F |
| Atirar | Espaço |
| Manipular a água | Arrastar com botão esquerdo |
| Girar a câmera | Arrastar com botão direito |
| Visitar ilhas | 1 a 5 ou menu |
| Voltar ao barco | 0 ou Esc |
| Ver o planeta | Tab |

Os controles devem aparecer na abertura em um painel curto e permanecer acessíveis por um botão de ajuda. No modo de visita, o painel dá destaque à ilha e ao atalho de volta. No Time Attack, dá destaque ao cronômetro, às boias restantes e ao canhão. Áudio e ciclo do dia ficam em um grupo discreto, separado dos comandos principais.

## Limite desta fase

O Godot já contém a câmera por ilha, o Log Pose, o canhão, a água interativa e a lógica local do desafio. A abertura do site, a adaptação para toque e o serviço do placar ainda dependem da camada web. O arquivo `Export/world_config.json` é uma exportação antiga; suas posições e sua câmera não representam a cena atual. Ele não deve ser usado como fonte da migração antes de ser regenerado.
