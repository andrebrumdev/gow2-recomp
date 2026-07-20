# Sessão oráculo intro (2026-07-20) — recomp medido + gap nomeado

RPCS3 **não está instalado** nesta máquina (`which rpcs3` / Application Support
vazio). A coluna "RPCS3" abaixo é o **comportamento esperado** a partir de:

1. RE estática no lift (cadeia Play → FIOS documentada em `patch_fios_open_probe.py`)
2. Medição in-boot com `PS3_TRACE_FIOSOPEN=1` + `PS3_TRACE_SNDOPEN=1` (esta sessão)
3. Spec de paths / módulos no tree RPCS3 local (`../_ref_rpcs3`)

Ferramentas: `./oracle_intro_checklist.sh`, `../ps3recomp/tools/oracle_parse_recomp_log.py`.

---

## Como repetir

```bash
cd gow2-recomp
./oracle_intro_checklist.sh 35
# com log RPCS3 quando existir:
./oracle_intro_checklist.sh 35 /path/to/RPCS3.log

# probe fina (já default no checklist):
PS3_TRACE_FIOSOPEN=1 PS3_TRACE_SNDOPEN=1 PS3_TRACE_FIOSSCHED=1 \
  ./oracle_intro_checklist.sh 40
```

---

## Tabela de gaps (10 linhas) — preenchida

| # | Pergunta | recomp (medido 28–35 s) | RPCS3 / consola (esperado) | Gap / acção |
|---|----------|-------------------------|----------------------------|-------------|
| 1 | Opens cellFs bem-sucedidos | 1: só `gow2.psarc` via `[fs] open` | Archive open + reads de membros | OK para o arquivo; membros **não** passam por cellFs |
| 2 | Path SmLogo visto? | **Sim** via FIOS: `/_movies/smlogo_v2.m2v` | Membro no psarc lowercase | Não é cellFs — é FIOS |
| 3 | Via cellFs / movieio / fios? | fiosopen + fs(psarc); **movieio não serve m2v/wav** | FIOS mediaobj open | movie_io só se cellFsOpen no basename |
| 4 | movie_io serviu ficheiro? | **no** (só tenta `gow2.psarc` no cache e falha) | n/a | Esperado: membros via FIOS, não basename de psarc |
| 5 | Path FIOS exacto | `/_movies/smlogo_v2.m2v` (flags 0x20) | mesmo formato | **OK** — F4 refutado |
| 6 | wav / SNDOPEN? | **Sim** `path='/_movies/SmLogo_v2.wav'` em `0045E230` / open drv guest `0x002B47D4` | open audio stream paralelo ao vídeo | wav no `movie_cache/` existe; open **não** é cellFs |
| 7 | Poll open `done≠0`? | **polls milhares, done sempre 0** em 28 s | op completa (`[op+0x90]=1`) antes do poll útil | **WALL ACTUAL** |
| 8 | Scheduler FIOS corre? | (correr com `PS3_TRACE_FIOSSCHED=1`) | thread `fios scheduler` drena fila e chama complete | Hipótese: scheduler não completa a tempo / não corre |
| 9 | st620 | **0 → 1 → 3** (avança!) | 1→3→5→11→done | Já não está preso só em 1 |
| 10 | AddWorkload / stubs | AddWorkload>0; sc stubs vazios no log oracle | — | M2/boot sc OK |

### Evidência bruta (FIOSOPEN)

```
Play 002C00DC nome='SmLogo_v2' flags ramo → /_movies/%s.m2v
0030D578 path='/_movies/smlogo_v2.m2v'
0030D5CC file_new r3=0x43018528 path='/_movies/smlogo_v2.m2v'   ← open devolve handle
002B4224 poll … done=0x00000000   (milhares de vezes)          ← poll nunca vê done
```

### Evidência bruta (SNDOPEN)

```
0045E230 path='/_movies/SmLogo_v2.wav'
00461658 OPEN … sub inline '/_movies/SmLogo_v2.wav'
open() → guest code EA 0x002B47D4 (FIOS-ish), não cellFsOpen
```

---

## Diagnóstico (actualizado com FIOSSCHED)

### Hipótese inicial (parcialmente errada)

“Open assíncrono nunca completa” — **refutada**.

Com `PS3_TRACE_FIOSSCHED=1` (20 s, `/tmp/fiossched.log`):

```
[FIOSSCHED] sched #1 entrou func_0030ED68 r3=0x43009270
[FIOSSCHED] complete #1 op=0x430094C0 estado=1 opcode=9 … done_antes=0
[FIOSSCHED] done90 #1 op=0x430094C0 <- 1 (opcode=9)
… complete estado=2 (teardown) …
done90: 6   complete: 12   sched: 1
```

O **scheduler corre**, **complete com estado=1**, e **`[op+0x90]=1` é escrito**.

### Wall real (refinado)

O poll do estado 1 (`func_002B4224`) regista **milhares** de `done=0x00000000` em
`io=0x430095A0` **ao mesmo tempo** que o scheduler marca done noutras ops (e
às vezes na mesma). Padrões possíveis:

1. **Race / ordem:** o poll corre no main sob giant lock e perde a janela em que
   `done==1` antes do complete estado=2 / reutilização da op.
2. **Op errada no container:** `io` apontado pelo poll ≠ op que o scheduler
   completou no instante certo.
3. **Visibilidade:** menos provável em process único, mas giant lock + threads
   guest pode reordenar o que o poll “vê” se houver cache mental errado no lift.

**Frase:** open FIOS **sucesso**; done **é produzido**; o estado 1 **não consome**
o done a tempo (race / wiring do poll), não “falta ficheiro no cache”.

---

## Próxima acção única (implementação)

| Prioridade | Acção | Não fazer |
|------------|--------|-----------|
| **1** | Correlacionar `io=` do poll com `op=` do done90 no **mesmo** segundo (script) | Forjar `[op+0x90]` |
| **2** | Se op coincide e done oscila 0→1→0: atrasar teardown ou notificar waiter (lwcond) como no hardware | Skip scheduler |
| **3** | Se op **não** coincide: bug de container/+4/+8 no 2º Play | Force st620 |
| **4** | Giant lock: garantir que fios scheduler não fica eternamente atrás do main no poll | Sleep hacks cegos |

Referência RPCS3: não há HLE “FIOS”; o emulador faz o guest scheduler progredir
com sync/threads fiéis. Diff útil: ordem de `sys_lwcond_signal` vs poll no log RPCS3.

---

## RPCS3 nesta máquina

**Não instalado.** Para fechar a coluna oráculo de verdade:

1. Instalar https://rpcs3.net/ ou build GitHub  
2. Mesmo dump NPUA80491  
3. `./oracle_intro_checklist.sh 40 "$HOME/Library/Application Support/rpcs3/RPCS3.log"`  

Até lá, a tabela acima usa RE+probes como proxy documentado.

---

## Ficheiros desta sessão

| Artefacto | Path |
|-----------|------|
| Checklist auto | `oracle_out/checklist_20260720_173609.md` |
| Log recomp 35s | `oracle_out/recomp_20260720_173609.log` |
| Log FIOS/SND 28s | `/tmp/fios35.log` |
| Tools | `oracle_intro_checklist.sh`, `../ps3recomp/tools/oracle_parse_recomp_log.py` |
