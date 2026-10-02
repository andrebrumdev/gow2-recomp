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
3. Commits (desde 2026-10-02): assunto em inglês, imperativo, prefixo Conventional (`feat|fix|docs|test|perf|refactor|chore(escopo):`), corpo em inglês ou pt-BR; sem co-autoria nem trailer de atribuição. **Output ao usuário em pt-BR**; raciocínio/planos/código internos em **inglês** (ver `../ps3recomp/CLAUDE.md` § Idioma).
4. `ppu_recomp_XXX.cpp/.h/.o` são gitignored (gigantes, regeneráveis) — fixes neles viram
   scripts idempotentes commitados (`patch_fallthrough_2550c8.py` é o modelo) e são
   reaplicados após cada re-lift.
5. `exit 124` do boot = normal (loop de render até timeout). `taskkill //F //IM
   boot_v2_new.exe` antes/depois de cada run.

Atalhos:
- Rodar (usuário, com janela): `recomp_mid_v2/rodar_gow2_intro_skip.cmd` (Win) /
  `./rodar_gow2.sh` (macOS: **Metal default** M10) ou `PS3_NO_RSX=1 ./boot_gow2 EBOOT.ELF`
- Smokes Mac (em `scripts/smoke/`, mapa em `scripts/README.md`): `scripts/smoke/smoke_intro_macos.sh`,
  `scripts/smoke/smoke_boot_mac.sh`, `scripts/smoke/smoke_perf_macos.sh`,
  `scripts/smoke/smoke_metal_matrix_mac.sh` (M10 matriz metal), `scripts/smoke/smoke_metal_draw_mac.sh`
- Build Mac: `./build_macos.sh` (LIFT_OPT/HOST_OPT/OUT para A/B; default `-O0`)
- Smokes Win: `recomp_mid_v2/bt_intro_wads.sh`, `bt_visual_combo.sh`, etc.
- Organização (2026-10-02): a raiz só tem pontos de entrada (launchers, `build_macos.sh`,
  `env_gow2.sh`, fontes do build, `apply_all_patches.sh`/`verify_lift.sh`/`accept_relift.sh`).
  Helpers do lift em `scripts/lift/`, diagnósticos Mac em `scripts/diag/`, `tr*.sh` e scripts do
  Windows de julho em `scripts/archive/windows/`, `decrypt_self.py`/`extract_pkg.py` em `tools/`.
  Mapa antigo → novo em `scripts/README.md`; os caminhos antigos viram wrappers até 2026-12-31.
  Arquivo novo na raiz: só com entrada em `ROOT_KEEP` de `scripts/check_layout.sh` (que falha se não).
- Recipe de env e **como puxar o upstream sp00nznet sem partir o Mac/GoW2**:
  ver secção **«Integrar melhorias do projeto original»** em `../ps3recomp/CLAUDE.md`

### Port Apple (obrigatório ler no motor)

Qualquer feature **macOS** (janela, vídeo, áudio, RSX, perf): seguir
`../ps3recomp/Claude.md` § **«Port Apple / macOS — otimização e baixo nível»**.

- Default GPU: **Metal nativo** (`PS3_RSX_BACKEND=metal`), não “port preguiçoso” do Win.
- Vídeo overlay: **VideoToolbox** (planos M0/M4), não ffmpeg CLI nem reencode Theora.
- Stack de planos: `../ps3recomp/docs/superpowers/plans/2026-07-21-00-macos-metal-stack-INDEX.md`
  (M0–M10: overlay, draw, MSL, tex, state, RT, content hold, vdec present, ops).
- Backlog do que falta portar: `../ps3recomp/docs/superpowers/plans/2026-07-21-00-macos-metal-pending-backlog.md`.
- Overlay **não** substitui WAD/vdec (cadeia `intro-vdec-open-force-wad`).

### Não-regressão Mac após merge do motor
Depois de qualquer integrate de `sp00nznet/ps3recomp` no `../ps3recomp`:
1. `cmake --build ../ps3recomp/build-macos -j…` + `./build_macos.sh`
2. Smoke 25s probes OFF: max `st620 ≥ 3` e sticky vivo
3. Matar boot pelo **PID** (TERM, depois -9) — nunca deixar órfãos a 90% CPU
4. Se st620=0 ou OOB `0xFFFF*`: **regressão do merge** — não commitar como “OK”;
   ver CLAUDE do motor (cherry-pick vs revert)
