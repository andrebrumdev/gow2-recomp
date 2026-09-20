#!/bin/bash
# jogar_g2.sh -- igual ao jogar_gow2.sh, mas o binario chama-se `g2play`.
# Porque existe: outra sessao corre um kill_competing que mata por padrao de
# nome qualquer processo com "boot_gow2" -- o jogo lancado por jogar_gow2.sh
# morria com SIGKILL (exit 137) a meio. Nome neutro = nao e' apanhado.
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE" || exit 1
# capturado ANTES do env_gow2.sh, que poe 3000 incondicionalmente
G2_DONE_MS="${PS3_MOVIE_DONE_MS-}"
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
mkdir -p "$HERE/claude_runs"
echo "[jogar] log: $HERE/claude_runs/jogar.log"
exec ./g2play EBOOT.ELF > "$HERE/claude_runs/jogar.log" 2>&1
