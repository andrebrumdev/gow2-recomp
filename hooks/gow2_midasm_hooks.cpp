/* gow2_midasm_hooks.cpp -- corpos dos mid-asm hooks HOST do GoW2.
 *
 * Ver o cabecalho de gow2_midasm_hooks.h para o contrato do simbolo e para a
 * razao de este ficheiro existir.
 *
 * ESTADO NESTE PLANO (17-02): TODOS OS CORPOS SAO NO-OP, DE PROPOSITO.
 * -------------------------------------------------------------------
 * O 17-02 fecha so' a metade de LINK do XEN-02: o lifter ja' sabe emitir a
 * chamada (17-01), aqui garante-se que o simbolo RESOLVE no boot_gow2 e que
 * ligar o objecto nao muda o comportamento do boot. Por isso o smoke desta
 * fase tem de bater o baseline da Fase 16 -- se mudasse alguma coisa, seria a
 * mudanca de build a ser culpada, nao o hook.
 *
 * O principio G2 do marco (probes OFF por default = zero mudanca de
 * comportamento) exige ainda que TODO o hook declarado no TOML tenha corpo,
 * mesmo o nao implementado: sem stub, declarar um hook da' erro de LINK em vez
 * do no-op que se pediu. Regra pratica para quem mexer nisto: uma entrada
 * [[midasm_hook]] nova no games/gow2/config/gow2_recomp.toml sem stub aqui
 * parte o link -- e' o comportamento desejado (falha alto, nao em silencio),
 * mas o stub deve entrar no mesmo commit que a entrada do TOML.
 *
 * PORTABILIDADE (G4 -- Windows nao regride): zero tokens Win32 fora de
 * #ifdef _WIN32 -- e nem sequer os NOMES dessa lista aparecem aqui, para um
 * grep de auditoria do G4 sobre este ficheiro sair vazio em vez de sair a
 * apontar para um comentario. A lista vive no CLAUDE.md da raiz.
 * Quando o corpo do CE03C entrar (17-03) usara' usleep/nanosleep e o giant
 * lock do runtime, como o patch_ce03c_introseq_block.py ja' faz.
 */
#include "gow2_midasm_hooks.h"

/* GOW2_MIDASM_USED: impede que um linker com dead-strip agressivo deixe cair
 * um hook que ainda nenhum lift chama -- e' exactamente o caso do 17-02, em
 * que a producao ainda nao foi re-liftada com --config. Verificado por leitura
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

extern "C" {

/* Piloto da Fase 17. Corpo real no 17-03. */
GOW2_MIDASM_USED
void gow2_midasm_Ce03cWaitIdle(ppu_context* ctx)
{
    (void)ctx;
}

} /* extern "C" */
