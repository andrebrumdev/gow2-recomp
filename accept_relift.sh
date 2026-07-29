#!/usr/bin/env bash
# accept_relift.sh -- o aceite de promocao (D-5.1) num unico comando: TRES
# pernas, nenhuma delas reimplementada aqui, cada uma ja existente noutro
# script. rc final = AND das tres.
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
# AS TRES PERNAS:
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
#
# rc final = 0 SO se as tres pernas passarem. As tres correm sempre, mesmo
# que a 1a falhe (nao aborta cedo) -- o relatorio final mostra sempre o
# estado das tres, nunca so da primeira que falhou.
#
# Uso:
#   ./accept_relift.sh LIFT_DIR [RUNS] [OUTDIR]
#     LIFT_DIR default nenhum (obrigatorio); RUNS default 6; OUTDIR default /tmp.
#
# Protocolo G6 (D-5.5): logs em /tmp (fora dos dois repositorios), kill
# sempre por PID dentro de smoke_relift_equiv.sh (TERM depois -9), nunca
# pkill -f boot_gow2.
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
echo " accept_relift.sh -- aceite de tres pernas (D-5.1)"
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

# ---- relatorio final --------------------------------------------------------
echo "=============================================================="
echo " RELATORIO DE ACEITE (D-5.1)"
echo "=============================================================="
printf 'PERNA 1 (smoke)          %s   (OK=%s/%s)\n' "$([ "$leg1_rc" -eq 0 ] && echo PASS || echo FAIL)" "$leg1_ok" "$RUNS"
printf 'PERNA 2 (verify_lift)    %s   (rc=%s)\n' "$([ "$leg2_rc" -eq 0 ] && echo PASS || echo FAIL)" "$leg2_rc"
printf 'PERNA 3 (apply_patches)  %s   (NO-MATCH=%s FAILED-fora-PROBE=%s, UNVERIFIED=%s informativo)\n' \
  "$([ "$leg3_pass" -eq 1 ] && echo PASS || echo FAIL)" "$n_nomatch" "$n_failed_nao_probe" "$n_unverified"
echo

if [ "$leg1_rc" -eq 0 ] && [ "$leg2_rc" -eq 0 ] && [ "$leg3_pass" -eq 1 ]; then
  echo "ACEITE: rc=0 -- as tres pernas passaram."
  exit 0
else
  echo "REJEITADO: rc=1 -- pelo menos uma perna falhou (ver PASS/FAIL acima)."
  exit 1
fi
