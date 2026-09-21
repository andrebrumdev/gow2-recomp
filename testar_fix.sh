#!/bin/bash
# testar_fix.sh N -- roda o jogo com UMA correcao do documento RPCS3 ligada.
#   1  §1  saidas do vertex shader comecam em (0,0,0,1)  [PS3_RSX_FIX_OUT_W1]
#   2  §2  sem o atalho "UV vazio -> UV cru" (so' nosso)  [PS3_RSX_FIX_NO_TC0_HACK]
#   3  §3  sem semear o UV empacotado no atributo 8       [PS3_RSX_FIX_NO_UV_SEED]
#   4  §6  neblina so' do componente X                     [PS3_RSX_FIX_FOG_X]
#   0      nenhuma (referencia, igual ao jogo de hoje)
HERE="$(cd "$(dirname "$0")" && pwd)"
case "$1" in
  1) export PS3_RSX_FIX_OUT_W1=1 ;;
  2) export PS3_RSX_FIX_NO_TC0_HACK=1 ;;
  3) export PS3_RSX_FIX_NO_UV_SEED=1 ;;
  4) export PS3_RSX_FIX_FOG_X=1 ;;
  0) ;;
  *) sed -n '2,7p' "$0"; exit 1 ;;
esac
echo "[testar_fix] correcao $1 ligada"
exec "$HERE/jogar_g2.sh"
