#!/usr/bin/env bash
# accept_relift.sh -- o aceite de promocao (D-5.1 + D-5.2 + GATE-03) num
# unico comando: QUATRO pernas, nenhuma delas reimplementada aqui, cada uma
# ja existente noutro script, mais uma seccao de contadores por delta
# (D-5.2). rc final = AND das quatro pernas E dos contadores bloqueantes.
#
# A LICAO que criou este script (05-CONTEXT.md, 2026-07-26): o lift
# regenerado passou o smoke M0 com st620=11 em 6/6 -- MELHOR do que o
# criterio 1 exige (>=3 em >=4 de 6) -- e foi promovido a producao com base
# so nisso. Faltavam-lhe 36 conversoes OPD, 35 guardas 0x4F000000u e 9
# familias de marcador. O smoke mede a intro ate st620=11; a perda estava
# no WADLD e no caminho de shaders, DEPOIS disso. A perna 2
# (games/gow2/verify_lift.sh) e a que teria apanhado essa perda -- e' por
# isso que o smoke sozinho e necessario mas NUNCA suficiente.
#
# A LICAO que acrescentou a PERNA 4 (07-CONTEXT.md, 2026-07-30, Fase 7): as
# tres pernas acima medem lift/patches, mas NENHUMA delas mede se a cadeia
# de boot chega ao thr_auto_load. Foi exactamente esse buraco que promoveu,
# em 29 Jul, um binario que nao chega ao AUTO_LOAD (StartSeq=1, thr_end=0).
#
# AS QUATRO PERNAS:
#   perna 1 -- smoke_relift_equiv.sh [LIFT] [RUNS] [TSV]
#              rc=0 se st620>=3 em >=4 de 6 execucoes reais.
#   perna 2 -- games/gow2/verify_lift.sh LIFT_DIR (via PS3_ENGINE_ROOT)
#              rc=0 os 3 passos (lift_parity/MANIFEST/audit_boundaries)
#              passam por DELTA contra os baselines congelados (Fase 4 +
#              Plano 05-02) -- ja NAO nasce vermelho por divida conhecida.
#   perna 3 -- apply_all_patches.sh LIFT --status TSV
#              este script NUNCA usa o `rc` bruto desse comando para a
#              perna 3: esse `rc` tambem conta UNVERIFIED (D-4.1), que e
#              divida conhecida (42 patches FUNCIONAL sem contrato) e NAO
#              deve bloquear esta fase. Em vez disso le-se o `--status`
#              TSV directamente e exige-se so zero NO-MATCH e zero FAILED
#              fora de classe PROBE -- exactamente o que D-5.1 especifica.
#   perna 4 -- smoke_chain_gate.sh --bin BIN RUNS TSV (GATE-03, Fase 7)
#              rc=0 se a cadeia de 5 elos bloqueantes (intro/2o movie/
#              re-Play/AUTO_LOAD/WAD) chega ao fim em >=THRESHOLD de RUNS
#              execucoes. Reutiliza o MESMO binario que a PERNA 1 acabou de
#              construir -- nunca dispara um segundo build a partir do
#              mesmo LIFT_REL. Le o TSV produzido (nunca o rc bruto de
#              forma opaca) e nomeia o elo_stopped mais frequente entre as
#              corridas que falharam.
#
# rc final = 0 SO se as quatro pernas passarem. As quatro correm sempre,
# mesmo que uma ja tenha falhado (nao aborta cedo) -- o relatorio final
# mostra sempre o estado das quatro, nunca so da primeira que falhou.
#
# Uso:
#   ./accept_relift.sh LIFT_DIR [RUNS] [OUTDIR]
#     LIFT_DIR default nenhum (obrigatorio); RUNS default 6; OUTDIR default /tmp.
#
# Protocolo G6 (D-5.5): logs em /tmp (fora dos dois repositorios), kill
# sempre por PID dentro de smoke_relift_equiv.sh/smoke_chain_gate.sh (TERM
# depois -9), nunca pkill -f boot_gow2.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
REPO="$PWD"

LIFT_REL="${1:?uso: accept_relift.sh LIFT_DIR [RUNS] [OUTDIR]}"
RUNS="${2:-6}"
OUTDIR="${3:-/tmp}"

LIFT="$REPO/${LIFT_REL#./}"
if [ ! -d "$LIFT" ]; then
  echo "ERRO: dir de lift nao existe: $LIFT" >&2
  exit 2
fi
TAG="$(basename "$LIFT")"

# ---- ponte cross-repo (mesma convencao de apply_all_patches.sh:112) --------
PS3_ENGINE_ROOT="${PS3_ENGINE_ROOT:-$REPO/../ps3recomp}"
VERIFY_LIFT="$PS3_ENGINE_ROOT/games/gow2/verify_lift.sh"
if [ ! -x "$VERIFY_LIFT" ]; then
  echo "ERRO: verify_lift.sh nao encontrado ou nao executavel ($VERIFY_LIFT) -- sem a perna 2 nao ha aceite possivel" >&2
  exit 2
fi

echo "=============================================================="
echo " accept_relift.sh -- aceite de tres pernas + contadores (D-5.1 + D-5.2)"
echo " lift   : $LIFT"
echo " runs   : $RUNS"
echo " outdir : $OUTDIR"
echo "=============================================================="
echo

# ---- PERNA 1: smoke_relift_equiv.sh ----------------------------------------
TSV1="$OUTDIR/accept_${TAG}_smoke.tsv"
echo "---- PERNA 1: smoke_relift_equiv.sh ----"
"$REPO/smoke_relift_equiv.sh" "$LIFT_REL" "$RUNS" "$TSV1"
leg1_rc=$?
leg1_ok=$(awk -F'\t' 'NR>1 && $8=="OK"{n++} END{print n+0}' "$TSV1" 2>/dev/null)
leg1_ok=${leg1_ok:-0}
echo "PERNA 1: OK=$leg1_ok de $RUNS, rc=$leg1_rc"
echo

# ---- PERNA 4: smoke_chain_gate.sh (cadeia, GATE-03) ------------------------
# Reutiliza o MESMO binario que a PERNA 1 acabou de construir -- mesma
# convencao de nomes de smoke_relift_equiv.sh:84 (BIN="$HERE/boot_gow2_${TAG#recomp_macos_}").
# NUNCA dispara um segundo build a partir do mesmo LIFT_REL (~1.5min
# desperdicados e um segundo binario que podia divergir do primeiro por
# timing de compilacao).
BIN4="$REPO/boot_gow2_${TAG#recomp_macos_}"
TSV4="$OUTDIR/accept_${TAG}_chain.tsv"
echo "---- PERNA 4: smoke_chain_gate.sh (cadeia) ----"
if [ -x "$BIN4" ]; then
  "$REPO/smoke_chain_gate.sh" --bin "$BIN4" "$RUNS" "$TSV4"
  leg4_rc=$?
  leg4_ok=$(awk -F'\t' 'NR>1 && $10=="OK"{n++} END{print n+0}' "$TSV4" 2>/dev/null)
  leg4_ok=${leg4_ok:-0}
  leg4_elo="$(awk -F'\t' 'NR>1 && $10=="REGRESSAO"{print $9}' "$TSV4" 2>/dev/null \
    | sort | uniq -c | sort -rn | head -1 | sed 's/^ *[0-9]* //')"
else
  echo "ERRO: binario da PERNA 1 nao encontrado ($BIN4) -- PERNA 1 deve ter falhado antes de construir" >&2
  leg4_rc=2
  leg4_ok=0
  leg4_elo="binario nao construido"
fi
if [ "$leg4_rc" -eq 0 ]; then
  echo "PERNA 4: OK=$leg4_ok de $RUNS, rc=$leg4_rc"
else
  echo "PERNA 4: OK=$leg4_ok de $RUNS, rc=$leg4_rc, elo_stopped mais frequente: ${leg4_elo:-desconhecido}"
fi
echo

# ---- PERNA 2: games/gow2/verify_lift.sh ------------------------------------
LOG2="$OUTDIR/accept_${TAG}_verify.log"
echo "---- PERNA 2: verify_lift.sh ----"
"$VERIFY_LIFT" "$LIFT" > "$LOG2" 2>&1
leg2_rc=$?
leg2_detail="$(grep -E '^(lift_parity|MANIFEST|audit_boundaries)\s' "$LOG2" 2>/dev/null)"
printf '%s\n' "$leg2_detail"
echo "PERNA 2: rc=$leg2_rc (log completo: $LOG2)"
echo

# ---- PERNA 3: apply_all_patches.sh --status (NUNCA o rc bruto) ------------
TSV3="$OUTDIR/accept_${TAG}_status.tsv"
LOG3="$OUTDIR/accept_${TAG}_patches.log"
echo "---- PERNA 3: apply_all_patches.sh --status (rc bruto ignorado para o gate) ----"
"$REPO/apply_all_patches.sh" "$LIFT_REL" --status "$TSV3" > "$LOG3" 2>&1
leg3_rc_bruto=$?
n_nomatch=$(awk -F'\t' 'NR>1 && $2=="NO-MATCH"{n++} END{print n+0}' "$TSV3" 2>/dev/null)
n_nomatch=${n_nomatch:-0}
n_failed_nao_probe=$(awk -F'\t' 'NR>1 && ($2=="FAILED" || $2=="FAILED-PARTIAL") && $3!="PROBE"{n++} END{print n+0}' "$TSV3" 2>/dev/null)
n_failed_nao_probe=${n_failed_nao_probe:-0}
n_unverified=$(awk -F'\t' 'NR>1 && $2=="UNVERIFIED"{n++} END{print n+0}' "$TSV3" 2>/dev/null)
n_unverified=${n_unverified:-0}
if [ "$n_nomatch" -eq 0 ] && [ "$n_failed_nao_probe" -eq 0 ]; then
  leg3_pass=1
else
  leg3_pass=0
fi
echo "PERNA 3: NO-MATCH=$n_nomatch FAILED-fora-de-PROBE=$n_failed_nao_probe (UNVERIFIED=$n_unverified, informativo, nao bloqueia)"
echo "PERNA 3: rc bruto (inclui UNVERIFIED, nao bloqueia D-5.1)=$leg3_rc_bruto | leg3_pass=$leg3_pass"
echo

# ---- CONTADORES (D-5.2): baseline REAL congelado vs candidato, por DELTA ---
# 56072 (function_table_count) e 56223 (lifted functions registered), citados
# em ROADMAP.md/REQUIREMENTS.md, sao do lift ANTIGO escrito a mao (31 chunks --
# ver games/gow2/lift_baseline/counters_pre.tsv). O lift regenerado (producao
# E candidato, medido nesta sessao) tem function_table_count=51917 nos DOIS --
# gatear pelos absolutos antigos faria este gate falhar sempre contra
# qualquer lift novo. Em vez disso: congela-se UMA VEZ um baseline real
# contra a producao atual (recomp_macos_v2/boot_gow2), e mede-se o candidato
# por delta. imp_modules/imp_imports/orfaos NAO dependem do lift -- ficam
# absolutos e BLOQUEANTES. function_table_count/boot_lifted_functions ficam
# INFORMATIVOS (delta reportado, nunca bloqueia este rc -- a justificacao por
# escrito do delta fica no relatorio de aceite, Plano 05-05).
BASELINE_TSV="$PS3_ENGINE_ROOT/games/gow2/lift_baseline/COUNTERS_BASELINE.tsv"

baseline_val() {
  awk -F'\t' -v k="$1" '$1==k{print $2; exit}' "$BASELINE_TSV"
}

counters_baseline_freeze() {
  if [ -f "$BASELINE_TSV" ]; then
    return 0
  fi
  echo "AVISO: $BASELINE_TSV nao existe -- congelando baseline REAL contra a producao (recomp_macos_v2/boot_gow2)" >&2
  local ftc_prod prod_tsv lifted_prod modules_prod imports_prod
  # Rule 1 fix (encontrado nesta corrida real): "grep -oE '[0-9]+'" sozinho
  # casa o "64" de "uint64_t" ANTES do valor real apos "= " -- extrair so o
  # numero apos "= " evita esse falso-positivo.
  ftc_prod=$(grep -h "function_table_count = " "$REPO"/recomp_macos_v2/ppu_recomp_*.cpp 2>/dev/null | grep -oE '= [0-9]+' | grep -oE '[0-9]+' | head -1)
  prod_tsv="$OUTDIR/counters_baseline_prod.tsv"
  "$REPO/smoke_relift_equiv.sh" --bin "$REPO/boot_gow2" 1 "$prod_tsv"
  lifted_prod=$(tail -1 "$prod_tsv" | awk -F'\t' '{print $3}')
  modules_prod=$(tail -1 "$prod_tsv" | awk -F'\t' '{print $4}')
  imports_prod=$(tail -1 "$prod_tsv" | awk -F'\t' '{print $5}')
  mkdir -p "$(dirname "$BASELINE_TSV")"
  {
    echo "# COUNTERS_BASELINE.tsv -- baseline REAL congelado (D-5.2), medido por"
    echo "# accept_relift.sh contra a producao atual (recomp_macos_v2 / boot_gow2)"
    echo "# na primeira corrida em que este ficheiro nao existia."
    echo "#"
    echo "# NOTA: 56072/56223 (ROADMAP.md/REQUIREMENTS.md) sao do lift ANTIGO"
    echo "# escrito a mao (31 chunks -- ver games/gow2/lift_baseline/counters_pre.tsv)."
    echo "# O lift regenerado (medido nesta sessao) tem function_table_count=51917"
    echo "# tanto na producao como no candidato -- gatear pelos absolutos antigos"
    echo "# faria este gate falhar sempre contra qualquer lift novo (D-5.2)."
    printf 'contador\tvalor\n'
    printf 'function_table_count\t%s\n' "$ftc_prod"
    printf 'boot_lifted_functions\t%s\n' "$lifted_prod"
    printf 'imp_modules\t%s\n' "$modules_prod"
    printf 'imp_imports\t%s\n' "$imports_prod"
    printf 'orfaos\t0\n'
  } > "$BASELINE_TSV"
  echo "COUNTERS_BASELINE.tsv congelado: $BASELINE_TSV"
}

counters_baseline_freeze

# Rule 1 fix: mesmo cuidado que em counters_baseline_freeze() -- "64" de
# "uint64_t" precede o valor real de function_table_count na mesma linha.
ftc_cand=$(grep -h "function_table_count = " "$LIFT"/ppu_recomp_*.cpp 2>/dev/null | grep -oE '= [0-9]+' | grep -oE '[0-9]+' | head -1)
lifted_cand=$(tail -1 "$TSV1" | awk -F'\t' '{print $3}')
modules_cand=$(tail -1 "$TSV1" | awk -F'\t' '{print $4}')
imports_cand=$(tail -1 "$TSV1" | awk -F'\t' '{print $5}')
orfaos_cand=$(pgrep -f "$TAG" | wc -l | tr -d ' ')

ftc_prod="$(baseline_val function_table_count)"
lifted_prod="$(baseline_val boot_lifted_functions)"
modules_prod="$(baseline_val imp_modules)"
imports_prod="$(baseline_val imp_imports)"

echo "---- CONTADORES (D-5.2) ----"
printf '%-24s producao=%-8s candidato=%-8s delta=%-6s %s\n' \
  "function_table_count" "$ftc_prod" "$ftc_cand" "$((ftc_cand - ftc_prod))" "[INFORMATIVO -- delta justificado no relatorio de aceite]"
printf '%-24s producao=%-8s candidato=%-8s delta=%-6s %s\n' \
  "boot_lifted_functions" "$lifted_prod" "$lifted_cand" "$((lifted_cand - lifted_prod))" "[INFORMATIVO -- delta justificado no relatorio de aceite]"
printf '%-24s producao=%-8s candidato=%-8s delta=%-6s %s\n' \
  "imp_modules" "$modules_prod" "$modules_cand" "$((modules_cand - modules_prod))" "[BLOQUEANTE]"
printf '%-24s producao=%-8s candidato=%-8s delta=%-6s %s\n' \
  "imp_imports" "$imports_prod" "$imports_cand" "$((imports_cand - imports_prod))" "[BLOQUEANTE]"
printf '%-24s producao=%-8s candidato=%-8s delta=%-6s %s\n' \
  "orfaos" "0" "$orfaos_cand" "$((orfaos_cand - 0))" "[BLOQUEANTE]"
echo

if [ "$modules_cand" = "$modules_prod" ] && [ "$imports_cand" = "$imports_prod" ] && [ "$orfaos_cand" -eq 0 ] 2>/dev/null; then
  counters_pass=1
else
  counters_pass=0
fi

# ---- relatorio final --------------------------------------------------------
echo "=============================================================="
echo " RELATORIO DE ACEITE (D-5.1 + D-5.2 + GATE-03)"
echo "=============================================================="
printf 'PERNA 1 (smoke)          %s   (OK=%s/%s)\n' "$([ "$leg1_rc" -eq 0 ] && echo PASS || echo FAIL)" "$leg1_ok" "$RUNS"
printf 'PERNA 2 (verify_lift)    %s   (rc=%s)\n' "$([ "$leg2_rc" -eq 0 ] && echo PASS || echo FAIL)" "$leg2_rc"
printf 'PERNA 3 (apply_patches)  %s   (NO-MATCH=%s FAILED-fora-PROBE=%s, UNVERIFIED=%s informativo)\n' \
  "$([ "$leg3_pass" -eq 1 ] && echo PASS || echo FAIL)" "$n_nomatch" "$n_failed_nao_probe" "$n_unverified"
if [ "$leg4_rc" -eq 0 ]; then
  printf 'PERNA 4 (chain gate)     %s   (OK=%s/%s)\n' "PASS" "$leg4_ok" "$RUNS"
else
  printf 'PERNA 4 (chain gate)     %s   (OK=%s/%s, elo_stopped mais frequente: %s)\n' "FAIL" "$leg4_ok" "$RUNS" "${leg4_elo:-desconhecido}"
fi
printf 'CONTADORES (D-5.2)       %s   (imp_modules/imp_imports/orfaos bloqueantes)\n' \
  "$([ "$counters_pass" -eq 1 ] && echo PASS || echo FAIL)"
echo

if [ "$leg1_rc" -eq 0 ] && [ "$leg2_rc" -eq 0 ] && [ "$leg3_pass" -eq 1 ] && [ "$leg4_rc" -eq 0 ] && [ "$counters_pass" -eq 1 ]; then
  echo "ACEITE: rc=0 -- as quatro pernas + contadores bloqueantes passaram."
  exit 0
else
  echo "REJEITADO: rc=1 -- pelo menos uma perna ou os contadores bloqueantes falharam (ver PASS/FAIL acima)."
  exit 1
fi
