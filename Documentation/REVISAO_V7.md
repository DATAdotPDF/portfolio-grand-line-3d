# Revisão 7 — globo, ilhas e Log Pose

O raio comum do planeta, da água e da balística é 280 m (`Scripts/WorldScale.gd`). As cinco ilhas ficam em posições de Fibonacci sobre a esfera. Os pontos mais ao norte e ao sul têm latitude aproximada de ±53°. A menor separação medida entre centros é superior a 200 m pela superfície. Os modelos, materiais, scripts de efeitos e colisões continuam como filhos das mesmas ilhas. As 21 boias foram recalculadas para o novo raio; as três de cada ilha continuam a 15, 20 e 25 m da costa.

`MainWorld.tscn` contém `IslandAnchors` com cinco marcadores. `Scripts/IslandDistributor.gd` roda no editor e distribui esses marcadores ao marcar `Execute Distribution`. A cena constrói as ilhas ao iniciar o jogo e copia a posição e a orientação dos marcadores. Assim, os marcadores aparecem no editor; os modelos completos aparecem quando a cena roda. Mudar só o raio do Inspector, sem mudar `WorldScale.gd`, deixaria água e ilhas em raios diferentes.

`Scenes/LogPose_HUD.tscn` usa os três GLBs fornecidos em um SubViewport transparente no canto superior direito. A agulha aponta para a ilha mais próxima pelo rumo tangente do globo. Ela responde ao giro da chalupa, troca de destino durante a navegação e oscila levemente. O desenho interno roda a 15 quadros por segundo em 160 × 160 pixels, ampliados para 220 × 220 no HUD. Os botões de hora e música ficaram abaixo da bússola.

A Jolly Roger foi invertida no eixo vertical da projeção da vela. A captura `Previews/v7_sail.png` mostra o rosto na posição correta.

O teste `Tests/v7_check.gd` passou em 47 verificações no Godot 4.7.2, renderizador OpenGL Compatibility. Ele cobre escala, distâncias, colisões, alvos, Log Pose, preservação dos modelos, navegação e flutuação. O teste também grava `Previews/v7_world.png`, `v7_logpose.png` e `v7_sail.png`. Em uma medição após o carregamento inicial, 60 quadros levaram 799 ms com o Log Pose ativo; outros 60 levaram 799 ms com seu desenho desligado. Esta medição local não substitui o teste no navegador. A exportação Web ainda depende dos modelos de exportação da versão 4.7.2, ausentes nesta máquina.
