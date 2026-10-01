# Revisão da câmera e saída para web

O mundo do Godot continua com água em esfera de raio 200 m, leito a 196 m, cinco ilhas e 20 alvos. A nova câmera segue a chalupa, orbita a ilha escolhida e mostra o globo inteiro. O trajeto entre modos fica acima da esfera.

Controles no sandbox:

- `1` a `5`: voar para a ilha correspondente e orbitar.
- `Tab`: visão do globo.
- `B`: voltar para a chalupa.
- Botão direito pressionado: ajustar ângulo da câmera em cada modo.

`Scripts/ExportWorldConfig.gd` monta a cena em processo separado e grava `Export/world_config.json`. Use o comando abaixo depois de mudar posições, escala, modelos, alvos ou parâmetros do mar:

```powershell
& 'D:\Godot\Godot.exe' --headless --rendering-method gl_compatibility --path 'D:\Godot\Projects\portifolio-pedro-ferreira-3d-2026' --script res://Scripts/ExportWorldConfig.gd
```

O JSON registra poses completas das ilhas, transformações locais dos GLBs, alvos, parâmetros das ondas, spawn do barco e velocidade. O site local recebe uma cópia por `npm run sync:godot -- <caminho-do-Godot>`. Ele ainda usa a cena antiga de 14 m e não lê este JSON para desenhar o mundo.

Checagens: `Tests/v9_check.gd` passou com zero falhas. `Tests/v9_preview.gd` gerou capturas dos três modos. Foram conferidas a ilha em órbita, a visão do globo e a câmera atrás do barco. `npm test` validou as 25 rotas do protótipo web e `npm run build` terminou. Esses testes não medem FPS em navegador.

O céu atual já é `shader_type sky` e usa a normal radial da câmera. Trocar isso diretamente por `EYEDIR.y` ou `LIGHT0_DIRECTION.y` faria o horizonte e o horário dependerem do eixo Y global, mesmo quando a chalupa navega em outro hemisfério. Sunshine Clouds 2 não foi adicionado. O plugin usa o compositor do Godot e tem relatos abertos de problema com Godot 4.7 e suporte a planeta esférico.

Ainda faltam GLBs leves das ilhas, barco e alvos, o uso do JSON no Three.js, a cena web na escala nova e os modos de jogo/ranking. A versão web atual e o site publicado não foram substituídos nesta revisão.
