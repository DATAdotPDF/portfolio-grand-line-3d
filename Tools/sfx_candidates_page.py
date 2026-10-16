# Gera Builds/SfxCandidatos/index.html: página local para ouvir os recortes de teste.
# Uso: python -I Tools/sfx_candidates_page.py
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "Builds", "SfxCandidatos")

# (grupo, [(arquivo, para quê, origem, licença, observação)])
GROUPS = [
    ("Kraken", [
        ("kraken_pressagio_loop", "Presságio (loop)", "385818 ominous_horn", "CC0", "Pitch 0,85 (mais grave). Loop."),
        ("kraken_pressagio_tensao", "Presságio, alternativa", "776333 tension", "CC0", "Cordas de suspense. Soa mais como trilha do que como criatura."),
        ("kraken_aparece_boom", "Aviso / sombra chegando", "541600 cinematic boom", "CC-BY 4.0", "Pancada única quando o aviso aparece."),
        ("kraken_riser", "Subida antes dos tentáculos", "784974 riser-gleamer", "CC-BY 4.0", "Riser longo (8,5 s)."),
        ("kraken_intro_cinematica", "Alternativa ao riser", "810166 cinematic intro", "CC-BY 4.0", "Gerado por IA (diz o autor)."),
        ("kraken_tentaculo_a", "Tentáculo saindo da água", "376819 impact-wet", "CC-BY 3.0", "Pitch 0,7."),
        ("kraken_tentaculo_b", "Tentáculo (variação)", "376819 impact-wet", "CC-BY 3.0", "Pitch 0,55, mais pesado."),
        ("kraken_rugido", "Rugido", "837799 sea-creature-roar", "CC0", "Feito para kraken. Meu favorito."),
        ("kraken_rugido_grave", "Rugido, mais grave", "837799", "CC0", "Pitch 0,8."),
        ("kraken_rugido_antigo", "Rugido, alternativa", "648480 ancient-roar (trecho 52–59 s)", "CC-BY 4.0", "Um dos rugidos da série."),
        ("kraken_rugido_eco", "Rugido com eco", "345736 deep-roar-echo", "CC0", ""),
        ("kraken_redemoinho_loop", "Redemoinho (loop)", "567241 vortex", "CC0", "Pitch 0,75. O original já emenda."),
        ("kraken_redemoinho_borbulha", "Camada de borbulhas do redemoinho (loop)", "696008 stomach growls", "CC0", "Barriga roncando, metade do pitch + passa-baixa: vira borbulha grave. Testar por baixo do vortex."),
        ("kraken_barra_carga", "Barra de ação enchendo", "555060 charge-up", "CC0", "Inteiro (2,2 s)."),
        ("kraken_barra_toque", "Toque na barra", "555060 (trecho)", "CC0", "Recorte de 0,5 s para cada toque."),
        ("kraken_arranque_nc", "Arranque final", "716972 engine-ignition burst", "CC-BY-NC 4.0", "Licença NÃO comercial."),
        ("kraken_naufragio", "Naufrágio", "624150 + 618085 + 17341", "CC0", "Mix: madeira quebrando + rangido grave + bolhas."),
    ]),
    ("Navio fantasma e biomas", [
        ("fantasma_navio_loop", "Navio fantasma (loop)", "648654 ghost-ship-ambience (2–24 s)", "CC0", "Cabos rangendo e vozes. Bom."),
        ("fantasma_perseguicao", "Começa a perseguir", "367746 scream", "CC0", "Risada esticada com eco."),
        ("fantasma_some_whoosh_nc", "Some na névoa", "241146 whoosh, invertido", "CC-BY-NC 4.0", "NÃO comercial. O nosso teleport_whoosh também serve."),
        ("fantasma_espacial_loop", "Bioma fantasma (loop), alternativa", "55541 spaceghostship", "CC-BY 3.0", "Ruído sintético, passa-baixa."),
        ("bioma_fantasma_aves_nc", "Bioma fantasma (loop)", "688741 sea at night + Manx shearwater", "CC-BY-NC 4.0", "Aves noturnas que soam como espíritos. NÃO comercial."),
        ("bioma_fantasma_piano_musica", "Bioma fantasma: é MÚSICA", "819108 piano", "CC0", "Piano, não ambiência. Serve como faixa da trilha."),
        ("vulcao_lava_loop", "Vulcão: lava (loop)", "474849 lava-loop", "CC0", "Emenda perfeito. Baixinho: subir o volume no jogo."),
        ("vulcao_erupcao_nc", "Vulcão: erupção", "674560 cascading explosion", "CC-BY-NC 4.0", "NÃO comercial. Primeiros 14 s."),
    ]),
    ("Animais", [
        ("golfinho_a_nc", "Golfinho", "202489 dolphins (2–6 s)", "CC-BY-NC 4.0", "Gravação real na proa de veleiro. NÃO comercial."),
        ("golfinho_b_nc", "Golfinho (variação)", "202489 (8,5–12,5 s)", "CC-BY-NC 4.0", ""),
        ("golfinho_imitacao", "Golfinho, alternativa", "456151 dolphin-noise", "CC0", "Uma pessoa imitando golfinho."),
        ("baleia_canto", "Jubarte", "82325 diving-with-whales (3–13 s)", "CC0", "Gravação real debaixo d'água."),
        ("baleia_canto_voz", "Jubarte, alternativa", "171945 low whale song", "CC0", "Voz humana processada."),
        ("foca_a_nc", "Foca", "347162 Weddell seal pup (22,8 s)", "CC-BY-NC 4.0", "NÃO comercial."),
        ("foca_b_nc", "Foca (variação)", "347162 (27,5 s)", "CC-BY-NC 4.0", ""),
        ("tubarao_tensao_nc", "Tubarão: tensão", "13698 shark01", "CC-BY-NC 4.0", "Abelha processada. NÃO comercial."),
        ("tartaruga_respiro", "Tartaruga gigante", "427414 dinosaur growls", "CC-BY 4.0", "Pitch 0,75 + passa-baixa. É rosnado, não respiro: testar."),
    ]),
    ("Mundo", [
        ("boia_sino", "Boia-sino", "804786 rope-hung bell", "CC-BY 4.0", ""),
        ("boia_sino_panela", "Boia-sino, alternativa", "264850 metal pan bell", "CC0", "Pitch 0,8, primeira batida."),
        ("costa_ondas_loop", "Costa / praia (loop)", "795445 waves crashing", "CC0", "Era .m4a (o Godot não lê)."),
        ("noite_mar_loop", "Mar à noite (loop)", "465435 ocean beach at night", "CC0", ""),
        ("chuva_baltico_loop", "Chuva real (pode trocar a sintetizada)", "870414 thunderstorm Baltic sea", "CC0", "30 s sem trovão."),
        ("fogueira_loop", "Fogueira (loop)", "784223 meat frying over campfire", "CC-BY 4.0", "É carne chiando: testar se passa por fogueira."),
        ("bau_abrindo_moedas", "Baú + moedas", "872674 chest open + 223342 coins", "CC-BY 4.0 + CC0", "Mix (moedas entram em 0,45 s). O baú foi feito com IA."),
        ("farol_buzina", "Farol: buzina", "371290 foghorn", "CC0", "Muito alto no original."),
        ("farol_buzina_longe", "Farol: buzina distante", "371290", "CC0", "Passa-baixa + eco."),
        ("farol_buzina_b", "Farol, alternativa", "81869 foghorn + gaivotas", "Sampling+", "Licença antiga (Sampling+). Prefiro a 371290."),
        ("lanterna_acende", "Lanterna acendendo", "637533 flame burst", "CC0", "Era .flac (o Godot não lê)."),
        ("lanterna_isqueiro", "Lanterna, alternativa", "816728 lighter", "CC0", ""),
        ("cordame_rangido_a", "Leme/cordame rangendo", "618083 wood creak", "CC0", "Pitch 0,8."),
        ("cordame_rangido_b", "Rangido (variação)", "618084", "CC0", ""),
        ("cordame_rangido_c", "Rangido (variação)", "618085", "CC0", ""),
    ]),
    ("Interface, desafio e canhão", [
        ("ui_clique_madeira", "Clique de botão", "342200 menu click (madeira)", "CC0", ""),
        ("ui_clique_b", "Clique, alternativa", "629020 button-click", "CC0", ""),
        ("ui_carta_papel", "Abrir a carta", "828026 paper fold", "CC-BY 4.0", "Recorte de 1,5 s."),
        ("ui_aviso_pop", "Aviso (toast)", "540568 ui-pop-up", "CC-BY 4.0", ""),
        ("ui_aviso_notificacao", "Aviso, alternativa", "616699 notification-7", "CC0", ""),
        ("ilha_descoberta", "Chegou numa ilha", "401179 achado-2", "CC0", "Primeiros 4,5 s (o original tem 16 s)."),
        ("ilha_descoberta_sitar", "Ilha, alternativa", "422548 egyptian discovery", "CC0", ""),
        ("ovo_pascoa_alerta", "Easter egg", "277031 completed alert", "CC-BY 4.0", ""),
        ("ovo_pascoa_blip", "Easter egg, alternativa", "531512 positive blip", "CC0", ""),
        ("sucesso_ux", "Sucesso genérico", "634450 success", "CC0", ""),
        ("desafio_contagem", "Desafio: bipe da contagem", "446130 race-start-countdown", "CC-BY 4.0", "Toca 3×."),
        ("desafio_largada", "Desafio: largada", "446142 race-start", "CC-BY 4.0", ""),
        ("desafio_contagem_321go", "Desafio: 3-2-1-GO pronto", "651010 pre-match countdown", "CC-BY 4.0", ""),
        ("desafio_ultimos10s", "Desafio: últimos 10 s", "211103 time-running-out (0–10,4 s)", "CC-BY 4.0", "Tique que acelera."),
        ("desafio_tempo_acabou", "Desafio: tempo acabou", "211103 (buzina final)", "CC-BY 4.0", ""),
        ("desafio_tique_nc", "Tique, alternativa", "243070 wood-block tick", "CC-BY-NC 4.0", "NÃO comercial."),
        ("desafio_vitoria", "Desafio: vitória", "677858 game-success-fanfare", "CC0", ""),
        ("desafio_vitoria_ia", "Vitória, alternativa", "810330 triumphant success", "CC-BY 4.0", "Gerado por IA (diz o autor)."),
        ("canhao_sem_municao", "Canhão recarregando", "869285 ui error", "CC0", "Digital demais: talvez não combine."),
        ("canhao_mira_manivela_loop", "Mira (manivela, loop)", "517120 crank", "CC0", "Era quase inaudível: normalizado."),
        ("canhao_tiro_b", "Tiro, alternativa ao atual", "162455 cannonball", "CC0", "Opcional."),
        ("canhao_tiro_corrente", "Tiro com corrente", "448002 cannon", "CC0", "Opcional."),
        ("canhao_impacto", "Impacto da bala", "423105 cannon impact", "CC-BY 4.0", "Pode trocar o EXPLOSION atual."),
        ("explorar_whoosh_nc", "Entrar em \"Explorar em 3D\"", "241146 transition whoosh", "CC-BY-NC 4.0", "NÃO comercial."),
    ]),
]

css = """
:root{--bg:#f6f1e7;--card:#fffaf0;--ink:#2a2118;--muted:#7a6a55;--line:#e3d7c3;--nc:#9e1b2b;--ok:#2f6b3a}
@media (prefers-color-scheme:dark){:root{--bg:#141820;--card:#1d222c;--ink:#ece6da;--muted:#a9b3c7;--line:#2c3340;--nc:#e7787f;--ok:#7fc58a}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.45 system-ui,sans-serif}
main{max-width:980px;margin:0 auto;padding:24px 16px 64px}h1{font-size:22px;margin:0 0 4px}p.lead{color:var(--muted);margin:0 0 20px}
h2{font-size:17px;margin:28px 0 10px;border-bottom:1px solid var(--line);padding-bottom:6px}
.row{display:grid;grid-template-columns:1fr 300px;gap:12px;align-items:center;background:var(--card);border:1px solid var(--line);border-radius:10px;padding:10px 12px;margin:8px 0}
.t{font-weight:600}.m{color:var(--muted);font-size:13px}.lic{font-size:12px;font-weight:600;color:var(--ok)}.lic.nc{color:var(--nc)}
audio{width:100%}@media (max-width:640px){.row{grid-template-columns:1fr}}
"""
rows = []
for title, items in GROUPS:
    rows.append(f"<h2>{title}</h2>")
    for name, use, src, lic, note in items:
        path = os.path.join(OUT, name + ".ogg")
        missing = "" if os.path.exists(path) else " (FALTA O ARQUIVO)"
        nc = " nc" if "NC" in lic else ""
        rows.append(
            f'<div class="row"><div><div class="t">{use}{missing}</div>'
            f'<div class="m">{name}.ogg · origem: {src}</div>'
            f'<div class="m">{note}</div><div class="lic{nc}">{lic}</div></div>'
            f'<audio controls preload="none" src="{name}.ogg"></audio></div>')
html = f"""<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>SFX candidatos</title>
<style>{css}</style></head><body><main>
<h1>SFX candidatos</h1>
<p class="lead">Recortes de teste dos sons baixados (Tools/cut_sfx_candidates.sh): mono, pico em −1 dBFS, fades nas pontas, loops com as pontas cruzadas. Os volumes no jogo ainda vão ser ajustados. Em vermelho, as licenças NÃO comerciais.</p>
{''.join(rows)}
</main></body></html>"""
open(os.path.join(OUT, "index.html"), "w", encoding="utf-8").write(html)
print("ok", sum(len(i) for _, i in GROUPS), "itens")
