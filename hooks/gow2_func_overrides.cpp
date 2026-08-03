/* gow2_func_overrides.cpp -- corpos dos WEAK OVERRIDES host do GoW2.
 *
 * Ver o cabecalho de gow2_func_overrides.h para o contrato do simbolo, para a
 * diferenca face ao mid-asm da Fase 17 e para a razao de a macro
 * GOW2_FUNC_OVERRIDE nao ser cosmetica.
 *
 * ESTADO NESTE PLANO (19-03): O PILOTO DE IDENTIDADE + DUAS MIGRACOES REAIS.
 * --------------------------------------------------------------------------
 * O 19-01 mediu OFFLINE que o mecanismo funciona (nm -m + execucao real de um
 * binario ligado com override). O 19-02 ligou a ponta HOST: TU versionada,
 * compilada e ligada pelo build_macos.sh, e provou IN-BOOT que o override que
 * ganha o link e' este ficheiro e nao o wrapper fraco do lift -- com um
 * override de IDENTIDADE sobre `func_00010230` (o entry point do guest), que
 * continua ca' em baixo e continua a ser o sensor do caminho de link.
 *
 * Este plano (19-03) acrescenta COMPORTAMENTO, e so' o que o mecanismo weak e'
 * o unico a poder fazer:
 *
 *   func_000CE03C  pad de setjmp/longjmp do CE03C (WINDOWS.md #8). ENVOLVE o
 *                  corpo natural -- um [[midasm_hook]] corre AO LADO de uma
 *                  instrucao e nao pode envolver nada.
 *   func_0002F3F0  bounds-check do hash de nomes do registry 393E0. Precisa de
 *                  um RETURN ANTECIPADO (e de um tecto no numero de bytes
 *                  lidos) -- outra coisa que um mid-asm nao faz.
 *
 * PORQUE `func_00010230` E NAO OUTRA (escolha medida, nao gosto)
 * -------------------------------------------------------------
 *  - E' o ENTRY POINT do guest: a EBOOT.ELF tem `entry OPD 0x00519570`, que
 *    resolve para code=0x00010230 (lido do proprio ELF nesta sessao; o
 *    runtime/ppu/ppu_loader.cpp ja' lhe chama "the literal entry point
 *    0x00010230"). Logo e' chamada EXACTAMENTE UMA VEZ, e sempre -- se o boot
 *    arranca, o override correu. Nenhuma outra candidata da' essa garantia sem
 *    depender do caminho da intro.
 *  - `ppu_run` chama-a pela `function_table` (ppu_loader.cpp: resolve o OPD,
 *    procura o code addr na tabela, chama `fn`). E' o cenario L4 do 19-01 --
 *    o mais arriscado, porque a referencia esta' na MESMA TU do wrapper fraco
 *    e o compilador poderia curto-circuitar. Medido verde la', e aqui e' o
 *    caminho REAL do jogo, nao um teste.
 *  - E' inicio de funcao liftada e tem tamanho EXACTO conhecido:
 *    functions.json diz start=0x00010230 end=0x00010254 -> size 0x24. O
 *    `size` do TOML nao e' aproximado (o campo e' registado e nao consumido --
 *    19-01 -- mas escreve-se o numero verdadeiro).
 *  - NENHUM patch_*.py lhe toca (verificado por grep sobre os 140 patches: a
 *    unica ocorrencia de 00010230 e' um COMENTARIO de cadeia de chamadas em
 *    patch_introseq_probe.py). Um piloto patchado partiria o
 *    apply_all_patches.sh, porque com a emissao ligada a forma
 *    `void func_XXXXXXXX(ppu_context* ctx) {` deixa de existir no lift para a
 *    funcao declarada (passa a `PPC_FUNC_IMPL(...)`), e um patch que a procure
 *    por texto nao a encontra.
 *  - Uma vez por boot = custo zero. O 19-01 mediu que a -O0 (o default do
 *    build) o wrapper e' um `bl` real; num piloto chamado por frame isso seria
 *    ruido no smoke de perf.
 *
 * PORTABILIDADE (G4 -- Windows nao regride): zero tokens Win32. Este ficheiro
 * so' e' compilado pelo build_macos.sh; o build_d3d.sh nao o toca.
 */
#include "gow2_func_overrides.h"

#include "ppu_memory.h"   /* vm_read8 / vm_read32 / vm_write32 / vm_write8 */

#include <setjmp.h>       /* setjmp / jmp_buf -- o pad do CE03C (ver abaixo) */

#include <cstdio>
#include <cstdlib>

/* ---------------------------------------------------------------------------
 * Dependencias do runtime e do lift.
 *
 * Mesmo arranjo do gow2_midasm_hooks.cpp: nenhuma destas entidades tem header
 * publico no motor (o proprio ppu_loader.cpp e varios syscalls declaram-nas
 * localmente com `extern`), por isso sao declaradas aqui.
 * ------------------------------------------------------------------------ */
extern "C" {

/* Alvo do longjmp do pad do CE03C. Definido em runtime/ppu/ppu_loader.cpp
 * (`extern "C" void* g_ce03c_play_abort = nullptr;`) e disparado de dentro de
 * `ps3_indirect_call`, no ramo [ICALL-ASCII], quando o FO residual fica preso
 * a saltar para uma string depois do StartSeq#2 real:
 *     longjmp(*(jmp_buf*)g_ce03c_play_abort, 1);
 * Enquanto ninguem o armar vale NULL e o ramo nunca dispara. */
extern void* g_ce03c_play_abort;

/* Estado do movie player HLE: EA do hook de EOS sticky. */
extern uint32_t g_movie_eos_ea;

/* libs/codec/cellVdec.c -- para o ramo de abort: para os drivers async para o
 * PICOUT nao continuar a bater no path-as-code sob o giant lock. */
void cellVdec_stop_all_for_play_abort(void);

} /* extern "C" */

/* Cross-fragment trampoline pointer -- a MESMA declaracao que o ppu_lifter.py
 * escreve no preambulo de toda a TU liftada e que casa com a definicao do
 * runtime/ppu/ppu_loader.cpp. Em Apple TEM de ser `thread_local` do C++ (ver a
 * nota longa no gow2_midasm_hooks.cpp: um `extern "C" __thread` nao pede o
 * wrapper TLS do Itanium e o link morre). */
#if defined(_MSC_VER)
extern "C" __declspec(thread) void (*g_trampoline_fn)(void*);
#elif defined(__APPLE__)
extern "C" thread_local void (*g_trampoline_fn)(void*);
#else
extern "C" __thread void (*g_trampoline_fn)(void*);
#endif

/* Funcao liftada do guest, com linkagem C++ (o lifter emite-as sem extern "C").
 * E' o alvo do trampolim que o CE03C arma na cauda. */
void func_000CE01C(ppu_context* ctx);

/* Corpo liftado original do entry point. Declarado, nao definido: a definicao
 * (`PPC_FUNC_IMPL(func_00010230)`) vem do chunk liftado. Se o lift for gerado
 * SEM a emissao ligada, este simbolo nao existe e o link parte alto -- e o
 * guard do build_macos.sh trata desse caso ANTES, saltando a compilacao. */
PPC_FUNC_IMPL_DECL(func_00010230);

/* Probe gated por env var, OFF por omissao (regra 6 do CLAUDE.md): com
 * PS3_FUNCOVR_TRACE ausente/vazio/"0" este ficheiro e' um no-op exacto sobre o
 * baseline. Ligado, imprime a prova IN-BOOT de que quem correu foi o override
 * host e nao o wrapper fraco do lift -- a string nao existe em lift nenhum. */
static bool gow2_funcovr_trace(void)
{
    static int on = -1;
    if (on < 0) {
        const char* e = getenv("PS3_FUNCOVR_TRACE");
        on = (e && e[0] && e[0] != '0') ? 1 : 0;
    }
    return on != 0;
}

/* ---------------------------------------------------------------------------
 * func_00010230 -- entry point do guest (EA 0x00010230, size 0x24).
 *
 * PILOTO DA FASE 19 (plano 19-02). Override de IDENTIDADE: o unico efeito com
 * o probe desligado e' um `bl` a mais para o corpo original. Nao le nem escreve
 * um so' campo de `ctx` -- de proposito: assim o override nao depende de o
 * layout do `ppu_context` do motor casar com o do lift (casam, verificado no
 * 17-02, mas nao depender e' mais barato do que voltar a prova-lo).
 * ------------------------------------------------------------------------ */
GOW2_FUNC_OVERRIDE(func_00010230)
{
    if (gow2_funcovr_trace()) {
        static int n = 0;
        if (n++ < 4) {
            fprintf(stderr,
                    "[FUNCOVR] func_00010230 (guest entry) -- override HOST "
                    "activo, chamada #%d\n", n);
            fflush(stderr);
        }
    }
    __imp_func_00010230(ctx);
}

/* ===========================================================================
 * func_000CE03C -- pad de setjmp/longjmp do CE03C (WINDOWS.md #8)
 *
 * A LACUNA QUE ISTO FECHA
 * -----------------------
 * O `patch_ce03c_introseq_block.py` instalava 116 linhas dentro do lift
 * gitignored. A Fase 17 migrou a PRIMEIRA metade -- o wait-idle -- para o
 * [[midasm_hook]] `Ce03cWaitIdle`, e declarou (17-03-SUMMARY, WINDOWS #8) que
 * a SEGUNDA metade nao cabia nesse mecanismo: o patch tambem ENVOLVIA o corpo
 * natural num `setjmp`, com um ramo de abort que chama
 * `cellVdec_stop_all_for_play_abort()` e reconstroi a freelist do media
 * object. Um `[[midasm_hook]]` corre AO LADO de uma instrucao; nao envolve
 * nada. Resultado medido: um lift feito com `--config` tinha o wait-idle e NAO
 * tinha o pad -- e nenhum script o repunha.
 *
 * O weak override e' o mecanismo que envolve. Daqui em diante o pad e' codigo
 * host versionado e sobrevive ao re-lift.
 *
 * ENVOLVER, NAO SUBSTITUIR (e porque e' esta a escolha)
 * ----------------------------------------------------
 * O corpo natural NAO e' copiado para aqui: chama-se `__imp_func_000CE03C`,
 * que e' o corpo que o lifter acabou de gerar -- e que ja' traz la' dentro,
 * como primeira instrucao, a chamada `gow2_midasm_Ce03cWaitIdle(ctx)` emitida
 * pelo [[midasm_hook]] da Fase 17. Isto tem duas consequencias que se querem:
 *
 *   1) UMA SO' FONTE DE VERDADE PARA O WAIT-IDLE. O override NAO chama
 *      gow2_midasm_Ce03cWaitIdle -- se o chamasse haveria DOIS pumps por
 *      entrada no CE03C (o do hook dentro do __imp_ e o do override), e o
 *      wait-idle nao e' idempotente: cada um esperaria ate' 600 ciclos de
 *      50 ms. Os dois mecanismos COMPOEM-SE; nao se duplicam.
 *   2) RE-LIFT-SAFE DE VERDADE. Se o lifter melhorar a traducao das 20
 *      instrucoes do corpo natural, o proximo lift traz a versao nova sem
 *      ninguem tocar neste ficheiro. Copiar o corpo para ca' (substituicao
 *      total) congelava-o -- exactamente o defeito que o patch tinha.
 *
 * A CAUDA, E PORQUE ELA E' REPETIDA NO RAMO DE ABORT
 * -------------------------------------------------
 * O corpo liftado termina com a cauda
 *     r9 = *(u32*)r30; r9 += 1; *(u32*)r30 = r9;
 *     g_trampoline_fn = func_000CE01C; return;
 * No caminho NORMAL essa cauda corre dentro do `__imp_` -- nada a fazer. No
 * caminho de ABORT o `longjmp` salta-a, e o bloco injectado corria-a na mesma
 * (esta a seguir ao pad, nao dentro dele). Por isso o ramo `else` repete-a
 * aqui, verbatim. Sem isto, um abort deixaria o contador por incrementar e o
 * trampolim por armar -- uma divergencia silenciosa face ao patch migrado.
 *
 * DIVERGENCIA DECLARADA (uma, e medida)
 * -------------------------------------
 * O bloco injectado forcava `r30 = _sv_r30` tambem no caminho NORMAL, imediata-
 * mente antes da cauda. Aqui isso e' inalcancavel: a cauda vive dentro do
 * `__imp_`. Nao e' regressao desta fase -- e' o comportamento que o lift
 * `--config` ja' tem desde o 17-03 (o pad nunca la' esteve) e cujo smoke esta'
 * medido verde nas Fases 17, 18 e 19-02 (st620_max=11). r30 e' callee-saved na
 * ABI PPC, portanto as tres chamadas guest do corpo natural tem de o repor.
 * No ramo de ABORT -- onde a ABI foi violada por um salto nao-local -- o
 * restauro E' feito, como o patch fazia.
 *
 * SEGUNDA DIFERENCA, TAMBEM DELIBERADA: o `_sv_r2` do bloco injectado era
 * capturado DEPOIS do wait-idle (o pad vinha a seguir a ele), e o hook mid-asm
 * deixa r2 "como o pump o devolveu" -- por escolha declarada no 17-03. Aqui e'
 * capturado A' ENTRADA, antes de tudo. Onde os dois divergiriam e' se o pump
 * sujasse o TOC; nesse caso o valor certo e' o da entrada, nao o sujo. Na
 * pratica sao iguais (o lifter resolve o TOC estaticamente -- o carimbo TOCFIX
 * que ele emite a seguir a cada chamada indirecta), mas a
 * escolha e' a que fica correcta se um dia deixarem de ser.
 * ======================================================================== */
PPC_FUNC_IMPL_DECL(func_000CE03C);

GOW2_FUNC_OVERRIDE(func_000CE03C)
{
    const uint64_t sv_r30 = ctx->gpr[30];
    const uint64_t sv_r2 = ctx->gpr[2];   /* o hang do FO pode sujar o TOC */

    jmp_buf jb;
    g_ce03c_play_abort = (void*)&jb;

    if (setjmp(jb) == 0) {
        /* Corpo natural do guest, tal como o lifter o gerou -- incluindo a
         * chamada ao mid-asm Ce03cWaitIdle na primeira linha e a cauda. */
        __imp_func_000CE03C(ctx);
    } else {
        /* Residual do FO depois do StartSeq#2 real: ps3_indirect_call ficou
         * preso a saltar para uma string e deu longjmp para ca'. */
        { static int n = 0; if (n++ < 4)
            fprintf(stderr, "[INTROSEQ] CE03C Play aborted "
                            "(FO residual after StartSeq#2)\n"); }
        g_trampoline_fn = 0;
        ctx->gpr[2] = sv_r2;   /* repor o TOC antes de tocar em memoria guest */

        cellVdec_stop_all_for_play_abort();

        /* O abort na pilha do host deixou o guest a meio do Play: parquear o
         * player e re-semear a freelist do media object, senao o open do WAD
         * a seguir a' intro bate no FREELIST-TAG-GUARD. */
        {
            const uint32_t toc = (uint32_t)sv_r2;
            const uint32_t mv = (toc >= 0x1124u)
                                    ? vm_read32(toc - 0x1124u) : 0u;
            if (mv >= 0x10000u && mv < 0x4F000000u) {
                vm_write32(mv + 0x620u, 0u);
                vm_write8(mv + 0x744u, 0);
                vm_write8(mv + 0x745u, 0);
                vm_write8(mv + 0x746u, 0);
            }
            g_movie_eos_ea = 0u;

            const uint32_t slot = (toc >= 0x1460u)
                                      ? vm_read32(toc - 0x1460u) : 0u;
            const uint32_t media = (slot && slot < 0x4F000000u)
                                       ? vm_read32(slot + 0x118u) : 0u;
            if (media >= 0x10000u && media < 0x4F000000u) {
                if (vm_read32(media + 0x16Cu) == 0u)
                    vm_write32(media + 0x16Cu, 1u);
                const uint32_t offs[8] = { 0x250u, 0x330u, 0x410u, 0x4F0u,
                                           0x5D0u, 0x6B0u, 0x790u, 0x870u };
                uint32_t chain = 0;
                for (int i = 7; i >= 0; i--) {
                    const uint32_t op = media + offs[i];
                    if (op >= 0x4F000000u) continue;
                    vm_write32(op + 0x0u, chain);
                    vm_write32(op + 0x90u, 0u);
                    vm_write32(op + 0x40u, 0u);
                    vm_write32(op + 0x44u, 0u);
                    chain = op;
                }
                vm_write32(media + 0x200u, chain);
                vm_write32(media + 0x218u, 0u);
                fprintf(stderr, "[INTROSEQ] CE03C post-abort freelist rebuild "
                                "media=0x%08X\n", media);
                fflush(stderr);
            } else {
                fprintf(stderr, "[INTROSEQ] CE03C post-abort freelist SKIP "
                                "toc=0x%08X media=0x%08X\n", toc, media);
                fflush(stderr);
            }
        }

        /* A cauda do corpo natural, que o longjmp saltou (ver acima). */
        ctx->gpr[30] = sv_r30;
        ctx->gpr[9] = vm_read32((uint32_t)ctx->gpr[30] + 0x0u);
        ctx->gpr[9] = ctx->gpr[9] + (int64_t)(1);
        vm_write32((uint32_t)ctx->gpr[30] + 0x0u, (uint32_t)ctx->gpr[9]);
        g_trampoline_fn = (void (*)(void*))func_000CE01C;
    }

    g_ce03c_play_abort = 0;
    ctx->gpr[2] = sv_r2;
}
