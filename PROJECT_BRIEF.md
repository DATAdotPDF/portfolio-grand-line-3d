# PROJECT_BRIEF.md — Portfólio 3D Náutico Interativo (Pedro Ferreira)

Pasta do projeto (fonte da verdade, acesso total liberado): 
D:\Godot\Projects\portifolio-pedro-ferreira-3d-2026
Engine: Godot 4 / WebGPU
Agente responsável a partir de agora: Claude (Opus via MCP, com acesso a esta pasta)
Agente anterior: Codex (via MCP) — este documento substitui o conhecimento que
estava apenas na cabeça do usuário e do Codex; leia-o como a memória do projeto.

===============================================================================
## PRODUTO FINAL — O QUE ESTAMOS CONSTRUINDO, EM UMA FRASE
===============================================================================
Um portfólio profissional de cibersegurança/engenharia de dados, disfarçado de
jogo 3D náutico navegável: o visitante controla uma chalupa pirata navegando
sobre um OCEANO ESFÉRICO VASTO com ondas grandes e realistas estilo Seagazer,
vento global estilo Wind Waker, e encontra 5 ilhas temáticas espalhadas pelo
globo — cada uma correspondendo a uma seção do currículo (Sobre, Experiência,
Formação, Projetos, Contato) — antes de ser publicado no domínio já ativo
portfolio-data-cybersecurity.data-pedutraferreira.workers.dev.

Não é uma demo técnica de shader nem um showcase de assets isolados: é um
PRODUTO NAVEGÁVEL, fim a fim, que precisa funcionar como experiência completa
— do momento em que o visitante entra na água até o momento em que lê o
conteúdo profissional do usuário dentro da ilha "Contato".

===============================================================================
## INSPIRAÇÕES VISUAIS E DE JOGABILIDADE (referências de tom, não de escopo)
===============================================================================
- **One Piece**: estética pirata geral, conceito de "Grand Line" com ilhas
  temáticas espalhadas por um oceano vasto, Log Pose como bússola/compasso
  modular, Poneglyphs, Den Den Mushi (caracol-telefone) como motivo visual.
- **The Legend of Zelda: The Wind Waker**: vento que é um sistema de jogo
  real (não cosmético) afetando a vela do barco e o mundo inteiro; navegação
  em oceano aberto; estética toon.
- **Seagazer** (referência técnica principal para a água):
  jettelly.com/blog/making-seagazer-s-bow-spray-feel-like-part-of-the-ocean
  — água calma, vítrea, reflexiva, toon; esteira de proa (bow spray) feita de
  malhas de grade 64×24 por lado, curvadas no vertex shader, formando folhas
  de água que se enrolam; gotículas via partículas. IMPORTANTE: Seagazer usa
  um MAPA PLANO, não uma esfera — nosso projeto escolheu esfera (conceito de
  globo navegável tipo "Grand Line"), o que é tecnicamente mais difícil para
  as ondas, e isso precisa ser levado em conta em toda decisão técnica sobre
  água (ver seção de Oceano abaixo).

===============================================================================
## TUDO JÁ FOI CRIADO — NÃO GERE NOVOS ASSETS 3D
===============================================================================
Todos os assets abaixo já existem dentro desta pasta do projeto (geometria e
textura já produzidas e aprovadas pelo usuário em outra ferramenta). Localize-
os na pasta antes de assumir que algo falta. NÃO crie, substitua ou regenere
nenhum asset 3D sob nenhuma circunstância — se algo parecer ausente ou com
nome diferente do listado aqui, isso é uma PERGUNTA para a Fase 2 (ver
processo obrigatório abaixo), nunca uma geração automática.

Lista de assets existentes:
- Chalupa pirata ("pirata-sloop"): casco, quilha naval, leme — com histórico
  de correção estrutural (ver seção de histórico de erros). Existe também uma
  variante com vela branca lisa/limpa (sem Jolly Roger), pensada para receber
  a textura/decal da Jolly Roger diretamente dentro do Godot (troca de albedo),
  em vez de reger o modelo.
- Canhão: cano (com munhões para o pitch) e carro/base (com berços em U para
  os munhões) como DOIS assets separados de propósito, para permitir que o
  cano rotacione no eixo de pitch sem o carro inteiro girar junto.
- Bola de canhão (cannonball).
- Alvo naval flutuante (buoy) para teste de disparo.
- Planeta/terreno esférico: esfera com platôs rebaixados (recessos) já
  pré-esculpidos especificamente para encaixar as 5 ilhas — estes pontos de
  recesso são a referência de ancoragem geométrica real, não coordenadas
  inventadas.
- 5 ilhas, cada uma como asset independente (para permitir animação de partes
  específicas no futuro): 
  1. Ilha "Sobre" — harbor/pier (píer, estacas).
  2. Ilha "Experiência".
  3. Ilha "Formação".
  4. Ilha "Projetos".
  5. Ilha "Contato" — farol + motivo Den Den Mushi.
- Log Pose (bússola modular): base, agulha, cúpula de vidro — como peças
  separadas.
- 5 placas de título 3D esculpidas, uma por ilha (Sobre / Experiência /
  Formação / Projetos / Contato) — destinadas a flutuar acima de cada ilha
  com o nome da seção.

===============================================================================
## PRIORIDADE TÉCNICA #1 — ESCALA DO MUNDO (resolve a causa-raiz de várias falhas)
===============================================================================
O planeta/esfera do oceano atual está PEQUENO DEMAIS. Isso é a causa-raiz por
trás de boa parte do histórico de falhas de shader listado abaixo, e precisa
ser corrigido ANTES de refinar qualquer outro detalhe visual:

- Em Seagazer, a sensação de "montanhas de água" grandes e agradáveis de ver
  passar só existe em escala grande. Quanto MENOR a circunferência do nosso
  globo, PIOR a ilusão de oceano vasto e pior o comportamento das ondas
  Trochoidal/Gerstner, que em escala pequena tendem a parecer grade, bandas
  de latitude/longitude, ou ruído repetitivo, em vez de swells naturais.
- Seagazer resolve isso fácil porque usa mapa PLANO. Nós optamos por ESFERA
  (conceito de globo navegável "Grand Line"), que é mais difícil: as ondas
  Gerstner precisam ser calculadas em espaço de mundo com eixos de direção de
  vento consistentes sobre TODA a superfície esférica — nunca com UV polar
  (atan/asin), que já causou bandas de meridiano/latitude no passado.
- AÇÃO REQUERIDA: aumentar significativamente o raio da esfera do planeta/
  oceano, recalibrar a subdivisão da malha (segmentos radiais/anéis) e
  recalibrar amplitude/densidade/crest_sharpness das ondas proporcionalmente
  à nova escala — mantendo o barco com bastante espaço livre para circular,
  como já era a intenção original.
- As 5 ilhas devem continuar distribuídas em pontos diferentes do globo —
  cada uma em um "canto" distinto do planeta, não agrupadas — isso já estava
  correto na escala anterior e deve ser preservado ao reescalar.

===============================================================================
## OCEANO — ESPECIFICAÇÃO TÉCNICA E HISTÓRICO DE FALHAS (NÃO REPETIR NENHUMA)
===============================================================================
Tecnologia escolhida: Trochoidal wave / Gerstner wave — solução exata de
fluido ideal incompressível para ondas de superfície (ver Wikipedia:
"Trochoidal wave" para a formulação matemática de referência).

Comportamento visual desejado: água calma, vítrea, reflexiva, estilo toon,
igual à referência Seagazer — incluindo esteira de proa (bow spray) e
perturbação/ondulação de esteira (wake) ao redor do barco em movimento.

### Histórico de falhas já diagnosticadas e corrigidas — NÃO REINTRODUZIR:
1. **"Piscando branco/azul"**: causado por subdivisão de esfera baixa demais
   combinada com textura de espuma vazia. Corrigido aumentando o SphereMesh
   para 256 segmentos radiais / 128 anéis.
2. **Bandas de meridiano/latitude**: causadas por matemática polar de UV
   (atan/asin) e projeção angular geodésica. Corrigido substituindo por
   desacoplamento de coordenadas em espaço de mundo.
3. **Espuma em padrão "polka dot"**: causada por limiar binário (step()).
   Corrigido com gradiente smoothstep, aplicado apenas em linha de costa e
   esteira do barco, nunca espalhado pela superfície inteira.
4. **"Água fervendo" / efeito casca-de-laranja**: causado por ruído
   procedural calculado no VÉRTICE, corrompendo as normais por vértice.
   Corrigido movendo todo o cálculo de onda para o fragment shader, com
   matemática contínua em espaço de mundo — normais não são mais perturbadas
   em vertex().
5. **"Bola de gelatina"**: deslocamento de vértice distorcendo a silhueta da
   esfera (visível de longe, na escala planetária). Corrigido usando esfera
   NÃO deformada geometricamente + perturbação de normal apenas no fragment
   shader.
6. **"Bola de boliche" / recorrência de polka dot**: causada por interferência
   de produto sin(x)*cos(y) em 3D, criando picos circulares concentrados.
   Corrigido substituindo por bandas de swell DIRECIONAIS e lineares (produto
   escalar — dot product — ao longo de eixos alinhados ao vento), em vez de
   multiplicação de funções de ruído.
7. **"Bola de plástico lisa"**: ondas ficavam invisíveis em escala planetária
   (400m) porque a amplitude era pequena demais para ser percebida de longe.
   Corrigido recalibrando wave_density e crest_sharpness, e reforçando o
   render de crista estilo toon (bandas smoothstep) para ficar visível em
   escala grande. ATENÇÃO: este ajuste muda de novo com o aumento de escala
   da Prioridade #1 acima — a amplitude/densidade precisa ser recalibrada
   outra vez para o novo raio do planeta.
8. **"Grade waffle / favo de mel"**: causado por soma cartesiana ortogonal
   sin(x)+sin(z) sem projeção geodésica/tangencial, criando uma grade
   quadrada regular de solavancos. Corrigido com coordenada de streaming
   contínua orientada ao eixo do vento (dot(world_pos, wind_dir)), gerando
   linhas de swell lineares e não-repetitivas em grade. STATUS: correção
   aplicada mas AINDA NÃO CONFIRMADA visualmente pelo usuário no editor —
   reavaliar obrigatoriamente depois de aplicar o aumento de escala da
   Prioridade #1, pois o comportamento pode mudar com o novo raio.
9. **Interação com mouse na água**: atualmente funcional mas pouco natural/
   divertida — a perturbação de ondas ao clicar/arrastar o mouse precisa ficar
   mais orgânica e agradável de usar, menos "mecânica".

### Regra geral extraída deste histórico (aplicar sempre):
Qualquer matemática de onda deve ser: (a) calculada em espaço de mundo, nunca
em UV polar da esfera; (b) calculada no fragment shader, nunca deformando
vértices nem perturbando normais no vertex shader, para não distorcer a
silhueta planetária vista de longe; (c) baseada em direção(ões) de vento como
vetores contínuos (dot product), nunca em somas cartesianas ortogonais puras
nem em produtos multiplicativos de funções periódicas (ambos geram padrões
de grade ou de pontos repetidos).

===============================================================================
## VENTO GLOBAL (estilo Wind Waker)
===============================================================================
O vento deve ser um sistema que afeta O MUNDO INTEIRO durante todo o tempo de
jogo — não apenas a vela do barco em momentos pontuais, como estava antes.

Requisitos:
- Um `WindManager` (ou equivalente) global, definindo uma direção e
  intensidade de vento compartilhada por toda a cena, não local ao barco.
- Afeta a física da vela do barco (reação real à direção do vento, não
  animação cosmética fixa).
- Idealmente alimenta partículas visuais de vento no ambiente (GPUParticles3D
  — estrias/rastros de vento visíveis sobre a água ou no ar).
- A MESMA direção de vento deve alimentar a orientação das bandas de swell do
  oceano (ver item 6/8 do histórico de falhas acima), para que vento, água e
  vela fiquem visualmente coerentes entre si — um visitante deve conseguir
  "ler" a direção do vento olhando tanto para a vela quanto para as ondas.

===============================================================================
## POSICIONAMENTO E ORIENTAÇÃO DAS 5 ILHAS NO PLANETA
===============================================================================
### Problema atual (ainda não resolvido, evidenciado em screenshot recente)
As ilhas não estão sendo posicionadas corretamente sobre a esfera: algumas
aparecem inclinadas ou parcialmente enterradas na água, cortando a superfície
da esfera em ângulo reto, em vez de assentar naturalmente na curvatura do
planeta.

### Causa raiz diagnosticada (dupla — as duas precisam ser corrigidas juntas)
1. **Falta de alinhamento rotacional**: o eixo "para cima" local de cada ilha
   precisa coincidir com a NORMAL RADIAL da esfera naquele ponto específico
   da superfície — não pode usar um eixo Y global fixo, porque isso só
   funciona no "polo" da esfera e falha em qualquer outro ponto.
2. **Pivô do mesh incorreto**: o pivô de cada mesh de ilha está, aparentemente,
   no centro do AABB (bounding box) em vez de na base real da ilha. Como as 5
   ilhas têm alturas totais muito diferentes entre si (o farol da ilha
   "Contato" é alto; o píer da ilha "Sobre" é baixo), usar o centro do AABB
   como referência de "chão" faz algumas ilhas afundarem na água e outras
   flutuarem acima dela, de forma inconsistente.

### Solução obrigatória: MEDIR, nunca estimar
Para cada um dos 10 assets envolvidos (as 5 ilhas E as 5 placas de título),
rodar dentro do próprio Godot:
```gdscript
var aabb: AABB = mesh_instance.get_aabb()
var floor_offset = aabb.position.y                   # ponto mais baixo real
var ceiling_offset = aabb.position.y + aabb.size.y   # ponto mais alto real

Estes são valores geométricos reais extraídos do próprio arquivo GLB — não números inventados ou estimados visualmente. Reportar os 10 valores medidos ANTES de aplicar qualquer reposicionamento, para validação do usuário.

Utilitário de ancoragem: PlanetAnchor.anchor_to_sphere()
Deve:

Usar os pontos de recesso JÁ ESCULPIDOS no modelo do terreno do planeta (os 5 platôs rebaixados) como pontos de ancoragem REAIS — nunca inventar coordenadas novas nem estimar posições a olho.
Calcular posição_final = ponto_do_recesso - (normal_radial * floor_offset_da_ilha)
Calcular rotação_final como um Basis ortonormal que alinha o eixo Y local da ilha à normal radial naquele ponto específico da esfera (não um Y global compartilhado entre as 5 ilhas).
Aplicar a MESMA lógica de normal radial às placas de título: cada placa usa a normal radial do ponto de ancoragem da sua ilha correspondente, não um Y global independente, posicionada a uma altura de flutuação acima da ilha.
===============================================================================

CÂMERA POR ILHA (modo "visitar ilha", índices 1 a 5)
=============================================================================== Cada ilha tem uma altura total diferente entre seu chão e o topo da sua placa de título, então o enquadramento de câmera NÃO pode usar um valor fixo compartilhado entre as 5 — precisa ser calculado individualmente por ilha, usando os mesmos valores medidos na seção anterior:

"Chão" de referência = floor_offset do mesh da ILHA (o ponto mais baixo real da ilha — não o topo do píer/convés, não o centro do AABB).
"Teto" de referência = ceiling_offset do mesh da PLACA de título daquela ilha específica (não o prédio mais alto da ilha — farol, Poneglyph etc. são "conteúdo" da ilha, não o limite superior da composição para fins de câmera).

func frame_island(island_floor_y: float, plate_ceiling_y: float, island_world_origin: Vector3) -> void:
    var total_height = plate_ceiling_y - island_floor_y
    var vertical_center = island_world_origin.y + (island_floor_y + plate_ceiling_y) * 0.5
    var camera_distance = total_height * 1.6  # fator de enquadramento, ajustar visualmente
    # camera.look_at(Vector3(island_world_origin.x, vertical_center, island_world_origin.z), ...)

===============================================================================

OUTRAS MECÂNICAS JÁ DEFINIDAS (continuar implementando, nesta ordem relativa)
===============================================================================

Canhão estilo Sea of Thieves: base/carro e cano já são assets separados de propósito. O eixo de pitch deve rotacionar apenas o cano, nos munhões, sem que eles saiam dos berços em U de madeira do carro. Recuo com física de mola/damping ao disparar. Som de impacto de canhão a extrair/integrar (referência de áudio: estilo Sea of Thieves hit sounds).
Alvos flutuantes já modelados, para teste de disparo do canhão.
Esteira de proa (bow spray): malha de grade 64×24 por lado, curvada no vertex shader formando folhas de água que se enrolam, estilo Seagazer; gotículas via GPUParticles3D; ondulação de esteira (wake) visível ao redor do barco conforme ele se move pela água.
Títulos flutuantes: as 5 placas de título 3D já modeladas (ou Label3D, conforme decisão técnica do Claude) devem flutuar acima de cada ilha correspondente, com fade por distância — aparecendo conforme o barco se aproxima da ilha.
Animações específicas por ilha (cada ilha já é um asset independente justamente para permitir isso): Poneglyph flutuando/pulsando como peça separada da ilha; farol com luz giratória; antena do Den Den Mushi se movendo; tochas ou luzes de janela acendendo — tudo isso considerando um ciclo dia/noite no ambiente.
Ciclo dia/noite: afetando iluminação geral, skybox/céu estrelado, e os elementos emissivos de cada ilha listados acima.
Sistema de câmera com 3 modos:
Seguir o barco em terceira pessoa (já implementado).
Orbital/visita de ilha, usando o cálculo de enquadramento por ilha descrito na seção anterior.
Visão do planeta inteiro, de longe.
Vela lisa (branca, sem Jolly Roger) já existe como variante do barco — a Jolly Roger deve ser aplicada como textura/decal diretamente no Godot (troca do mapa de albedo), não regerando o modelo 3D.
===============================================================================

DEPLOY / PUBLICAÇÃO — DESTINO FINAL
=============================================================================== Destino de produção: portfolio-data-cybersecurity.data-pedutraferreira.workers.dev (domínio Cloudflare Workers já ativo, hospedando a versão atual do portfólio do usuário).

O export do Godot 4 em WebGPU precisa ser compatível com esse ambiente de hospedagem — isso deve ser verificado/planejado na Fase 2 do processo abaixo, não assumido como "vai funcionar" sem checagem.

IMPORTANTE — restrição explícita: NÃO tentar publicar o jogo Godot dentro de um "Artifact" da plataforma claude.ai. Artifacts daquela plataforma são sandboxes de React/HTML/JS/Python para protótipos de INTERFACE, não hospedagem para um export de engine 3D/WebGPU. Um artifact pode, no máximo, servir como PROTÓTIPO DE LAYOUT/HUD em 2D (ver seção abaixo) — o jogo propriamente dito vai exclusivamente para o domínio Cloudflare Workers acima.

===============================================================================

REFERÊNCIAS DE LAYOUT/UX (interface do portfólio, não gameplay 3D)
===============================================================================

https://nazarejose.vercel.app — referência estrutural de layout de portfólio (organização de seções e conteúdo). Mirar a estrutura, não necessariamente o estilo visual exato.
Artifact do claude.ai (link: claude.ai/artifact/RiTbBMEqgfNwgMHMTAhf5P) — referência de USABILIDADE e LIMPEZA visual de interface; é o alvo de "sensação"/polish de UI que o usuário quer para o HUD/menus do portfólio, mais do que uma referência estrutural. Este conteúdo NÃO pôde ser verificado automaticamente fora do ambiente claude.ai (acesso bloqueado para ferramentas externas) — procurar primeiro por screenshots dele na pasta de referências do projeto; se não encontrar nenhum, perguntar ao usuário na Fase 2 antes de interpretar esta referência apenas por este texto.
Buscar ativamente na pasta de referências do projeto por capturas de tela dessas duas fontes antes de tomar qualquer decisão de layout baseada nelas.
===============================================================================

PROCESSO OBRIGATÓRIO DE TRABALHO — 3 FASES, NESTA ORDEM, SEM PULAR ETAPA
=============================================================================== Esta seção é uma REGRA DE PROCESSO, não uma sugestão. Pular direto para a ação sem entender o projeto inteiro foi, historicamente, a causa de boa parte do retrabalho e do desperdício de créditos de geração já ocorridos neste projeto. NÃO execute, altere, gere ou rode nada antes de completar a Fase 1.

FASE 1 — ENTENDER (proibido alterar qualquer arquivo nesta fase)
Explore livremente toda a pasta do projeto: cenas (.tscn), scripts (.gd), shaders, assets (.glb), configurações de projeto e export, e a pasta de referências (imagens de Seagazer, Wind Waker, One Piece, e screenshots do histórico de falhas visuais do oceano). Leia este documento inteiro, do início ao fim, antes de formar qualquer opinião sobre o que fazer. Nenhuma modificação de arquivo é permitida nesta fase.

FASE 2 — PLANEJAR E PERGUNTAR (entregar antes de agir)
Depois de entender o projeto, produza e entregue ao usuário, em texto, ANTES de qualquer execução:

Um resumo do estado atual real do projeto, conforme encontrado nos arquivos (o que já funciona, o que está quebrado, pontos problemáticos identificados diretamente no código/cenas/shaders — não apenas repetindo este documento).
Um plano de ação, na ordem recomendada, cruzando com a ordem sugerida na seção de pendências abaixo — pode propor uma ordem diferente se houver justificativa técnica, mas a justificativa deve ser explicitada.
Lista explícita de qualquer PLUGIN, EXTENSÃO, ADDON do Godot, ou PERMISSÃO/LIBERDADE DE AÇÃO adicional necessária para executar o plano (ex.: rodar o editor automaticamente, instalar algo, alterar configurações de export, acessar a internet, etc.). Se nada além do que já está instalado for necessário, isso também deve ser dito explicitamente.
Qualquer ambiguidade, informação faltante, ou divergência entre o que este documento descreve e o que foi realmente encontrado na pasta (nomes de arquivos diferentes, assets aparentemente ausentes, referências de layout não encontradas, etc.) — perguntar, nunca assumir ou preencher a lacuna sozinho.
NÃO avançar para a Fase 3 sem confirmação explícita do usuário sobre o plano apresentado na Fase 2.

FASE 3 — EXECUTAR (somente após aprovação explícita do plano)
Implementar o plano aprovado. Mesmo nesta fase: não interromper o trabalho a cada pequena etapa para mostrar renders/screenshots a cada ajuste — o objetivo é chegar ao resultado funcional completo (mundo grande + ondas corretas + vento global + ilhas corretamente posicionadas, nesta ordem de prioridade). Avisar o usuário apenas quando um bloco inteiro da lista de pendências abaixo estiver concluído, ou se travar em algo que exija decisão do usuário no meio da execução.

===============================================================================

PENDÊNCIAS, EM ORDEM SUGERIDA (a Fase 2 pode propor reordenar, com justificativa)
===============================================================================

Recalibrar a escala do globo (Prioridade Técnica #1) — impacta tudo o resto.
Reaplicar as ondas Trochoidal/Gerstner na nova escala; confirmar ausência de grade/banding/boiling/polka-dot (ver histórico completo de falhas).
Corrigir posicionamento e rotação das 5 ilhas com PlanetAnchor, usando os valores MEDIDOS de floor_offset/ceiling_offset.
Implementar o cálculo de câmera por ilha (frame_island).
Implementar o vento global afetando todo o mundo (WindManager).
Implementar esteira de proa, gotículas e ondulação de esteira (wake).
Implementar títulos flutuantes, animações específicas por ilha, ciclo dia/noite, os 3 modos de câmera, e física/som do canhão.
Verificar e preparar o export WebGPU para compatibilidade com o domínio de produção Cloudflare Workers.
===============================================================================

RESTRIÇÕES QUE VALEM NAS 3 FASES, SEM EXCEÇÃO
===============================================================================

NÃO criar, substituir ou regenerar nenhum asset 3D. Todos já existem na pasta. Qualquer suspeita de ausência vira pergunta na Fase 2.
NÃO tentar publicar o jogo dentro de um Artifact do claude.ai.
NÃO assumir nomes de arquivo ou caminhos citados neste documento como exatos — a pasta do projeto é a fonte da verdade; qualquer divergência encontrada deve ser reportada na Fase 2, não corrigida silenciosamente.
NÃO pular da Fase 1 direto para a Fase 3. A Fase 2 (plano + perguntas) é obrigatória e precisa de aprovação explícita do usuário antes de qualquer execução.


---

Isso é o documento final — completo, com o histórico inteiro, o produto final explícito logo no topo, a lista de assets, a prioridade de escala, todo o histórico de falhas do shader para não repetir, posicionamento das ilhas, câmera por ilha, demais mecânicas, deploy, referências de layout, e o gate de 3 fases como regra de processo, não sugestão.

