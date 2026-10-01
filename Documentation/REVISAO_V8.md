# Revisão 8 — vento, placas e mar

O globo tem 200 m de raio na água e 196 m no leito. `Scripts/WorldScale.gd` fornece o raio para o cenário, as ondas e a balística. As cinco ilhas estão a cada 72° de longitude, com pequenos deslocamentos de latitude. Os seus modelos e colisões continuam intactos como filhos de cada ilha. Os diâmetros renderizados variam de 26 a 32 m. A distância de arco entre ilhas vizinhas é cerca de 251 m. O valor de 150 a 220 m da especificação não combina com um pentágono de 72° num raio de 200 m.

`Scripts/NavalGame.gd` posiciona três alvos a 20, 35 e 50 m da costa medida de cada ilha e cinco no mar aberto. Barco, alvos, água e projéteis compartilham o novo raio. O mar mantém a equação Gerstner esférica compartilhada por shader e GDScript, com altura radial, deslocamento tangente e espuma de crista. A espuma costeira agora reage à altura local da onda, ao padrão animado e à proximidade aproximada da margem. A captura `Previews/v8_shore.png` mostra a arrebentação na ilha Sobre. A costa do shader usa uma aproximação por raio de ilha; não resolve colisão de fluido com cada pedra.

`Scenes/WindRibbon.tscn` cria quatro fitas de laço de 4 s e três brisas retas. `Shaders/WindRibbon.gdshader` curva as fitas, afina as pontas e anima a passagem do vento. A cena usa sete malhas pequenas e funciona no renderizador Compatibility. Essa escolha evita `RibbonTrailMesh` com trilhas de partículas, que o renderizador Web não suporta. A captura isolada está em `Previews/v8_wind.png`.

As cinco placas novas entram em `Scripts/IslandTitleSign.gd`. O nome 3D já está no próprio modelo; o Label3D anterior fica oculto para não duplicar texto. Os originais permanecem em `Assets`. As cópias em `Assets/Optimized` têm cerca de 30 mil triângulos e 1,5 MB cada, contra 1,1 a 1,3 milhão de triângulos e 55 a 61 MB cada nos originais. `export_presets.cfg` exclui os arquivos originais das placas do pacote Web.

`Tests/v8_check.gd` passou em 82 verificações no Godot 4.7.2 com OpenGL Compatibility. O teste cobre raio, leito, rota, alinhamento, colisões, placas, alvos, vento, Log Pose, navegação e flutuação. A medição local após aquecimento foi de 120 quadros em 1.599 ms, aproximadamente 75 FPS, com o Log Pose ativo. O teste não mede navegador ou celular. A exportação Web ainda não foi realizada porque os modelos de exportação da versão 4.7.2 não estão instalados. O projeto também contém outros GLBs grandes que precisarão de redução antes da publicação Web.

Referência técnica do renderizador: https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html
