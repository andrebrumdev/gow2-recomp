# Sessão oráculo intro (2026-07-20) — recomp medido + gap nomeado

RPCS3 **não está instalado** nesta máquina (`which rpcs3` / Application Support
vazio). A coluna "RPCS3" abaixo é o **comportamento esperado** a partir de:

1. RE estática no lift (cadeia Play → FIOS documentada em `patch_fios_open_probe.py`)
2. Medição in-boot com `PS3_TRACE_FIOSOPEN=1` + `PS3_TRACE_SNDOPEN=1` + `PS3_TRACE_FIOSSCHED=1`
3. Spec de paths / módulos no tree RPCS3 local (`../_ref_rpcs3`)

Ferramentas: `./oracle_intro_checklist.sh`, `../ps3recomp/tools/oracle_parse_recomp_log.py`.

Planos: `ps3recomp/docs/superpowers/plans/2026-07-20-00-wall-chain-INDEX.md`.

---

## Status late (fim de sessão) — wall reclassificado

| Gap | Estado late |
|-----|-------------|
| Open m2v FIOS | ✅ handle ≠0 |
| Scheduler escreve done90 | ✅ |
| Poll consome done / 002B4274 | ✅ sticky + play-already |
| st620 1→3 | ✅ in-boot |
| f744 / EOS / 3→5→11 / WAD | ⏳ **parede actual** (plano EOS Task 7) |

**Fixes aplicados (motor + port):**
- `ps3recomp` giant lock POSIX + `lwcond` prio (`a82c594`); sticky API em `ppu_loader.cpp`
- `gow2-recomp` `patch_fios_play_already_active.py`, `patch_fios_cancel_yield.py` (`c5f718c`)
- lift local: `STICKY-RESTORE` / publish / consume (gitignored `recomp_macos_v2/`)

**Evidência:** `/tmp/fios_sticky.log`, `/tmp/fios_sticky2.log` —
`STICKY-RESTORE` → `002B4274 DONE` → `st620 1 -> 3` (fica em 3, `f744=0`).

---

## Como repetir

```bash
cd gow2-recomp
./oracle_intro_checklist.sh 35
# com log RPCS3 quando existir:
./oracle_intro_checklist.sh 35 /path/to/RPCS3.log

PS3_TRACE_FIOSOPEN=1 PS3_TRACE_SNDOPEN=1 PS3_TRACE_FIOSSCHED=1 \
  ./oracle_intro_checklist.sh 40
```

Aceite mínimo pós-4.0 (baseline, EOS OFF):

```bash
grep -E 'STICKY-RESTORE|002B4274 DONE|st620 .*->' /tmp/run.log
# esperável: DONE ou STICKY; st620 max ≥ 3; sem MOVIEEOS se EOS=0
```

---

## Tabela de gaps (10 linhas) — actualizada late

| # | Pergunta | recomp late | RPCS3 / consola (esperado) | Gap / acção |
|---|----------|-------------|----------------------------|-------------|
| 1 | Opens cellFs | 1× `gow2.psarc` | archive + members | OK; membros via FIOS |
| 2 | Path SmLogo | `/_movies/smlogo_v2.m2v` | mesmo | OK |
| 3 | Via | FIOS mediaobj | FIOS | OK |
| 4 | movie_io m2v? | não (psarc) | n/a | esperado |
| 5 | Path exacto | smlogo_v2.m2v flags 0x20 | — | OK |
| 6 | wav / SNDOPEN | path visto; WAV_SURVIVABLE | stream paralelo | 2º open pool = ruído |
| 7 | Poll `done≠0`? | **sim** (sticky → 4274) | done antes do poll útil | **destravado** |
| 8 | Scheduler FIOS | sched + complete + done90 | thread fios | OK |
| 9 | st620 | **0→1→3** (parque em 3) | 1→3→5→11→done | **falta 3→5→11** |
| 10 | f744 / WAD | f744=0; sem R_* | EOS + WAD | **parede actual** |

### Diagnóstico refinado (histórico → late)

| Fase | Frase |
|------|--------|
| Manhã | open falha / handles 0 |
| Mid | open OK; done **produzido**; poll **não consome** |
| Late | poll **consome** (sticky); FSM em **3**; falta **EOS/f744/WAD** |

Causas do não-consumo (documentadas, parcialmente mitigadas):

1. Play reentrante `002C0498` → teardown + re-open → `SEM OP LIVRE` → `io=0`  
   → **play-already-active**
2. Guest `[op+0x90]` fica 1 no fim do complete (RAWMEM) e 0 no 1º poll **sem** write32 ao EA  
   → **sticky publish/restore** (workaround honesto do sinal do produtor; clear fantasma opcional)

---

## Próxima acção única (implementação)

| Prioridade | Acção | Não fazer |
|------------|--------|-----------|
| **1** | Plano EOS **Task 7**: pós-st620=3 → f744 / 3→5→11 / open R_* | Forjar st620=5 ou f744 |
| **2** | Higiene: `patch_fios_sticky_*.py` + smoke N/M DONE4274 | Duplicar HLE 002B3D1C (refutado) |
| **3** | (opcional) pinchar clear fantasma de done | Sleep hacks cegos no poll |
| **4** | RPCS3 instalado para coluna oráculo real | Copiar GPL / forjar porque o emulador avançou |

---

## RPCS3 nesta máquina

**Não instalado.** Para fechar a coluna oráculo de verdade:

1. Instalar https://rpcs3.net/ ou build GitHub  
2. Mesmo dump NPUA80491  
3. `./oracle_intro_checklist.sh 40 "$HOME/Library/Application Support/rpcs3/RPCS3.log"`  

---

## Ficheiros desta sessão

| Artefacto | Path |
|-----------|------|
| Checklist / logs oracle | `oracle_out/` |
| Logs sticky | `/tmp/fios_sticky.log`, `/tmp/fios_sticky2.log` |
| Tools | `oracle_intro_checklist.sh`, `../ps3recomp/tools/oracle_parse_recomp_log.py` |
| Planos | `docs/superpowers/plans/2026-07-20-00-wall-chain-INDEX.md` (+ 4.0, EOS, fios-async) |
