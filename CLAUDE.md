# CLAUDE.md — gow2_work (port do God of War II HD)

Repo de TRABALHO do port GoW2 do ps3recomp: launchers, scripts de run/smoke, patches
de lift (`patch_*.py`), registro de SPU e provas (frames). **O guia operacional completo
— metas, progresso, regras do que fazer/não fazer e metodologia — vive no repo do motor:
`../ps3recomp/CLAUDE.md`** (sub-projeto: `../ps3recomp/games/gow2/`). Leia-o primeiro.

Regras que valem dobrado AQUI (é o repo mais perto dos dados do jogo):

1. **NUNCA commitar dados do jogo**: `EBOOT.ELF/BIN`, `*.psarc`, `*.self`, `extracted/`,
   `movie_cache/`, `spu_images/`, `*.m2v`, `*.wav`, `*.wad_ps3`, `*_text.bin`.
   O `.gitignore` cobre, mas NUNCA use `git add -A`/`.` — sempre arquivos explícitos.
2. Push só para `origin` = fork pessoal andrebrumdev/gow2-recomp.
3. Commits em português, sem co-autoria.
4. `ppu_recomp_XXX.cpp/.h/.o` são gitignored (gigantes, regeneráveis) — fixes neles viram
   scripts idempotentes commitados (`patch_fallthrough_2550c8.py` é o modelo) e são
   reaplicados após cada re-lift.
5. `exit 124` do boot = normal (loop de render até timeout). `taskkill //F //IM
   boot_v2_new.exe` antes/depois de cada run.

Atalhos:
- Rodar (usuário, com janela): `recomp_mid_v2/rodar_gow2_intro_skip.cmd`
- Smokes: `recomp_mid_v2/bt_intro_wads.sh` (FORCE→WADs), `bt_visual_combo.sh` (EOS visual),
  `smoke_asset_pipeline.sh` (métricas de raiz), `run_basecase.sh` (heap/free-list)
- Build/relink: ver `recomp_mid_v2/build_crc.sh` (padrão de compile+link)
- Recipe de env canônico e armadilhas (VDEC_ASYNC obrigatório etc.): CLAUDE.md do ps3recomp
