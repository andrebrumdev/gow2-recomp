/* gow2_midasm_hooks.cpp -- corpos dos mid-asm hooks HOST do GoW2.
 *
 * Ver o cabecalho de gow2_midasm_hooks.h para o contrato do simbolo e para a
 * razao de este ficheiro existir.
 *
 * ESTADO NESTE PLANO (17-03): O PILOTO CE03C TEM CORPO REAL.
 * ----------------------------------------------------------
 * O 17-01 poe o lifter a emitir a chamada, o 17-02 provou que o simbolo
 * RESOLVE no boot_gow2 (nm -> T) com corpo no-op, e este plano poe ca' dentro
 * o bloco que ate' agora era TEXTO INJECTADO por
 * recomp_mid_v2/patch_ce03c_introseq_block.py dentro do lift gitignored.
 *
 * O principio G2 do marco (probes OFF por default = zero mudanca de
 * comportamento) continua a exigir que TODO o hook declarado no TOML tenha
 * corpo, mesmo o nao implementado: sem stub, declarar um hook da' erro de LINK
 * em vez do no-op que se pediu. Regra pratica para quem mexer nisto: uma
 * entrada [[midasm_hook]] nova no games/gow2/config/gow2_recomp.toml sem corpo
 * aqui parte o link -- e' o comportamento desejado (falha alto, nao em
 * silencio), mas o corpo deve entrar no mesmo commit que a entrada do TOML.
 *
 * PORTABILIDADE (G4 -- Windows nao regride): zero tokens Win32 fora de
 * #ifdef _WIN32 -- e nem sequer os NOMES dessa lista aparecem aqui, para um
 * grep de auditoria do G4 sobre este ficheiro sair vazio em vez de sair a
 * apontar para um comentario. A lista vive no CLAUDE.md da raiz.
 *
 * A espera do pump usa `usleep`, como o bloco original. A alternativa portatil
 * `std::this_thread::sleep_for` foi TENTADA e NAO compila neste TU: o
 * ppu_memory.h inclui <stdatomic.h> e o libc++ recusa <atomic> (que <thread> e
 * <chrono> arrastam) depois de <stdatomic.h> antes de C++23 -- erro medido, nao
 * suposto. Ficou <unistd.h>: hoje este ficheiro so' e' compilado pelo
 * build_macos.sh (o build_d3d.sh do Windows nao o toca), e se alguem o
 * acrescentar la' o erro sera' alto e imediato em vez de silencioso.
 */
#include "gow2_midasm_hooks.h"

#include "ppu_memory.h"   /* vm_read32 / vm_write32 / vm_write8 (static inline) */

#include <unistd.h>       /* usleep -- ver a nota de portabilidade acima */

#include <cstdint>
#include <cstdio>

/* GOW2_MIDASM_USED: impede que um linker com dead-strip agressivo deixe cair
 * um hook que ainda nenhum lift chama -- e' exactamente o caso de um lift de
 * producao que ainda nao foi regenerado com --config. Verificado por leitura
 * da linha de link do build_macos.sh: nao passa -dead_strip. O contrafactual
 * (linkar SEM o atributo) NAO foi corrido, por isso o que prova o aceite e' o
 * `nm` registado no SUMMARY, nao esta linha -- o atributo e' cinto e
 * suspensorios. Fora de GCC/clang (ex.: MSVC) expande para nada, para nao
 * partir o Windows. */
#if defined(__GNUC__) || defined(__clang__)
#  define GOW2_MIDASM_USED __attribute__((used))
#else
#  define GOW2_MIDASM_USED
#endif

/* ---------------------------------------------------------------------------
 * Dependencias do runtime e do lift.
 *
 * Nenhuma destas entidades tem header publico no motor (o proprio ppu_loader e
 * varios syscalls declaram-nas localmente com `extern`), por isso sao
 * declaradas aqui -- e' o padrao ja' estabelecido no repositorio, nao uma
 * invencao deste ficheiro.
 * ------------------------------------------------------------------------ */
extern "C" {

/* Giant lock do interpretador PPU. O corpo de uma funcao liftada corre com ele
 * TOMADO; o pump ca' em baixo larga-o durante a espera para nao congelar as
 * mediathreads do FIOS -- exactamente como o bloco original fazia. */
void ppu_giant_lock_acquire(void);
void ppu_giant_lock_release(void);

/* Estado do movie player HLE (libs/video + runtime): EA do hook de EOS sticky,
 * limpeza do overlay do VideoToolbox e reset do temporizador de "done". */
extern uint32_t g_movie_eos_ea;
void movie_vt_clear_overlay_done(void);
void movie_done_timebased_reset(void);

} /* extern "C" */

/* Cross-fragment trampoline pointer -- a MESMA declaracao que o ppu_lifter.py
 * escreve no preambulo de toda a TU liftada (ppu_lifter.py, bloco
 * DRAIN_TRAMPOLINE) e que casa com a definicao do runtime/ppu/ppu_loader.cpp.
 * Em Apple TEM de ser `thread_local` do C++: um `extern "C" __thread` nao pede
 * o wrapper TLS do Itanium (__ZTW...) que as TUs C++ resolvem, e o link
 * morreria em "thread-local wrapper routine for g_trampoline_fn". */
#if defined(_MSC_VER)
extern "C" __declspec(thread) void (*g_trampoline_fn)(void*);
#elif defined(__APPLE__)
extern "C" thread_local void (*g_trampoline_fn)(void*);
#else
extern "C" __thread void (*g_trampoline_fn)(void*);
#endif

/* Funcao liftada do guest: o pump do movie player. Chamar o CODIGO DO PROPRIO
 * JOGO (e nao simular o que ele faz) e' a regra do CLAUDE.md para HLE fiel, e
 * era ja' o que o bloco injectado fazia.
 *
 * LIGACAO: as funcoes liftadas sao emitidas com linkagem C++ (ppu_recomp.h
 * declara `void func_XXXXXXXX(ppu_context* ctx);` sem extern "C"), portanto o
 * simbolo leva o nome do TIPO: __Z13func_002C0508P11ppu_context -- medido com
 * `nm boot_gow2`. Como o typedef do motor e o do lift partilham o MESMO tag
 * `ppu_context`, a decoracao gerada aqui e' identica byte-a-byte a' do chunk
 * liftado. Se um dia os tags divergirem, isto falha no LINK (undefined
 * symbol), que e' a falha alta desejavel -- nunca em silencio. */
void func_002C0508(ppu_context* ctx);

/* Drena os trampolins pendentes depois de uma chamada que possa te-los armado.
 * Replica o macro DRAIN_TRAMPOLINE do preambulo do lift; e' funcao em vez de
 * macro porque aqui nao ha' `ctx` implicito nenhum a esconder. */
static inline void gow2_drain_trampoline(ppu_context* ctx)
{
    while (g_trampoline_fn) {
        void (*tf)(void*) = g_trampoline_fn;
        g_trampoline_fn = 0;
        tf((void*)ctx);
    }
}

/* Guest EA valido para leitura/escrita do movie object. Os mesmos limites do
 * bloco original (o topo de 0x4F000000 e' o do heap do jogo). */
static inline bool gow2_ea_ok(uint32_t ea)
{
    return ea >= 0x10000u && ea < 0x4F000000u;
}

extern "C" {

/* ---------------------------------------------------------------------------
 * Ce03cWaitIdle -- piloto da Fase 17. EA guest 0x000CE03C, hook ANTES da
 * primeira instrucao de func_000CE03C (after_instruction ausente = default).
 *
 * O QUE FAZ (comentario do bloco original, preservado):
 *   Intro idx->2 natural 2nd Play (guest already calls Play here).
 *   Wait-idle only: CE03C often races while st620 != 0 -> SAI CEDO.
 *   Pump until natural MovieStop (st=0); arm +0x714 at st>=10 for EOS.
 *   Clear sticky EOS hook + done timer so re-Play is not poisoned.
 *   No soft-clear/soft-park of st620 (not a pass path). No inject.
 *
 * O QUE **NAO** ESTA' AQUI, E PORQUE (nao e' esquecimento -- e' limite do
 * mecanismo):
 *   O bloco injectado nao era so' este prologo. Envolvia tambem o CORPO
 *   NATURAL da funcao num setjmp/longjmp pad (g_ce03c_play_abort) com
 *   cellVdec_stop_all_for_play_abort() + reconstrucao da freelist do media
 *   object no ramo de abort. Um `[[midasm_hook]]` corre AO LADO de uma
 *   instrucao; nao pode ENVOLVER o corpo da funcao. Migrar essa parte exige
 *   substituir a funcao inteira -- weak override, Fase 19 -- ou um patch
 *   residual minimo so' para o pad. Enquanto isso nao acontecer, um lift
 *   feito com --config tem o wait-idle mas NAO tem o pad de abort: esta'
 *   escrito no SUMMARY do 17-03 e no ledger, e NAO se afirma paridade com as
 *   143 linhas do lift de producao.
 *
 * REGISTOS: o pump chama codigo guest, que mexe nos GPR. O bloco original
 * salvava e repunha SO' r30 (o corpo natural le' `vm_read32(gpr[30])` no
 * fim); r2 (TOC) era deliberadamente deixado como o pump o devolvia. Mantem-se
 * exactamente essa escolha -- divergir dela seria mudar o comportamento do
 * fix medido a pretexto de o migrar.
 * ------------------------------------------------------------------------ */
GOW2_MIDASM_USED
void gow2_midasm_Ce03cWaitIdle(ppu_context* ctx)
{
    const uint64_t sv_r30 = ctx->gpr[30];

    const uint32_t mv = vm_read32((uint32_t)ctx->gpr[2] - 0x1124u);
    uint32_t st = gow2_ea_ok(mv) ? vm_read32(mv + 0x620u) : 0u;

    if (st != 0u && gow2_ea_ok(mv)) {
        { static int n = 0; if (n++ < 8)
            fprintf(stderr, "[INTROSEQ] CE03C wait-idle 1st movie st620=%u\n", st); }

        for (int i = 0; i < 600; i++) {
            if (st >= 0xAu && vm_read32(mv + 0x714u) == 0u) {
                vm_write32(mv + 0x714u, 1u);
                { static int n = 0; if (n++ < 4)
                    fprintf(stderr, "[INTROSEQ] CE03C arm +0x714 st=%u\n", st); }
            }
            for (int j = 0; j < 32; j++) {
                func_002C0508(ctx);
                gow2_drain_trampoline(ctx);
                st = vm_read32(mv + 0x620u);
                if (st == 0u) break;
            }
            if (st == 0u) break;
            ppu_giant_lock_release();
            usleep(50000);
            ppu_giant_lock_acquire();
            if ((i % 40) == 0) {
                static int n = 0; if (n++ < 16)
                    fprintf(stderr, "[INTROSEQ] CE03C wait tick st620=%u i=%d\n", st, i);
            }
        }

        { static int n = 0; if (n++ < 8)
            fprintf(stderr, "[INTROSEQ] CE03C wait-idle exit st620=%u\n", st); }
    }

    /* O EOS sticky do filme #1 nao pode forcar "done" a meio do re-Play. */
    if (g_movie_eos_ea != 0u) {
        fprintf(stderr, "[INTROSEQ] CE03C clear sticky EOS hook 0x%08X\n",
                g_movie_eos_ea);
        fflush(stderr);
        g_movie_eos_ea = 0u;
    }
    if (gow2_ea_ok(mv)) {
        vm_write8(mv + 0x744u, 0);
        vm_write8(mv + 0x745u, 0);
        vm_write8(mv + 0x746u, 0);
    }
    movie_vt_clear_overlay_done();
    /* Subsume o patch_ce03c_movie_done_reset.py: o temporizador de "done"
     * baseado em tempo tem de ir a zero antes do re-Play natural. */
    movie_done_timebased_reset();

    ctx->gpr[30] = sv_r30;
}

} /* extern "C" */
