# Revisão de navegação e oceano — 30/09/2026

Autorização: usuário encerrou a coleta de detalhes e pediu para prosseguir.

## Alterações

- Sobre: ajuste vertical próprio e remoção dos triângulos da faixa inferior de água turquesa incorporada em uma cópia da malha criada ao iniciar. Preserva o arquivo GLB. Colisão gerada após essa limpeza. A identificação usa altura e cor da textura, específica deste asset.
- Experiência: mar junto às rochas, com altura do penhasco preservada.
- Formação: base cinza submersa, com terreno e escadaria visíveis.
- Contato: areia recuperada com ajuste próprio.
- Cinco ilhas em um grande círculo do planeta, com centros separados por 72 graus. Raio do oceano mantido em 90 m. Distância entre centros vizinhos pela superfície: aproximadamente 113 m.
- Shift: 12,5 m/s como valor inicial ajustável. Velocidade normal: 4,2 m/s.
- Proteção contra subida nas ilhas: perímetro esférico conservador calculado pelas dimensões de cada asset e tamanho do casco. Bloqueia a componente de movimento que entra na ilha. Colisão de malha mantida. Enseadas estreitas ficam inacessíveis nesta etapa.
- Ondas mais longas, com alturas compartilhadas entre a superfície, flutuação e água da proa. Tons azuis mais escuros e reflexo reduzido.
- Espuma de crista, rastro e espuma junto aos objetos na linha d'água. A costa usa diferença de profundidade, não uma simulação de ondas refletidas pelo terreno.
- Botão esquerdo pressionado gera perturbações na altura da água. Arrastar move a origem. Eventos dissipam em quatro segundos. Limite de vinte eventos ativos. Botão direito preservado para câmera.
- Ciclo de 600 segundos, ajustável em `day_duration`. `day_phase` permite controlar o horário posteriormente pelo site. Luz solar, lunar, ambiente e céu mudam com a fase. Mar e espuma recebem essas luzes.
- Música MP3 de `Assets/Sound` em repetição, volume inicial -18 dB. Tecla M pausa/retoma. A pasta também será usada para futuros SFX.

## Limites desta etapa

A água usa ondas analíticas com perturbações locais, não fluidos volumétricos. A técnica da proa é uma aproximação inspirada no artigo de Seagazer. Não inclui o recorte detalhado pelo casco nem gotas do exemplo. A semelhança artística ainda depende de revisão do usuário em movimento.

Não foi feita publicação do site nesta etapa. Vela independente, currículo, atracação e otimização dos GLBs para web seguem em etapas próprias.

## Referências

- https://jettelly.com/blog/making-seagazer-s-bow-spray-feel-like-part-of-the-ocean
- https://store.steampowered.com/app/4989540/Seagazer/
- https://store.steampowered.com/app/3216520/Sandcastle/
- https://www.youtube.com/shorts/S7OuhAYsit8
- Música escolhida: https://www.youtube.com/watch?v=i43QHIupHfY

Os vídeos do YouTube não foram reproduzidos nesta consulta. O artigo técnico foi lido. O MP3 fornecido pelo usuário foi conectado ao player do Godot.

## Validação

25 verificações automatizadas passaram, sem falhas. Incluem aproximação de cada ilha por quatro lados a 12,5 m/s. Capturas das cinco ilhas, navegação e noite conferidas no renderizador D3D12. Evidência: Previews e navigation_revision.log. O teste confirma reprodução e pausa do player, não uma avaliação auditiva da faixa.

