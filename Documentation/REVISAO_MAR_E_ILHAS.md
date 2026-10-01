# Mar, ciclo global e efeitos das ilhas

## Alterações aplicadas

- `DayNightCycle.gd` registrado em Autoload. Um relógio global, com escuridão calculada pela posição de cada ilha na esfera. Corrigida a convenção: 0 = meia-noite, 0,25 = alvorada, 0,5 = meio-dia e 0,75 = crepúsculo no hemisfério de referência.
- Ciclo inicial de 1.800 segundos, ajustável. É mais lento que o ciclo anterior de 600 segundos. `set_time(valor, congelar)` prepara controles de dia/noite para a futura página.
- O sol é direcional. Sua distância não altera o resultado. O ciclo controla direção e iluminação.
- Sobre próximo ao polo norte, Contato próximo ao polo sul. Experiência, Formação e Projetos em latitudes 12°, -8° e 14°, separados em longitude.
- Ondas de 22 m, 11 m e 5,5 m, com amplitudes de 0,48 m, 0,22 m e 0,09 m. Água e flutuação compartilham essas funções. Atualização visual interpolada entre passos de física.
- Física interpolada para o barco. Câmera acompanha a posição interpolada, sem aplicar uma segunda interpolação automática.
- Menos cálculos repetidos por pixel. Perturbações só percorrem eventos ativos. Normais com interação calculadas nos vértices. Malha do oceano reduzida de 512 × 256 para 256 × 128 divisões.
- Níveis de detalhe gerados para as cópias alteradas do porto e do templo. GLBs originais preservados.
- Recorte elíptico da superfície dentro do casco. Duas folhas curvas de água na proa, com variação pela velocidade e pelas curvas. Espuma junto à costa continua baseada na profundidade dos objetos.
- Céu com nuvens procedurais, sol, lua e estrelas. Cor acompanha o ciclo.
- Vela branca recebe movimento de vento por shader, limitado por altura e cor do tecido. Isso não é simulação de pano e a vela ainda pertence à malha importada.
- Tecla L controla a lamparina da chalupa, que recebe luz âmbar durante a noite local. M mantém o controle da música.
- Poneglyph separado usando limites medidos na malha original. Flutuação, giro, emissão nas inscrições e partículas. O pedestal e as plantas ficam parados.
- Farol com feixe rotativo noturno, cone sem tampas e foco de 80 m.
- Luz oscilante nas tochas da fortaleza e nos lampiões da taberna/píer. Baús recebem brilho dourado noturno.
- Luzes e partículas distantes são desligadas para reduzir trabalho fora da área próxima ao visitante.

## Verificação

32 verificações automatizadas passaram. Incluem aproximação às cinco ilhas por quatro lados com Shift, flutuação, água por clique/arraste, dissipação, distribuição polar/equatorial, relógio global, noite em hemisférios opostos, Poneglyph, farol e lamparina.

Capturas de dia e noite das cinco ilhas e uma vista próxima do casco foram conferidas no D3D12, na RTX 3060 Ti. O convés aparece sem água nessa captura. Essa conferência não substitui testar todas as manobras possíveis.

## Limites e próximas etapas

- O oceano continua analítico e esférico. O sistema FFT do GodotOceanWaves foi consultado como referência, mas não foi incorporado.
- O shader da proa é uma aproximação do vídeo. Não inclui o ajuste por dezenas de planos do casco nem gotas soltas do exemplo.
- O perímetro conservador de navegação impede subir nas ilhas, mas também restringe enseadas estreitas.
- O evento `open_chest()` prepara um clarão. A tampa do baú continua unida ao modelo e não abre nesta etapa. As animações e o conteúdo do currículo ao visitar as ilhas ficam para a etapa da interface.
- O resultado de desempenho deve ser lido com o cenário e resolução usados. Não afirmar que o engasgo relatado pelo usuário foi reproduzido ou eliminado em todas as condições.
- Os assets originais ainda são grandes para distribuição web. Não houve publicação nesta etapa.

## Referências consultadas

- Artigo técnico: https://jettelly.com/blog/making-seagazer-s-bow-spray-feel-like-part-of-the-ocean
- FFT: https://github.com/2Retr0/GodotOceanWaves
- Interpolação: https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/using_physics_interpolation.html
- Níveis de detalhe: https://docs.godotengine.org/en/stable/classes/class_importermesh.html

Foram extraídos e examinados quadros do MP4 local enviado pelo usuário. Os links do YouTube, o Shadertoy e a página do portfólio não abriram na consulta web desta etapa. Não considerar seus conteúdos integralmente analisados.
