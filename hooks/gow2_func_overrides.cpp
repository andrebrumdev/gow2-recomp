/* gow2_func_overrides.cpp -- corpos dos WEAK OVERRIDES host do GoW2.
 *
 * Ver o cabecalho de gow2_func_overrides.h para o contrato do simbolo, para a
 * diferenca face ao mid-asm da Fase 17 e para a razao de a macro
 * GOW2_FUNC_OVERRIDE nao ser cosmetica.
 *
 * ESTADO NESTE PLANO (19-02): UM SO' OVERRIDE, E E' IDENTIDADE.
 * ------------------------------------------------------------
 * O 19-01 mediu OFFLINE que o mecanismo funciona (nm -m + execucao real de um
 * binario ligado com override). Este plano liga a ponta HOST: TU versionada,
 * compilada e ligada pelo build_macos.sh, e prova IN-BOOT que o override que
 * ganha o link e' este ficheiro e nao o wrapper fraco do lift.
 *
 * Por isso o piloto e' de IDENTIDADE: chama `__imp_func_00010230(ctx)` e mais
 * nada. Com o probe desligado (o default) o comportamento do boot e' o mesmo
 * que sem o mecanismo -- e' isso que torna o smoke de nao-regressao uma
 * medicao do CAMINHO DE LINK e nao de uma mudanca de logica misturada com ele.
 * As migracoes com comportamento real (o pad de setjmp/longjmp do CE03C, os
 * OPD P0 do ledger) sao o 19-03: NAO as meter aqui sem plano.
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

#include <cstdio>
#include <cstdlib>

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
