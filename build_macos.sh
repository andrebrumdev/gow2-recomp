#!/usr/bin/env bash
# Build the God of War II HD native macOS/arm64 host (phase F4 of
# ps3recomp/docs/MACOS_PORT_PLAN.md). The POSIX counterpart of build_d3d.sh.
#
# Assumes the lift already ran:
#   python ../ps3recomp/tools/ppu_lifter.py EBOOT.ELF --functions functions.json \
#          --output recomp_macos
#
# Usage: ./build_macos.sh [lift-dir]        (default: recomp_macos_v2)
#
# Opt levels / output (perf A/B):
#   LIFT_OPT=-O0|-O1|-O2|-Os  optimization for lifted ppu_recomp_*.cpp (default -O0)
#   HOST_OPT=-O0|-O1|-O2|-Os  host/runtime objects + link (default -O0; SPU stays -O1)
#   OUT=/path/to/boot_gow2    binary path (default $HERE/boot_gow2)
#   FORCE_REBUILD_LIFT=1      ignore stale .o and rebuild all lift chunks
#   RELIFT=1  regenera o lift a partir do EBOOT.ELF/functions.json num
#             directorio NOVO (default recomp_macos_v3) antes de compilar;
#             NUNCA escreve em recomp_macos_v2 (aborta se o alvo resolver
#             para la)
#
# Examples:
#   ./build_macos.sh
#   LIFT_OPT=-O1 OUT=./boot_gow2_O1 ./build_macos.sh
#   LIFT_OPT=-O1 HOST_OPT=-O1 FORCE_REBUILD_LIFT=1 OUT=./boot_gow2_O1 ./build_macos.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# Raiz do motor. Override por PS3_ENGINE_ROOT para compilar contra uma worktree
# git do ps3recomp em vez do checkout ao lado -- necessario quando duas sessoes
# partilham o checkout principal e cada uma tem o seu branch. Sem a variavel o
# comportamento e' exactamente o de antes.
PS3="${PS3_ENGINE_ROOT:-$HERE/../ps3recomp}"
# Default recomp_macos_v2: e o lift em que o apply_all_patches.sh opera (tambem
# tem esse default). recomp_macos e' um lift ANTIGO sem os patches da sessao --
# nomeadamente sem o ps3_indirect_tail (fix do bctr), sem o qual o pump da intro
# bate na recursao de host. Compilar o lift errado dava um boot sem os fixes.
LIFT="${1:-$HERE/recomp_macos_v2}"
OUT="${OUT:-$HERE/boot_gow2}"
LIFT_OPT="${LIFT_OPT:--O0}"
HOST_OPT="${HOST_OPT:--O0}"
FORCE_REBUILD_LIFT="${FORCE_REBUILD_LIFT:-0}"

# RELIFT=1: regenera o lift a partir do EBOOT.ELF/functions.json num
# directorio SEMPRE novo (nunca recomp_macos_v2, que e' produção) antes de
# seguir para as seccoes normais de compilacao/link. Sob RELIFT=1 o
# positional $1 passa a significar "directorio NOVO a criar" em vez de
# "directorio existente a compilar" -- essa mudanca de significado so' se
# aplica dentro deste ramo condicional (D-3.5, 03-CONTEXT.md).
if [ "${RELIFT:-0}" = "1" ]; then
    LIFT="${1:-$HERE/recomp_macos_v3}"

    # Guarda anti-v2 (D-3.5): resolve o caminho absoluto canonico do alvo
    # ANTES de qualquer mkdir/escrita e aborta se resolver para
    # recomp_macos_v2. dirname existe sempre, mesmo que $LIFT ainda nao
    # exista -- por isso o resolve funciona mesmo em directorio novo.
    _lift_parent="$(cd "$(dirname "$LIFT")" 2>/dev/null && pwd)"
    _lift_abs="$_lift_parent/$(basename "$LIFT")"
    _v2_abs="$HERE/recomp_macos_v2"
    if [ "$_lift_abs" = "$_v2_abs" ]; then
        echo "RELIFT=1 nunca escreve em recomp_macos_v2 (produção) -- escolha outro directorio de saida" >&2
        exit 1
    fi

    EBOOT="${PS3_EBOOT:-$HERE/EBOOT.ELF}"
    FUNCS="${PS3_FUNCTIONS_JSON:-$HERE/functions.json}"
    if [ ! -f "$EBOOT" ]; then
        echo "RELIFT=1: EBOOT nao encontrado em $EBOOT (defina PS3_EBOOT)" >&2
        exit 1
    fi
    if [ ! -f "$FUNCS" ]; then
        echo "RELIFT=1: functions.json nao encontrado em $FUNCS (defina PS3_FUNCTIONS_JSON)" >&2
        exit 1
    fi

    # --config: sem ele o lifter corre "como antes" e NAO emite os mid-asm
    # hooks -- ou seja, um RELIFT=1 produzia um lift SEM o wait-idle do CE03C
    # e o build seguinte compilava um gow2_midasm_hooks.o que ninguem chama
    # (medido no plano 17-03: e' o bug que faz o piloto parecer migrado sem o
    # estar). PS3_RECOMP_CONFIG permite apontar para outro TOML; vazio ou
    # ficheiro ausente = comportamento legado, sem hooks.
    RECOMP_CFG="${PS3_RECOMP_CONFIG:-$HERE/config/gow2_recomp.toml}"
    CFG_ARGS=()
    if [ -f "$RECOMP_CFG" ]; then
        CFG_ARGS=(--config "$RECOMP_CFG")
        echo "  RELIFT: --config $RECOMP_CFG"
    else
        echo "  RELIFT: sem --config (nao existe $RECOMP_CFG) -- lift SEM mid-asm hooks"
    fi

    mkdir -p "$LIFT"
    echo "=== 0. RELIFT=1: regenerando lift em $LIFT (a partir de $EBOOT) ==="
    python3 "$PS3/tools/ppu_lifter.py" "$EBOOT" --functions "$FUNCS" \
        ${CFG_ARGS[@]+"${CFG_ARGS[@]}"} -o "$LIFT" -j 4
    _relift_rc=$?
    if [ "$_relift_rc" != "0" ]; then
        exit "$_relift_rc"
    fi
fi

case "$LIFT_OPT" in -O0|-O1|-O2|-Os) ;; *)
    echo "LIFT_OPT must be -O0|-O1|-O2|-Os (got '$LIFT_OPT')" >&2; exit 1 ;;
esac
case "$HOST_OPT" in -O0|-O1|-O2|-Os) ;; *)
    echo "HOST_OPT must be -O0|-O1|-O2|-Os (got '$HOST_OPT')" >&2; exit 1 ;;
esac

if [ ! -f "$LIFT/ppu_recomp.h" ]; then
    echo "no lift output in $LIFT -- run ppu_lifter.py first" >&2
    exit 1
fi

RUNTIME_LIB="$PS3/build-macos/libps3recomp_runtime.a"
if [ ! -f "$RUNTIME_LIB" ]; then
    echo "runtime library missing; build it first:" >&2
    echo "  cmake -B $PS3/build-macos -G Ninja -DCMAKE_BUILD_TYPE=Release $PS3" >&2
    echo "  cmake --build $PS3/build-macos" >&2
    exit 1
fi

INC=(-I "$LIFT"
     -I "$PS3/include"
     -I "$PS3/runtime/ppu"
     -I "$PS3/runtime/syscalls"
     -I "$PS3/runtime/spu"
     -I "$PS3/runtime/prx"
     -I "$PS3/runtime/memory"
     -I "$PS3/libs/system" -I "$PS3/libs/spurs" -I "$PS3/libs/sync"
     -I "$PS3/libs/video"  -I "$PS3/libs/audio" -I "$PS3/libs/network"
     -I "$PS3/libs/codec")

JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
JOBS=$(( JOBS > 6 ? 6 : JOBS ))   # each chunk peaks near 1 GB of compiler RSS

# Tag objects by lift opt so -O0 and -O1 can coexist without clobbering each
# other when A/B benchmarking. Default -O0 keeps historical bare *.cpp.o names
# (no mass rebuild of existing trees). Non-default: ppu_recomp_NNN.cpp.1.o
lift_obj() {
    local f=$1
    if [ "$LIFT_OPT" = "-O0" ]; then
        echo "$f.o"
    else
        echo "${f}.${LIFT_OPT#-O}.o"
    fi
}

echo "=== 1. lifted chunks -> .o  LIFT_OPT=$LIFT_OPT HOST_OPT=$HOST_OPT OUT=$OUT (-P $JOBS) ==="
cd "$LIFT"
t0=$(date +%s)
# Only rebuild chunks whose object is missing or stale. FORCE_REBUILD_LIFT=1
# rebuilds every chunk (needed when switching LIFT_OPT with shared bare .o
# names, or after patch re-apply without mtime bump).
{
    for f in ppu_recomp_*.cpp ppu_stubs.cpp; do
        [ -f "$f" ] || continue
        o=$(lift_obj "$f")
        if [ "$FORCE_REBUILD_LIFT" = "1" ] || [ ! -f "$o" ] || [ "$f" -nt "$o" ]; then
            echo "$f"
        fi
    done
} | xargs -P "$JOBS" -I {} sh -c \
    'src="$1"; ps3="$2"; opt="$3"
     if [ "$opt" = "-O0" ]; then o="$src.o"; else o="${src}.${opt#-O}.o"; fi
     clang++ -std=c++20 "$opt" -w -c -I . -I "$ps3/include" -I "$ps3/runtime/ppu" \
         "$src" -o "$o" 2> "$src.cclog"' \
    _ {} "$PS3" "$LIFT_OPT"
NOBJ=0
for f in ppu_recomp_*.cpp ppu_stubs.cpp; do
    [ -f "$f" ] || continue
    o=$(lift_obj "$f")
    [ -f "$o" ] && NOBJ=$((NOBJ + 1))
done
echo "  dur=$(( $(date +%s) - t0 ))s objs=$NOBJ errors=$(cat ./*.cclog 2>/dev/null | grep -c 'error:' || true)"

echo "=== 2. runtime PPU sources -> .o (HOST_OPT=$HOST_OPT) ==="
cd "$HERE"
for src in ppu_loader ppu_imports ppu_hle ppu_sysprx ppu_fs; do
    clang++ -std=c++20 $HOST_OPT -w -c "${INC[@]}" "$PS3/runtime/ppu/$src.cpp" -o "$LIFT/$src.o"
done
# host_gow2_factory: subsistema factory/TYPE15 extraido do lift para ficheiro
# versionado (games/gow2/host_gow2_factory.cpp, commit 1f651aa no irmao
# gow2-recomp; porte para o monorepo, criterio 3 do ROADMAP da Fase 2). O
# criterio 4 (um lift novo, sem patches, mais estas fontes versionadas, LINKA)
# ja' esta medido tres vezes e promovido a producao -- boot_gow2_v3/v4 linkaram
# e o lift regenerado deu st620=11 em 6/6 (gow2-recomp commit 57b418f,
# games/gow2/lift_baseline/counters_pre.tsv: boot_lifted_functions=56223,
# lift_function_table_count=56072, imp_modules=13, imp_imports=151,
# orfaos_pos_run=0). Esta task (02-03) NAO re-prova o criterio 4 (D-2.6,
# 02-CONTEXT.md) -- so' liga o mecanismo de compilacao condicional que ja'
# funcionou a esse lift.
# Compila-se SO' quando o lift NAO trouxer a definicao (corpo, chaveta) dentro
# dele -- o lift antigo tem-na escrita a mao, e linkar as duas dava "duplicate
# symbol". Um lift regenerado so' tem a declaracao (patch_zz_host_api_decls.py,
# que termina em `;`) e precisa deste objecto.
if [ -f "$HERE/host_gow2_factory.cpp" ]; then
    # Procura a DEFINICAO (corpo, chaveta) e nao o prototipo: o patch_zz injecta
    # `...(uint32_t obj);` no preambulo, e um grep que casasse com isso mandaria
    # saltar a compilacao mesmo sem definicao nenhuma -> undefined symbol.
    if grep -lq 'extern "C" int ps3_factory_repair_vt(uint32_t obj) *{' "$LIFT"/ppu_recomp_*.cpp 2>/dev/null; then
        echo "  host_gow2_factory: definicoes ja' no lift -- nao compilar (evita duplicate symbol)"
        rm -f "$LIFT/host_gow2_factory.o"
    else
        clang++ -std=c++20 $HOST_OPT -w -c "${INC[@]}" \
            "$HERE/host_gow2_factory.cpp" -o "$LIFT/host_gow2_factory.o"
        echo "  host_gow2_factory: compilado"
    fi
fi
# host_gow2_f2b: subsistema F2B (mapa file-object->mfd/tamanho + preenchimento
# de stream FIOS do movie player) extraido POR SIMBOLO (D-2.3/D-2.4,
# 02-CONTEXT.md) para games/gow2/host_gow2_f2b.c (plano 02-02). Mesma logica
# de guard anti-duplicate-symbol do host_gow2_factory acima, MAS com uma
# diferenca critica medida nesta sessao (02-03): dos 17 simbolos F2B, so' 2
# funcoes (f2b_stream_ensure, f2b_stream_eof_try_complete) tem linkagem
# EXTERNA (`extern "C"`) no lift de producao actual -- as outras 5 funcoes E
# os 10 globais sao `static` (linkagem INTERNA, ex.: `static void
# f2b_fo_mfd_put(...)`, `static uint32_t g_f2b_fo_mfd_fo[8];`). Um guard que
# so' detectasse a forma `extern "C" ... *{` (como o do factory acima) nunca
# apanharia um lift onde esses 5/10 simbolos `static` continuassem la' mas os
# 2 `extern` tivessem desaparecido: nesse caso NAO haveria "duplicate symbol"
# nenhum (linkagens diferentes nunca colidem no link), mas haveria ESTADO
# DUPLICADO EM SILENCIO -- o chunk continuaria a usar a sua copia `static`
# interna, e o host_gow2_f2b.o ficaria morto no binario, sem erro nenhum que
# avisasse. Por isso o guard abaixo tem TRES condicoes, nao uma: (1) a
# definicao do simbolo-ancora `f2b_stream_ensure` independentemente do prefixo
# de linkagem (static/extern "C"/nenhum -- so' a assinatura + chaveta de
# abertura, nunca o `;` do prototipo); (2) qualquer uma das 5 funcoes `static`
# conhecidas; (3) qualquer um dos 10 globais `static` conhecidos. Presente
# qualquer uma -> salta a compilacao (hoje, medido: as tres batem no lift de
# producao actual -- portanto NAO compila).
if [ -f "$HERE/host_gow2_f2b.c" ]; then
    if grep -Eq 'f2b_stream_ensure\(uint32_t type_sys\) *\{' "$LIFT"/ppu_recomp_*.cpp 2>/dev/null || \
       grep -Eq '^static .*\bf2b_(fo_mfd_put|fo_mfd_get|fo_sz_get|stream_fill|stream_pre_consume)\b' "$LIFT"/ppu_recomp_*.cpp 2>/dev/null || \
       grep -Eq '^static .*\bg_f2b_(fo_mfd_fo|fo_mfd_fd|fo_mfd_sz|fo_mfd_n|natural_movie_fo|fill_fo|fill_mfd|fill_sz|fill_file_pos|fill_stream)\b' "$LIFT"/ppu_recomp_*.cpp 2>/dev/null; then
        echo "  host_gow2_f2b: definicao (static ou extern) ja' no lift -- nao compilar (evita duplicate symbol OU estado duplicado em silencio)"
        rm -f "$LIFT/host_gow2_f2b.o"
    else
        clang -std=c11 $HOST_OPT -w -c "${INC[@]}" \
            "$HERE/host_gow2_f2b.c" -o "$LIFT/host_gow2_f2b.o"
        echo "  host_gow2_f2b: compilado"
    fi
fi
# gow2_midasm_hooks: corpos HOST dos mid-asm hooks da Fase 17 (XEN-02). Um
# [[midasm_hook]] no config/gow2_recomp.toml faz o ppu_lifter.py emitir
# `gow2_midasm_<Name>(ctx);` ao lado da instrucao ancorada (17-01); a definicao
# do simbolo vem deste objecto. No plano 17-02 os corpos sao NO-OP -- o que se
# liga aqui e' o caminho de link, nao comportamento.
#
# GUARD ANTI-DUPLICATE-SYMBOL -- porque nao e' o mesmo grep dos dois blocos
# acima. Duas diferencas MEDIDAS (2026-08-02), nao assumidas por analogia:
#
#  (1) O lifter emite, no PREAMBULO da TU gerada, uma DECLARACAO por hook:
#      `void gow2_midasm_<Name>(ppu_context* ctx);` (ppu_lifter.py,
#      _preamble_lines). Um guard que casasse com o nome do simbolo -- como
#      `grep -q gow2_midasm` -- passaria a saltar a compilacao assim que o
#      primeiro lift com --config existisse, e o link morreria em "undefined
#      symbol" sem ninguem perceber porque. O guard tem de casar com a
#      DEFINICAO (assinatura + chaveta), nunca com o prototipo nem com a
#      chamada `gow2_midasm_X(ctx);` (essa acaba em `;`).
#
#  (2) Licao do host_gow2_f2b (marco v1.0): 5 das 7 funcoes F2B eram `static`
#      no lift real, e um guard so'-`extern "C"` teria deixado ESTADO
#      DUPLICADO EM SILENCIO em vez de um erro de link. Por isso as duas
#      expressoes abaixo nao ancoram em prefixo de linkagem NENHUM: apanham
#      `static`, `extern "C"` ou nada. A segunda cobre a definicao com a
#      chaveta na linha seguinte (estilo de codigo host colado a mao; o lifter
#      poe sempre na mesma linha, mas o corpo do CE03C hoje e' texto injectado
#      por patch e nao tem de seguir o estilo do lifter).
#
# Estado medido do lift de producao nesta corrida: ZERO ocorrencias de
# gow2_midasm_ em recomp_macos_v2/ppu_recomp_*.cpp -- logo o guard nao dispara
# e o objecto e' compilado. E' isso que faz o `nm` do aceite XEN-02 ter algo
# para encontrar.
if [ -f "$HERE/hooks/gow2_midasm_hooks.cpp" ]; then
    _midasm_def_same_line='(^|[^A-Za-z0-9_])gow2_midasm_[A-Za-z0-9_]+[[:space:]]*\([^;]*\)[[:space:]]*\{'
    _midasm_def_next_line='(^|[^A-Za-z0-9_])gow2_midasm_[A-Za-z0-9_]+[[:space:]]*\([^;]*\)[[:space:]]*$'
    if grep -Eq "$_midasm_def_same_line" "$LIFT"/ppu_recomp_*.cpp 2>/dev/null || \
       grep -Eq "$_midasm_def_next_line" "$LIFT"/ppu_recomp_*.cpp 2>/dev/null; then
        echo "  gow2_midasm_hooks: DEFINICAO (static ou extern) ja' no lift -- nao compilar"
        echo "                     (evita duplicate symbol OU estado duplicado em silencio)"
        rm -f "$LIFT/gow2_midasm_hooks.o"
    else
        clang++ -std=c++20 $HOST_OPT -w -c "${INC[@]}" -I "$HERE/hooks" \
            "$HERE/hooks/gow2_midasm_hooks.cpp" -o "$LIFT/gow2_midasm_hooks.o"
        echo "  gow2_midasm_hooks: compilado"
    fi
fi
# host_res_inflate: runtime/ppu is excluded from libps3recomp_runtime.a (same as
# ppu_loader). Required for EBOOT gzip HOSTRES (gowshader.cfx, *.ctxr) after
# patch_host_res_inflate.py hooks func_001E7B50. Uses rsx_host_content + stbi
# from the runtime .a — portable Mac/Win.
if [ -f "$PS3/runtime/ppu/host_res_inflate.c" ]; then
    clang -std=c11 $HOST_OPT -w -c "${INC[@]}" -I "$PS3/libs/video" \
        "$PS3/runtime/ppu/host_res_inflate.c" -o "$LIFT/host_res_inflate.o"
fi
# WAD ~texture packages after WADLD-T1R (patch_wad_tex_capture → force-bind).
if [ -f "$PS3/runtime/ppu/host_wad_tex.c" ]; then
    clang -std=c11 $HOST_OPT -w -c "${INC[@]}" -I "$PS3/libs/video" \
        "$PS3/runtime/ppu/host_wad_tex.c" -o "$LIFT/host_wad_tex.o"
fi

echo "=== 3. HLE NID table -> .o ==="
# ppu_hle_register_all() is a weak no-op in the runtime; without a strong
# override every firmware call the game makes logs "unresolved NID" and returns
# nothing. Regenerated from the /* NID */ annotations in the HLE sources.
mkdir -p "$LIFT/gen"
# Espelha a exclusao do CMakeLists do motor: sceNpCommerce.c colide com
# sceNpCommerce2.c e ficou fora da biblioteca (ver o comentario la para o que
# se perde). O gerador varre o disco, nao o que o CMake compila, entao tem de
# saltar o ficheiro tambem -- senao declara simbolos que nao existem na .a.
LIBS=$(ls "$PS3"/libs/*/*.c | xargs -n1 basename | sed 's/\.c$//' | sort -u \
       | grep -vx 'sceNpCommerce')
# shellcheck disable=SC2086
"$PS3/.venv/bin/python" "$PS3/tools/gen_hle_nids.py" \
    --out "$LIFT/gen/ppu_hle_nids.cpp" $LIBS > /dev/null
clang++ -std=c++20 $HOST_OPT -w -c "${INC[@]}" -I "$PS3/libs" "$LIFT/gen/ppu_hle_nids.cpp" -o "$LIFT/ppu_hle_nids.o"

echo "=== 3b. imagens SPU liftadas do GoW2 -> .o ==="
# spu_lifted/spu{0..3}_v2 ja vem com simbolos prefixados (spu0_, spu1_, ...),
# logo os quatro coexistem no mesmo binario. gow2_spu_register.c regista-os no
# dispatcher por fingerprint; spu0 entra sempre, spu1/2/3 sao opt-in por env
# (PS3_SPU1/2/3, PS3_SPU_ALL).
#
# Cuidado herdado do Windows: o comentario do gow2_spu_register.c diz que um job
# que rebenta mata so a thread "gracas a SEH isolation" -- isso e Windows. Aqui a
# proteccao e o setjmp/longjmp do spu_lifted_job.h do master, que apanha a saida
# do job mas NAO um SIGBUS/SIGSEGV: um job que falta leva o processo inteiro.
# E por isso que spu1/2/3 continuam opt-in.
SPU_OBJS=()
for d in "$HERE"/spu_lifted/spu?_v2; do
    [ -f "$d/spu_recomp.c" ] || continue
    n=$(basename "$d")
    o="$LIFT/${n}_spu_recomp.o"
    if [ ! -f "$o" ] || [ "$d/spu_recomp.c" -nt "$o" ]; then
        clang -std=c11 -O1 -w -c -I "$d" -I "$PS3/runtime/spu" -I "$PS3/include" \
              "$d/spu_recomp.c" -o "$o"
    fi
    SPU_OBJS+=("$o")
done
if [ ${#SPU_OBJS[@]} -gt 0 ]; then
    clang -std=c11 -O1 -w -c -I "$PS3/runtime/spu" -I "$PS3/include" \
          "$HERE/recomp_mid_v2/gow2_spu_register.c" -o "$LIFT/gow2_spu_register.o"
    SPU_OBJS+=("$LIFT/gow2_spu_register.o")
fi
echo "  imagens SPU: ${#SPU_OBJS[@]} objecto(s)"

echo "=== 4. boot host -> .o ==="
clang++ -std=c++20 $HOST_OPT -w -c "${INC[@]}" "$HERE/boot_macos.cpp" -o "$LIFT/boot_macos.o"
# Amostrador do movie player ([MOVIEFSM]), gated por PS3_TRACE_MOVIEOBJ /
# PS3_MOVIE_EOS / PS3_PERF_FSM. C puro e portatil de proposito.
clang -std=c11 $HOST_OPT -w -c -I "$HERE" "$HERE/movie_eos_arm.c" -o "$LIFT/movie_eos_arm.o"

echo "=== 5. link ==="
SDL_FLAGS=$(pkg-config --libs sdl2)
VK_FLAGS=""
if [ -f /opt/homebrew/lib/libvulkan.dylib ]; then
    VK_FLAGS="-L/opt/homebrew/lib -lvulkan"
fi

# Collect lift objects matching this LIFT_OPT (bare .o for -O0, .1.o for -O1, ...)
LIFT_OBJS=()
for f in "$LIFT"/ppu_recomp_*.cpp "$LIFT"/ppu_stubs.cpp; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    if [ "$LIFT_OPT" = "-O0" ]; then
        LIFT_OBJS+=("$LIFT/$base.o")
    else
        LIFT_OBJS+=("$LIFT/${base}.${LIFT_OPT#-O}.o")
    fi
done

# The guest's CRT recurses deeply under -O0; the default 8 MB main-thread stack
# is not enough. Windows uses -Wl,--stack,33554432 for the same reason.
# NB (Task 5, macos-movie-eos plan): 0x2000000 (32 MB) is NOT bumped for the
# "SIGBUS after recursion cap @0x0045CB90". That was diagnosed as a host stack
# overflow, but PS3_TRACE_HOST_STACK=1 measures the capped depth-4000 recursion
# using only ~2 MB of host stack (~514 B/level) -- 32 MB is never threatened.
# The real SIGBUS is the cap's skip returning a corrupt result (r3=0x84010002,
# an unmapped guest EA) that the caller derefs; the committed bctr-tail fix
# already keeps that poll from reaching the cap. See runtime/ppu/ppu_loader.cpp.
clang++ -std=c++20 $HOST_OPT \
    "${LIFT_OBJS[@]}" \
    "$LIFT"/ppu_loader.o "$LIFT"/ppu_imports.o "$LIFT"/ppu_hle.o \
    "$LIFT"/ppu_sysprx.o "$LIFT"/ppu_fs.o \
    $([ -f "$LIFT/host_gow2_factory.o" ] && echo "$LIFT/host_gow2_factory.o") \
    $([ -f "$LIFT/host_gow2_f2b.o" ] && echo "$LIFT/host_gow2_f2b.o") \
    $([ -f "$LIFT/gow2_midasm_hooks.o" ] && echo "$LIFT/gow2_midasm_hooks.o") \
    $([ -f "$LIFT/host_res_inflate.o" ] && echo "$LIFT/host_res_inflate.o") \
    $([ -f "$LIFT/host_wad_tex.o" ] && echo "$LIFT/host_wad_tex.o") \
    "$LIFT"/ppu_hle_nids.o "$LIFT"/boot_macos.o "$LIFT"/movie_eos_arm.o \
    ${SPU_OBJS[@]+"${SPU_OBJS[@]}"} \
    "$RUNTIME_LIB" \
    -framework Metal -framework MetalFX -framework QuartzCore -framework Foundation \
    -framework Cocoa \
    -framework AVFoundation -framework CoreMedia -framework CoreVideo \
    -framework AudioToolbox -framework CoreAudio \
    -framework GameController -framework CoreHaptics \
    $SDL_FLAGS $VK_FLAGS -lm \
    -Wl,-stack_size,0x2000000 \
    -o "$OUT"

echo
ls -lh "$OUT"
echo "*** $OUT built (LIFT_OPT=$LIFT_OPT HOST_OPT=$HOST_OPT) ***"
echo
echo "run it with:  ./rodar_gow2.sh"
