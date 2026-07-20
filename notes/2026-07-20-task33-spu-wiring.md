# Task 3.3 — ligacao das imagens SPU do GoW2 (PARQUEADO)

Feito e revertido em 2026-07-20. **Nao esta no `build_macos.sh`** porque nao
funciona com o runtime SPU desta branch. Fica aqui para nao ser reescrito.

## Porque esta parqueado

`spu_lifted/spu{0..3}_v2/` foi gerado por um `spu_lifter.py` mais novo, do
`origin/master`. Esse output referencia `g_spu_trampoline_fn` e `SPU_DRAIN`, que
**nao existem** em lado nenhum desta branch (saida de `spurs-bringup`).

Portar os tres ficheiros do runtime SPU do master (`spu_context.h`,
`spu_channels.c`, `spu_lifted_job.h`, 241 linhas) resolve a compilacao **mas
muda a ABI da task SPU**, e o proprio master documenta porque:

> "(Two earlier attempts -- arg EA as a pointer in r3, then the words spread
> across r3..r6 -- left the base registers zero and sent the task into base-0
> DMA loops.)"

`r3` deixou de ser o EA do argumento e passou a ser o `CellSpursTaskArgument` de
128 bits carregado inteiro. Isso invalida, nesta branch:

| O que | Porque |
|---|---|
| `test_adapter`, `test_workload` | passam `args_ea` esperando `r3 = EA` (SIGBUS / assert) |
| `libs/spurs/spurs_kernel.c` | `gpr[3]._u32[0] = wl->args_ea` (Task 2.2) |
| `gen_test_spurs_{job_dma,completion,printf}.py` | os tres fazem `ai r10, r3, 0` |

Ou seja: a Phase 2 inteira foi construida sobre a convencao **antiga**, que o
master ja descobriu estar errada. Os testes passam por serem consistentes entre
si, nao por a convencao estar certa.

**Desbloqueia com:** rebase dos commits macOS em `origin/master` (83 commits a
frente), depois adaptar o kernel e os tres geradores a nova ABI, e so entao
aplicar o patch abaixo.

## O patch (para `build_macos.sh`)

Entre a etapa 3 (tabela de NIDs) e a 4 (boot host):

```bash
echo "=== 3b. imagens SPU liftadas do GoW2 -> .o ==="
# spu_lifted/spu{0..3}_v2 ja vem com simbolos prefixados (spu0_, spu1_, ...),
# logo os quatro coexistem no mesmo binario. gow2_spu_register.c regista-os no
# dispatcher por fingerprint; spu0 entra sempre, spu1/2/3 sao opt-in por env
# (PS3_SPU1/2/3, PS3_SPU_ALL).
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
```

E no link, a seguir a `boot_macos.o`:

```bash
    ${SPU_OBJS[@]+"${SPU_OBJS[@]}"} \
```

## Aviso separado, valido ja hoje

O comentario em `recomp_mid_v2/gow2_spu_register.c` diz que um job que rebenta
mata so a thread, gracas a "SEH isolation in spu_workload.c". **Isso e Windows.**
Nesta branch nao ha `__try` nem guarda nenhuma no `spu_workload.c` -- verificado
por grep. No macOS um job que falta leva o processo inteiro. O `spu_lifted_job.h`
do master usa `setjmp`/`longjmp`, que e portavel; mais um motivo para o rebase.
