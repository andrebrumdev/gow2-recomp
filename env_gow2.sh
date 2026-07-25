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
# se liga decode de video a serio (ver o CLAUDE.md do motor).
: "${PS3_MOVIE_HLE:=1}";        export PS3_MOVIE_HLE

# PS3_NOMOVIES deixou de ser 1 por default. Era, quando o macOS nao tinha
# caminho de dados nenhum: o movie_hle.c inteiro era #ifdef _WIN32 e os
# movie_io_* eram stubs no-op. Com o porte POSIX (0318caa) e os membros
# extraidos do psarc para movie_cache/, o titulo passa a ler WADs a serio --
# e o R_PermA e' o que alimenta o registry de shaders. Continuar com
# NOMOVIES=1 mataria exactamente a rota que se quer exercitar (Plano 04
# Task 3 diz isto por palavras). Quem quiser saltar a intro poe =1 a mao.
: "${PS3_NOMOVIES:=0}";         export PS3_NOMOVIES

# Caminho de I/O dos membros do psarc ja extraidos (R_PermA, R_LglScA e a
# intro). Sem MOVIE_IO=1 o movie_io_open nem e' consultado e o jogo cai no
# cellFs normal, que nao acha estes nomes.
: "${PS3_MOVIE_IO:=1}";         export PS3_MOVIE_IO
: "${PS3_MOVIE_CACHE:=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/movie_cache}"
export PS3_MOVIE_CACHE
: "${PS3_MOVIE_EOS:=1}";        export PS3_MOVIE_EOS

# Decode de video assincrono. Obrigatorio no caminho da intro (o sync voltou a
# ser default noutro commit; ver CLAUDE.md do motor). Respeitado se ja definido.
: "${PS3_VDEC_ASYNC:=1}";       export PS3_VDEC_ASYNC

# Pad ligado a arranque, senao o jogo espera input que nunca chega.
: "${PS3_PAD_AUTOSTART:=1}";    export PS3_PAD_AUTOSTART

# SPU1 = dearch / EDGE-zlib (fp 0x2A5C4E67A14505B8). Hit limpo in-boot
# (2026-07-22: HIT>=1, MISS=0, SPUJOB clean). Necessario para consumo
# real de WAD apos R_Perm; sem isto o dispatch fica MISS e o path de
# texturas WAD/UI nao avanca. spu2/3 continuam opt-in (PS3_SPU2/3).
: "${PS3_SPU1:=1}";             export PS3_SPU1

# FIFO do RSX consumido pelo backend.
: "${PS3_RSX_FIFO:=1}";         export PS3_RSX_FIFO

# Backend RSX (M10): no Darwin, default Metal com janela. Headless usa
# PS3_NO_RSX=1 e nao precisa de backend. Respeita valor ja definido.
if [ -z "${PS3_NO_RSX:-}" ]; then
    case "$(uname -s 2>/dev/null)" in
        Darwin) : "${PS3_RSX_BACKEND:=metal}" ;;
        *)      : "${PS3_RSX_BACKEND:=sdl}" ;;
    esac
    export PS3_RSX_BACKEND
fi

# Reordenacao do cellSysutil exigida pela ordem de init do titulo.
: "${PS3_CELLSYS_REORDER:=1}";  export PS3_CELLSYS_REORDER
