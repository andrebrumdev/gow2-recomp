/* gow2_midasm_hooks.h -- declaracoes dos mid-asm hooks HOST do GoW2.
 *
 * PORQUE ESTE FICHEIRO EXISTE
 * ---------------------------
 * Fase 17 (marco v1.3). Um `[[midasm_hook]]` declarado no
 * games/gow2/config/gow2_recomp.toml faz o ppu_lifter.py emitir, ao lado da
 * instrucao ancorada, uma chamada `gow2_midasm_<Name>(ctx);` (plano 17-01,
 * tools/ppu_lifter.py: MIDASM_SYMBOL_PREFIX / _midasm_lines / _preamble_lines).
 * O corpo dessa funcao vive AQUI: codigo host versionado e compilado, em vez
 * das linhas injectadas por um patch_*.py de texto que um re-lift apaga.
 *
 * O CONTRATO DO SIMBOLO (fixado e verificado no 17-01, nao inventado aqui)
 * -----------------------------------------------------------------------
 *   - assinatura: `void gow2_midasm_<Name>(ppu_context* ctx)` -- um so'
 *     parametro, o contexto guest;
 *   - `extern "C"` (o lifter emite a declaracao dentro de um `extern "C"`
 *     condicionado a __cplusplus; ver ppu_lifter.py::_preamble_lines);
 *   - SEM prefixo de simbolo (--symbol-prefix): os hooks sao simbolos host,
 *     nao funcoes liftadas.
 * A TU gerada ja' traz a sua propria declaracao no preambulo, por isso o lift
 * NAO precisa de incluir este header -- ele existe para o .cpp dos hooks e
 * para qualquer codigo host que lhes queira chamar. As duas declaracoes tem
 * de casar; se divergirem, o build parte (e e' esse o objectivo).
 *
 * NOTA SOBRE `ppu_context`: a TU liftada usa o typedef que o lifter escreve em
 * ppu_recomp.h; este header usa o canonico do motor (runtime/ppu/ppu_context.h,
 * alcancavel pelo -I do build_macos.sh). Sao dois typedefs distintos ao nivel
 * da linguagem mas com layout identico campo-a-campo -- verificado a
 * 2026-08-02 -- e, por serem `extern "C"`, o simbolo nao leva os tipos, logo
 * o link e' o mesmo. E' o mesmo arranjo que o ppu_loader do motor ja' usa.
 *
 * NAO METER AQUI: probes gated por env var com escritor proprio (esses
 * continuam patch_*.py, por decisao do 17-CONTEXT), nem overrides de funcao
 * inteira (isso e' weak override, Fase 19).
 */
#ifndef GOW2_MIDASM_HOOKS_H
#define GOW2_MIDASM_HOOKS_H

#include "ppu_context.h"

#ifdef __cplusplus
extern "C" {
#endif

/* CE03C wait-idle da intro (EA guest 0x000CE03C, piloto da Fase 17).
 * P0 no ledger games/gow2/lift_baseline/PATCH_MIGRATION.tsv, hoje ainda
 * instalado por recomp_mid_v2/patch_ce03c_introseq_block.py.
 * NO-OP no plano 17-02 (so' se prova que liga); o corpo -- pump ate' ao
 * MovieStop natural, arm do +0x714 e limpeza do sticky EOS -- entra no 17-03,
 * junto com a entrada [[midasm_hook]] no TOML. */
void gow2_midasm_Ce03cWaitIdle(ppu_context* ctx);

#ifdef __cplusplus
}
#endif

#endif /* GOW2_MIDASM_HOOKS_H */
