# Env canonico do God of War II HD (NPUA80491) -- fonte unica.
#
# Sourced por rodar_gow2.sh e smoke_boot_mac.sh. O equivalente Windows vive em
# recomp_mid_v2/rodar_gow2.cmd; manter os dois em sincronia, porque o plano
# exige que Mac e Windows classifiquem o mesmo wall (Phase 1 Task 1.4 de
# ../ps3recomp/docs/superpowers/plans/2026-07-20-gow2-full-bringup.md).
#
# Nao e executavel: e para `source`. Todas as variaveis respeitam valores ja
# definidos pelo chamador, para o smoke poder sobrepor sem editar este ficheiro.
#
# Uso:
#   . "$(dirname "$0")/env_gow2.sh"

# Raiz do VFS: onde os mount points do PS3 caem no host.
: "${PS3_VFS_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/extracted/USRDIR}"
export PS3_VFS_ROOT

# Filmes por HLE em vez de decode real. PS3_VDEC_ASYNC=1 e obrigatorio quando
# se liga decode de video a serio (ver o CLAUDE.md do motor); com NOMOVIES=1
# nao se aplica.
: "${PS3_MOVIE_HLE:=1}";        export PS3_MOVIE_HLE
: "${PS3_NOMOVIES:=1}";         export PS3_NOMOVIES

# Pad ligado a arranque, senao o jogo espera input que nunca chega.
: "${PS3_PAD_AUTOSTART:=1}";    export PS3_PAD_AUTOSTART

# FIFO do RSX consumido pelo backend.
: "${PS3_RSX_FIFO:=1}";         export PS3_RSX_FIFO

# Reordenacao do cellSysutil exigida pela ordem de init do titulo.
: "${PS3_CELLSYS_REORDER:=1}";  export PS3_CELLSYS_REORDER
