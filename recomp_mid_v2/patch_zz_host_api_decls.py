#!/usr/bin/env python3
"""Declara no preambulo de cada chunk o API host que o lift usa.

Porque existe
-------------
Os blocos instalados pelos patch_*_install.py chamam funcoes host
(ps3_factory_*, ps3_type15_*, ps3_timebase_now) cujas DECLARACOES viviam no
preambulo escrito a mao do lift gitignored -- outra edicao manual sem escritor.
Medido em 2026-07-26, ao tentar construir a partir de um lift regenerado:

    ppu_recomp_000.cpp:144906: error: use of undeclared identifier
                               'ps3_factory_repair_vt'
    ppu_recomp_000.cpp:144909: error: ... 'ps3_factory_freelist_replenish'
    ppu_recomp_000.cpp:144930: error: ... 'ps3_factory_reuse_product'
    ppu_recomp_000.cpp:166138: error: ... 'ps3_timebase_now'

As DEFINICOES estao versionadas em ../host_gow2_factory.cpp (13 funcoes,
commit 1f651aa); faltavam so' as declaracoes do lado do lift.

Como funciona
-------------
Declara apenas o que cada chunk USA: varre o ficheiro, e para cada simbolo
conhecido que apareça sem declaracao, injecta a linha `extern "C"` no
preambulo. Um chunk que nao chame nada fica intocado -- nao ha' poluicao.

As assinaturas foram copiadas das definicoes reais de host_gow2_factory.cpp,
nao inventadas; uma divergencia de assinatura daria erro de link so' no fim,
que e' o tipo de falha tardia que este projecto ja' pagou caro.

Uso:  patch_host_api_decls.py [LIFT_DIR_OU_FICHEIRO...]
rc=0 aplicado ou nada a fazer | rc=3 lift ilegivel
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lift_paths import resolve_lift_paths            # noqa: E402

MARKER = "HOST-API-DECLS"
END_MARKER = f"/* fim {MARKER} */"

# simbolo -> declaracao. Assinaturas copiadas de ../host_gow2_factory.cpp
DECLS = {
    "ps3_factory_snap_vt":
        'extern "C" void ps3_factory_snap_vt(uint32_t obj, uint32_t vt);',
    "ps3_factory_snap_product":
        'extern "C" void ps3_factory_snap_product(uint32_t fo, uint32_t product);',
    "ps3_factory_repair_vt":
        'extern "C" int ps3_factory_repair_vt(uint32_t obj);',
    "ps3_factory_reuse_product":
        'extern "C" uint32_t ps3_factory_reuse_product(uint32_t fo);',
    "ps3_factory_freelist_replenish":
        'extern "C" int ps3_factory_freelist_replenish(uint32_t fo, uint16_t type_id);',
    "ps3_type15_product_list_reset":
        'extern "C" void ps3_type15_product_list_reset(uint32_t prod);',
    "ps3_type15_protected_obj":
        'extern "C" uint32_t ps3_type15_protected_obj(void);',
    "ps3_type15_good_vt":
        'extern "C" uint32_t ps3_type15_good_vt(void);',
    "ps3_type15_block_stomp":
        'extern "C" int ps3_type15_block_stomp(uint32_t addr, uint32_t val);',
    "ps3_type15_pin_free":
        'extern "C" int ps3_type15_pin_free(uint32_t blk);',
    "ps3_type15_note_resolve":
        'extern "C" void ps3_type15_note_resolve(uint32_t idx, uint32_t obj, uint32_t vt);',
    "ps3_type15_repair_if_needed":
        'extern "C" int ps3_type15_repair_if_needed(uint32_t obj);',
    "ps3_type15_freelist_replenish":
        'extern "C" int ps3_type15_freelist_replenish(void);',
    "ps3_timebase_now":
        'extern "C" uint64_t ps3_timebase_now(void);',
    # FIOS sticky done-word: definidas em runtime/ppu/ppu_loader.cpp
    "ps3_fios_sticky_publish":
        'extern "C" void ps3_fios_sticky_publish(uint32_t op);',
    "ps3_fios_sticky_peek":
        'extern "C" int ps3_fios_sticky_peek(uint32_t op);',
    "ps3_fios_sticky_consume":
        'extern "C" void ps3_fios_sticky_consume(uint32_t op);',
    # giant lock: o bloco do CE03C liberta-o a' volta do usleep do wait-idle
    "ppu_giant_lock_acquire":
        'extern "C" void ppu_giant_lock_acquire(void);',
    "ppu_giant_lock_release":
        'extern "C" void ppu_giant_lock_release(void);',
}

# Cabecalhos que os blocos injectados usam e que o preambulo do lifter nao traz.
# (usleep no wait-idle do CE03C; jmp_buf no pad de longjmp)
HEADERS = {
    "usleep": "#include <unistd.h>",
    "jmp_buf": "#include <setjmp.h>",
}

ANCHOR = '#include "ppu_recomp.h"\n'


def needed_headers(text: str) -> list[str]:
    """Cabecalhos usados pelos blocos e ausentes do preambulo do lifter."""
    return [h for sym, h in HEADERS.items()
            if h not in text and re.search(rf"\b{sym}\b", text)]


def strip_block(text: str) -> str:
    """Remove um bloco MARKER injectado por uma corrida anterior.

    Sem isto o patch nao e' auto-corrector: uma assinatura errada de uma
    versao antiga fica no ficheiro e a nova (correcta) e' injectada ao lado,
    dando `conflicting types` -- medido em 2026-07-26 no ppu_recomp_001.

    O bloco e' delimitado por MARKER ... END_MARKER e o strip recorta EXACTAMENTE
    esse intervalo. Duas versoes anteriores tentaram inferir o fim e ambas
    comeram codigo alheio (2026-07-26):
      1. `.*?` com re.S -> o `.*\\n` greedy engoliu ate' ao fim do ficheiro e
         truncou tres chunks do lift a 2 linhas;
      2. "para na 1a linha que nao e' #include/extern" -> comeu os
         `#include <stdio.h>` que o PROPRIO lifter emite logo a seguir, e os
         chunks 000/002 deixaram de compilar (`undeclared identifier 'stderr'`).
    Delimitador explicito, nunca heuristica.
    """
    return re.sub(
        rf"/\* {MARKER}:[^\n]*\n(?:(?!{re.escape(END_MARKER)})[^\n]*\n)*"
        rf"{re.escape(END_MARKER)}\n",
        "", text)


def defines(text: str, sym: str) -> bool:
    """O proprio ficheiro ja' DEFINE o simbolo (corpo, nao so' prototipo)?"""
    return re.search(rf"\b{sym}\s*\([^;()]*\)\s*\{{", text) is not None


def needed(text: str) -> list[str]:
    """Simbolos usados como CHAMADA e ainda sem declaracao neste ficheiro."""
    out = []
    for sym, decl in DECLS.items():
        if decl in text:                       # ja' declarado
            continue
        if defines(text, sym):                 # definido aqui -- nao declarar
            continue
        if re.search(rf"\b{sym}\s*\(", text):  # usado
            out.append(sym)
    return out


def render(text: str) -> str:
    """Estado desejado do ficheiro: sem bloco antigo, com o bloco certo."""
    t = strip_block(text)
    syms = needed(t)
    hdrs = needed_headers(t)
    if not syms and not hdrs:
        return t
    if ANCHOR not in t:
        return t
    block = (f'/* {MARKER}: API host usada por este chunk. Definicoes em\n'
             f' * gow2-recomp/host_gow2_factory.cpp e runtime/ppu/ppu_loader.cpp.\n'
             f' * Sem estas declaracoes o chunk nao compila. */\n'
             + "".join(h + "\n" for h in hdrs)
             + "\n".join(DECLS[s] for s in syms) + ("\n" if syms else "")
             + END_MARKER + "\n")
    return t.replace(ANCHOR, ANCHOR + block, 1)


def patch_one(path: Path) -> int:
    """1 = escreveu, 0 = ja' no estado desejado.

    Convergente por construcao: calcula o estado final e so' escreve se
    diferir. Reaplicar o patch e' sempre no-op.
    """
    orig = path.read_text(encoding="utf-8", errors="replace")
    t = strip_block(orig)
    if ANCHOR not in t and (needed(t) or needed_headers(t)):
        print(f"  {path.name}: sem ancora #include \"ppu_recomp.h\" -- ignorado",
              file=sys.stderr)
        return 0
    syms, hdrs = needed(t), needed_headers(t)
    out = render(orig)
    if out == orig:
        return 0
    path.write_text(out, encoding="utf-8")
    print(f"  {path.name}: APPLIED ({len(syms)} decls, {len(hdrs)} headers)"
          + (f" -> {', '.join(syms)}" if syms else ""))
    return 1


def main() -> int:
    paths = [p for p in resolve_lift_paths(sys.argv[1:], "ppu_recomp_000.cpp")
             if p.is_file()]
    if not paths:
        print("ERRO: nenhum ficheiro de lift legivel", file=sys.stderr)
        return 3
    n = sum(patch_one(p) for p in paths)
    print(f"[host-api-decls] {n} chunk(s) declarados"
          if n else "[host-api-decls] nada a declarar (ALREADY)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
