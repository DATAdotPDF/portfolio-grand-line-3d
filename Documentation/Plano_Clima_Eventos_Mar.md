# Plano: clima e eventos do mar (referência: vídeo do Grande Mar, Wind Waker)

Fonte: `References/The Great Sea - ... noclip ... 2026-10-05.mp4` (4 min 33 s), gravado no noclip.website.
O vídeo é **só referência visual** e não sai do PC: nada de modelo, textura ou som da Nintendo entra no
projeto. Tudo é feito por nós, em shader e código, ou com o Meshy.

## 1. O que o vídeo mostra (onde a câmera para)

| Tempo | Cena | O que interessa |
|---|---|---|
| 0:12–0:54 | **Ciclone** | Fitas espirais semitransparentes em camadas (cone torcido), redemoinho branco na base da água, céu e mar com tom verde-acinzentado só perto dele; por dentro, um túnel girando. |
| 1:39–2:09 | Entardecer com lua, **ilhotas de pedra** | Pares de rochas recortadas no horizonte, em silhueta; mar escuro. |
| 1:54 | **Gaivotas** | Bando pequeno cruzando o céu, só silhueta em "V". |
| 2:12–2:30 | Ilha com penhasco e cascata | Variedade de formas: penhasco, gruta, platô com grama. |
| 2:33–3:15 | Mar à noite | Pontinhos espalhados no horizonte (barcos, boias, mirantes): o mar nunca fica vazio. |
| 3:18–3:48 | **Navio fantasma** | Casco verde translúcido e brilhante, cordame, mastro quebrado; aparece à noite. |
| 4:15–4:30 | **Tempestade local** | Anel de nuvem escura em forma de rosca sobre uma ilha, chuva só ali dentro, mar e céu escuros no meio, lua vista pelo "olho". |

(1:09–1:36, a torre em ruínas com tom sépia, não estava na sua lista; ficou de fora.)

## 2. O que dá para fazer, e como

Limites do nosso projeto: WebGL 2 (Compatibility), planeta de 800 m de raio, pacote do celular com ~20 MB,
níveis de gráficos Alto/Médio/Baixo. Cada item abaixo diz o que eu implemento e se você precisa produzir asset.

| # | Recurso | Dá? | Como (resumo) | Asset seu? |
|---|---|---|---|---|
| 1 | **Gaivotas esporádicas** | Sim, barato | Pássaro procedural (malha em "V" de poucos triângulos, asas batendo no shader). Bando de 3 a 7 a cada 40–90 s, cruzando com o vento ou circulando perto das ilhas. Som: já temos `SEAGULLS OPEN SEA SFX 1.mp3`. | **Não** |
| 2 | **Tempestade local** (nuvem, chuva, mar revolto) | Sim | Uma "célula" que anda com o vento: rosca de nuvem escura (malha + shader de ruído, estilo cartoon), cilindro de chuva com riscos animados no shader (sem partículas pesadas), riscos de chuva na tela quando o barco entra, ondas mais altas e mar mais escuro dentro do raio. Isso usa o mesmo jeito que já usamos para acalmar as ondas perto das ilhas, ao contrário: lá elas diminuem, aqui crescem, na CPU e no shader, para o barco continuar boiando certo. Mais relâmpagos de vez em quando (flash no céu e na luz). | **Não** (só sons, ver §3) |
| 3 | **Ciclone que teleporta** | Sim | 3 a 4 cones torcidos aninhados com faixas espirais rolando no shader (alfa, sem luz), disco de espuma girando na água, névoa e luz puxadas para o verde-cinza perto dele. Ao entrar: o barco sobe girando, a tela clareia e ele reaparece num ponto aleatório **de mar aberto** (longe de ilhas e da borda), com aviso no HUD ("O ciclone te levou para…"). | **Não** (só sons) |
| 4 | **Navio fantasma** | Sim, com modelo | Shader verde translúcido (brilho nas bordas, emissão, leve tremor), lanterna verde, névoa verde em volta. Só à noite; a posição segue a fase da lua real do dia (ideia do estudo). Ele navega numa rota; se o jogador chega perto, some na névoa ou revela um easter egg (o lado Red Team/cyber). | **Sim**: 1 navio em partes |
| 5 | **Ilhotas variadas** | Sim, com modelos | Sistema de espalhamento: poucas variantes, muitas instâncias (girando e mudando a escala), com colisão simples e longe das 5 ilhas principais. Ajuda a "carta náutica com descoberta". | **Sim**: 5 variantes |

## 3. O que você produz (Meshy e som)

Lição da chalupa: **peça as partes separadas** (casco, velas, bandeira). Malha única fundida obriga a
cortar na mão depois.

### Navio fantasma: 1 modelo, 3 partes

| Parte | Prompt base (Meshy, estilo das nossas ilhas: cartoon, cores chapadas) | Alvo |
|---|---|---|
| Casco + mastros + cordame | "stylized ghost galleon hull, broken masts, rotten planks, low poly, cartoon, no sails, neutral grey-green" | ≤ 15 mil triângulos |
| Velas rasgadas | "tattered ghost ship sails, separate, hanging cloth with holes, cartoon" | ≤ 3 mil triângulos |
| Bandeira | "tattered pirate flag, separate, cartoon" | ≤ 500 triângulos |

A cor final vem do nosso shader verde, então a textura pode ser simples (tons de cinza já ajudam).

### Ilhotas: 5 variantes (formas diferentes, mesma paleta das ilhas)

1. **Par de rochas recortadas** (sea stacks), como em 1:39–2:09.
2. **Banco de areia com 1 coqueiro.**
3. **Ilhota de grama com penhasco** (mini platô, pode ter cascata pintada).
4. **Recife**: rochas baixas quase no nível da água.
5. **Destroço ou mirante**: casco virado ou plataforma de madeira (é o "pontinho no horizonte" da noite).

Alvo por ilhota: **3 a 6 mil triângulos, textura de 512 a 1024 px**. Eu passo pelo mesmo pipeline das ilhas
(glTF-Transform + versão do celular). As 5 juntas devem caber em ~2 MB no desktop e ~1 MB no celular.

### Golfinho: 1 modelo (substitui o provisório feito em código)

Hoje o golfinho é uma malha gerada no `Scripts/SeaLife.gd` (`_build_dolphin_mesh`). O comportamento
(grupo acompanhando a proa, saltos em arco, respingos) e o nado (cauda sobe e desce no
`Shaders/sea_creature.gdshader`) continuam iguais; só a malha muda.

| Item | Pedido |
|---|---|
| Prompt base | "stylized bottlenose dolphin, cartoon, low poly, flat colors, dark blue-grey back, light grey belly, straight body, mouth closed, flippers and flukes spread flat, no base" |
| Pose | Corpo **reto** (sem curva, sem salto), caudal **horizontal**, peitorais abertas. Sem esqueleto: o nado é no shader. |
| Partes | **Uma malha só** (aqui não precisa separar: nada se move independente). |
| Tamanho e eixo | ~2,4 m do focinho à cauda. Se vier de lado ou em outra escala, eu giro e meço na importação. |
| Orçamento | 2 a 4 mil triângulos, textura de 512 px (cores chapadas bastam). |

Na integração: troco a malha do MultiMesh e calculo no shader a posição ao longo do corpo (0 focinho,
1 cauda) a partir do comprimento do modelo, no lugar do `UV.y` da malha provisória. Os peixes podem
continuar em código (são pequenos e rápidos demais para o modelo fazer diferença).

### Sons: 6 efeitos curtos

Chuva (loop), trovão (2 variações), vento de ciclone (loop), "whoosh" do teleporte e ambiente do navio
fantasma (loop). Fonte a decidir: geração via fal (tem custo; eu gero com o seu ok) ou bancos CC0
(Freesound). Mesma pendência dos direitos das músicas.

## 4. Ordem sugerida

| Etapa | O que | Depende de você? |
|---|---|---|
| 1 | Gaivotas | Não |
| 2 | Tempestade local (sem som primeiro) | Não |
| 3 | Ciclone + teleporte | Não |
| 4 | Sons de chuva, trovão e ciclone | Escolher a fonte |
| 5 | Ilhotas + espalhamento | 5 modelos Meshy |
| 6 | Navio fantasma | 1 modelo Meshy (3 partes) |

Etapas 1 a 3 eu faço já, com teste no Godot e prints. Do 5 e 6 eu cuido da integração quando os modelos chegarem.

## 5. Cuidados

- **Recrutador com pressa:** ciclone e tempestade ficam visíveis e são evitáveis, nunca no caminho entre
  as ilhas no começo. O teleporte não leva para longe do conteúdo: o HUD mostra a ilha mais próxima.
- **Celular:** chuva, ciclone e nuvem usam transparência, que pesa no celular por causa das camadas
  sobrepostas. No nível Baixo, menos camadas e sem riscos de chuva na tela.
- **Originalidade:** formas e comportamento inspirados, execução nossa. Nada copiado do jogo.
