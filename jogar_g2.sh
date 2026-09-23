#!/bin/bash
# jogar_g2.sh -- igual ao jogar_gow2.sh, mas o binario chama-se `g2play`.
# Porque existe: outra sessao corre um kill_competing que mata por padrao de
# nome qualquer processo com "boot_gow2" -- o jogo lancado por jogar_gow2.sh
# morria com SIGKILL (exit 137) a meio. Nome neutro = nao e' apanhado.
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE" || exit 1
# capturados ANTES do env_gow2.sh, que os poe incondicionalmente
G2_DONE_MS="${PS3_MOVIE_DONE_MS-}"
G2_MUTE="${PS3_MUTE-}"
G2_AUTOSTART="${PS3_PAD_AUTOSTART-}"
# Jogar abre em TELA CHEIA (F11 / Cmd+Enter / Escape voltam para janela).
# Em janela: PS3_FULLSCREEN=0 ./jogar_g2.sh
export PS3_FULLSCREEN="${PS3_FULLSCREEN:-1}"
set -a
. "$HERE/env_gow2.sh"
set +a
# PS3_TRACE_PROMPT_SHAPES: sonda de DIAGNOSTICO dos icones de botao. Estava
# ligada por default aqui, mas ela calcula uma assinatura de forma por DRAW no
# material 0x59864B76 -- que e' tambem o material das particulas, centenas de
# draws por frame no combate. Fica opt-in: `PS3_TRACE_PROMPT_SHAPES=1 ./jogar_g2.sh`.
# Cutscenes em video: o env_gow2.sh poe PS3_MOVIE_DONE_MS=3000, um atalho de
# BANCADA ("a medicao repete a mesma intro dezenas de vezes por sessao") que
# corta TODO filme aos 3 segundos -- o armador ancora no open e forca o fim
# ivl ms depois, re-armando a cada playback. Para JOGAR isso e' um bug.
# "auto" usa a duracao REAL do .wav do cache em vez de uma constante.
# LIMITE CONHECIDO: o valor e' latched uma vez e o cache so tem UM wav
# (SmLogo_v2, 14,7 s), logo todas as cutscenes herdam esse comprimento.
# Melhora, nao corrige. A correccao de raiz e' o relogio de audio (as vozes do
# mixer SCREAM nao avancam, por isso o filme nunca acaba sozinho).
export PS3_MOVIE_DONE_MS="${G2_DONE_MS:-auto}"
# Som LIGADO a jogar. O env_gow2.sh poe PS3_MUTE=1 porque a bancada corre a
# intro dezenas de vezes por sessao; para jogar isso e' um bug. "0" desliga o
# mute de verdade desde que ps3_audio_muted() passou a respeitar o valor
# (antes QUALQUER valor mutava, ate' PS3_MUTE=0). Mutar: PS3_MUTE=1 ./jogar_g2.sh
export PS3_MUTE="${G2_MUTE:-0}"
# Pad automatico DESLIGADO a jogar. O env_gow2.sh liga PS3_PAD_AUTOSTART para a
# bancada (percorre logos/menu sozinho); a jogar ele carregava START/CROSS no
# primeiro segundo e saltava o filme de abertura -- a musica da intro nunca
# tocava -- e ainda navegava o menu ate' o jogador tocar numa tecla. O cellPad
# testa so' a PRESENCA da variavel (ate' "0" liga), por isso unset. Teclado e
# comando ja' ligam a porta 0. Bancada a partir daqui: PS3_PAD_AUTOSTART=1 ./jogar_g2.sh
if [ -n "$G2_AUTOSTART" ]; then export PS3_PAD_AUTOSTART="$G2_AUTOSTART"; else unset PS3_PAD_AUTOSTART; fi
mkdir -p "$HERE/claude_runs"
LOG="${JOGAR_LOG:-$HERE/claude_runs/jogar.log}"   # testar_fix.sh usa um por teste
echo "[jogar] log: $LOG"
exec ./g2play EBOOT.ELF > "$LOG" 2>&1
