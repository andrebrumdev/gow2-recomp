# G4 — o gate real do open de `R_LglScA`/`R_PermA` (e por que nunca dispara no Mac)

Task 3, sub-faixa 3-G4 (`ps3recomp/.superpowers/sdd/task-3-brief.md`). Método: RE
estática do lift (`recomp_macos_v2/ppu_recomp_0NN.cpp`, gitignored, sempre
`grep -n` + `sed -n`/Read com range) **mais** 4 boots in-boot medidos (armados,
`PS3_TRACE_MOVIEOBJ=1`/`PS3_TRACE_SMPD=1`/`PS3_DUMP_IMPORTS=1`), matados sempre
por PID (`TERM` depois `-9`, `wait`, `pgrep` a confirmar 0 no fim de cada um).
Duas sondas diagnósticas novas, read-only, gated, adicionadas em `ps3recomp`
(runtime, não-lift) para decidir a questão — ver secção 6.

---

## TL;DR — veredito

**G4 refinado, não confirmado como estava formulado.** O "lead forte" herdado
(`func_0045B2A8`/`obj+0x720` = "sessão de decode vdec fria") está **refutado**:
`obj+0x720` é o handle do **snd_stream de ÁUDIO** (não vídeo — confirmado por
RE cruzada com `2026-07-20-macos-intro-audio-open-wall.md`), e a leitura da
condição de avanço estava **invertida** (secção 3): um handle **não resolvido**
faz `func_0045B2A8` devolver **-1**, e -1 **avança** a FSM (só o **0 literal**
pára). Isso não é o que bloqueia o Open.

**O bloqueio real, medido in-boot (secção 5):** `cellVdecOpenEx`/`cellVdecStartSeq`
têm **exactamente 1 site de chamada estático cada, em todo o lift de 31 chunks**
— dentro do handler do **estado 4** da FSM (`func_002C069C`), condicionado a
`vm_read8(obj+0x744) == 0`. O handler do **estado 3** (`func_002C05F8`) faz o
**mesmo teste primeiro**: se `+0x744 != 0`, salta directamente para o estado 5
**sem nunca entrar no estado 4** — nunca chamando Open. **O nosso próprio
mecanismo de arm de EOS (`movie_eos_arm.c`, usado por todas as sessões
anteriores para destravar `st620` 1→3) marca `+0x744` como "já terminado"
exactamente no momento em que os estados 3/4 fazem essa pergunta — e eles
interpretam "já terminado" como "não há nada para abrir", não como "o vídeo
já acabou de tocar".** Confirmado por trace `[EOSGATE]` em boot armado
(secção 5.2): o site do estado 3 dispara `val=1 branch=adv` no primeiro tick
pós-arm; o site do estado 4 nunca dispara nenhuma vez.

**Resultado:** 0 WADs abertos (0/4 boots medidos nesta task; consistente com
os 0/6 herdados). **Não** implementei o fix (é preciso editar
`movie_eos_arm.c`, ficheiro de outra sessão activa — ver secção 7) e não
consegui verificar em boot um fix hipotético porque, a meio da task, uma
sessão concorrente sobrescreveu o `boot_gow2`/`libps3recomp_runtime.a`
partilhados com um build **que ela própria documentou como regressão**
("st620 ficou 0, OOB stack" — `ps3recomp/CLAUDE.md`, secção "Alternativa mais
segura que merge total") — ver secção 8. Isto não é reclass "vdec frio
irrecuperável" (essa premissa caiu); é "causa raiz nomeada com prova, fix
apontado mas bloqueado por ambiente partilhado instável no momento desta
sessão".

---

## 1. O achado principal — onde `cellVdecOpenEx`/`StartSeq` são chamados

`PS3_DUMP_IMPORTS=1` (gate pré-existente em `ppu_imports.cpp`, ampliado nesta
task para também imprimir `tramp`, o endereço-alvo real que o `bl` do jogo usa
— ver secção 6) dá os 8 imports do módulo `libvdec` desta build:

| NID | símbolo (via `gen/ppu_hle_nids.cpp`) | `tramp` (EA guest chamado pelo jogo) |
|---|---|---|
| `0x0053E2D8` | `cellVdecOpenEx` | `0x004B9398` |
| `0xC757C2AA` | `cellVdecStartSeq` | `0x004B9458` |
| `0xC982A84A` | `cellVdecQueryAttrEx` | `0x004B9478` |
| `0xB6BBCD5D` (`cellVdecOpen`, não-Ex) | — | **não está na lista de imports desta build** |

O título **não importa `cellVdecOpen`** — só `cellVdecOpenEx` (o HLE mapeia
ambos para o mesmo `cellVdecOpen()` em `libs/codec/cellVdec.c`, então o log
`[cellVdec] Open ...` cobre os dois casos por igual).

Grep de `func_004B9398(` e `func_004B9458(` nos 31 chunks (`ppu_recomp_000.cpp`
… `ppu_recomp_030.cpp`, ~18M linhas):

```
recomp_macos_v2/ppu_recomp_001.cpp:36727:  func_004B9398(ctx); DRAIN_TRAMPOLINE(ctx);   // cellVdecOpenEx
recomp_macos_v2/ppu_recomp_001.cpp:36730:  func_004B9458(ctx); DRAIN_TRAMPOLINE(ctx);   // cellVdecStartSeq
```

**Um único site de chamada cada, em todo o binário do jogo.** Ambos dentro de
`func_002C069C` (`ppu_recomp_001.cpp:36675`), que é o handler do **estado 4**
da FSM do movie player (jump table do pump, confirmada em
`2026-07-20-st620-3to0-static.md`: `st620==4 -> 0x2C069C`).

---

## 2. `func_002C069C` (estado 4) — o corpo completo do gate

```c
// ppu_recomp_001.cpp:36675
void func_002C069C(ppu_context* ctx) {
        ctx->gpr[0] = vm_read8(ctx->gpr[30] + 0x744);          // :36676 — relê o byte de EOS
        ...
        if ((!((ctx->cr >> 0) & 2))) {                          // :36686 — SE +0x744 != 0
            g_trampoline_fn = (void(*)(void*))func_002C060C; return;   //   -> salta p/ st620=5, NÃO abre
        }
        // ... monta os argumentos (type@obj+0x748, res, cb, handle@obj+0x668) ...
        func_004B9398(ctx); DRAIN_TRAMPOLINE(ctx);              // :36727 — cellVdecOpenEx
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);
        ctx->gpr[3] = vm_read32(ctx->gpr[30] + 0x668);          // handle devolvido por OpenEx
        func_004B9458(ctx); DRAIN_TRAMPOLINE(ctx);              // :36730 — cellVdecStartSeq
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);
        ctx->gpr[0] = 5; vm_write32(ctx->gpr[30] + 0x620, ctx->gpr[0]);  // st620=5, incondicional
        { g_trampoline_fn = (void(*)(void*))func_002C0760; return; }    // :36734 — avança p/ estado 5
}
```

Traduzido: **"se o filme já está marcado como terminado, não há nada para
decodificar — salta a abertura e vai para o estado 5. Senão, abre o
decodificador de vídeo, arranca a sequência, e avança."** Isto é código são —
é exactamente o que se espera de um player real (não reabrir um decoder para
um clip já consumido). O bug não está aqui.

O handler do **estado 3** (`func_002C05F8`, `ppu_recomp_001.cpp:36610`) faz o
**mesmíssimo teste, primeiro**:

```c
// ppu_recomp_001.cpp:36610
void func_002C05F8(ppu_context* ctx) {
        ctx->gpr[0] = vm_read8(ctx->gpr[30] + 0x744);           // :36611
        ...
        if (((ctx->cr >> 0) & 2)) {                              // :36629 — SE +0x744 == 0
            g_trampoline_fn = (void(*)(void*))func_002C0688; return;  //  -> cadeia normal (secção 3)
        }
        // +0x744 != 0: "já terminado" — nem passa pelo estado 4
        ctx->gpr[0]=4; vm_write32(obj+0x620, gpr0);
        ctx->gpr[0]=5; vm_write32(obj+0x620, gpr0);              // st620 vira 5 directo (4 é transitório, nunca despachado)
        { g_trampoline_fn = (void(*)(void*))func_002C060C; return; }  // :36634
}
```

Ou seja: **há DOIS pontos (estado 3 e estado 4) que tratam `+0x744 != 0` como
"nada a abrir"** — e o estado 3 é o primeiro a correr.

---

## 3. Correcção ao "lead forte" herdado — `obj+0x720` não é sessão de vídeo

Quando `+0x744 == 0` (o caso normal, logo após o `Play` limpar os bytes de EOS
— confirmado em `2026-07-20-macos-intro-audio-open-wall.md` secção (a)), o
estado 3 cai em `func_002C0688` (`ppu_recomp_002.cpp:224843`):

```c
void func_002C0688(ppu_context* ctx) {
        ctx->gpr[0] = vm_read8(ctx->gpr[30] + 0x746);
        if (EQ) { -> func_002C0FA0; return; }          // +0x746==0
        st620 = 4; { -> func_002C0694; return; }        // +0x746!=0 -> avança directo
}
void func_002C0694(ppu_context* ctx) {                  // "avançar para estado 4"
        st620 = 4; { -> func_002C069C; return; }
}
void func_002C0FA0(ppu_context* ctx) {                   // ppu_recomp_002.cpp:224858
        ctx->gpr[3] = vm_read32(ctx->gpr[30] + 0x720);
        func_0045B2A8(ctx); DRAIN_TRAMPOLINE(ctx);        // gpr3 = resultado
        if (EQ, i.e. gpr3==0) { -> func_002C0614; return; }   // PARK só se == 0 literal
        { -> func_002C0694; return; }                    // qualquer outro valor (inclui -1!) -> AVANÇA
}
```

E `func_0045B2A8` (`ppu_recomp_001.cpp:426000` — **não 425951** como o brief
citava; linha antiga já não bate, lift foi regerado; sempre re-verificar):

```c
void func_0045B2A8(ppu_context* ctx) {
        ...
        func_004479E8(ctx); DRAIN_TRAMPOLINE(ctx);   // resolve handle geracional (gpr3=obj+0x720 na entrada)
        gpr0 = -1;                                    // default
        if (gpr3_resolvido == 0) goto loc_0045B2CC;    // resolve FALHOU -> mantém -1
        gpr0 = vm_read32(gpr3_resolvido + 0x1B8);       // resolve OK -> lê o campo real
loc_0045B2CC:
        gpr3 = gpr0; return;   // valor devolvido
}
```

**Isto é o oposto do que os documentos anteriores (`2026-07-20-st620-3to0-static.md`,
`2026-07-20-macos-post-st3-smpd-wad.md`, e o brief desta task) assumiam.** A
leitura antiga era "obj+0x720 precisa de uma sessão viva com `+0x1B8!=0`;
sem sessão, `func_0045B2A8` devolve 0/-1, fica parado". A leitura correcta
(confirmada por leitura directa do C gerado, não por prosa de nota antiga) é:

- **Handle não resolve (obj+0x720 vazio/inválido) → devolve literal `-1` → `-1 != 0` → `func_002C0FA0` AVANÇA.**
- **Handle resolve E `*(sessão+0x1B8) == 0` → devolve literal `0` → PARA.**
- Só este segundo caso pára. Um "não há sessão nenhuma" **não** é o que
  bloqueia — pelo contrário, avançaria de imediato.

E o que é `obj+0x720`? Cruzando com a RE já feita (não desta task) em
`2026-07-20-macos-intro-audio-open-wall.md` secção (a), o `Play`
(`func_002C00DC`) chama `func_0045E230` ("**snd_stream OPEN (returns into
obj+0x720)**") — é o handle do **áudio** (`.wav` da SmLogo), não do vídeo. O
handle de vídeo que `cellVdecOpenEx` devolve vai para **`obj+0x668`**
(confirmado nesta task, secção 2 — é o `r6`/4º argumento passado a
`func_004B9398`). São dois handles completamente distintos.

**Conclusão da secção:** o gate do estado 3 (`func_0045B2A8(obj+0x720)`) está
a verificar se o **subsistema de áudio** atingiu algum marco (não zero em
`+0x1B8`) — plausivelmente "áudio pronto/terminado" — **antes** de abrir o
decodificador de vídeo. Como o `.wav` abre com sucesso no Mac (já provado,
`543ab35`, "WAV_SURVIVABLE"), `obj+0x720` deve resolver para uma sessão real,
e por isso o campo genuinamente começa em 0 e o estado 3 fica à espera dele
progredir — **não** por falta de handle.

---

## 4. Porque é que isto ainda faz o `st620` avançar 1→3→(cascata)→0 tal como medido antes

Nada disto contradiz as notas anteriores sobre o `st620` chegar a 3 (sticky
FIOS, Task 8) nem sobre a cascata 3→11→Stop quando o hook dispara (Task 1 do
plano EOS). O que esta task acrescenta é **o que acontece DENTRO dessa
cascata, no exacto tick em que o hook arma**: ela passa pelo estado 4 **sem
nunca o executar de facto** (state 3 já desvia para 5 antes de o pump alguma
vez despachar para `func_002C069C`). Isso é o que faltava explicar — porque é
que a cascata "3→…→11" nunca deixa rasto de `[cellVdec] Open`.

---

## 5. Prova in-boot (antes da contaminação de ambiente, secção 8)

### 5.1 — `cellVdecOpen`/`StartSeq` continuam 0 com o recipe natural actual

Boot armado, recipe canónico (`env_gow2.sh`) + `PS3_MOVIE_DONE_MS=auto` +
`PS3_NO_RSX=1` + `PS3_TRACE_MOVIEOBJ=1` + `PS3_VDEC_STATS=1`, 45–60 s, PID-kill:

```
[cellVdec] QueryAttrEx codec=0 -> memSize=4MB     (2 linhas = 1 chamada)
[cellVdec] Open ...                                0 ocorrências
[cellVdec] StartSeq ...                            0 ocorrências
FORCE SEQDONE                                       0 ocorrências (StartSeq nunca latch o watchdog)
[movieio]/[fs] open com "R_LglScA"/"R_PermA"/"wad_ps3" (case-insensitive)   0/63291 linhas
```

Confirma o "cellVdecQueryAttrEx chamado, Open nunca" do brief — **ainda
verdadeiro no código actual**, mas por uma razão diferente da suposta (secção 3).

### 5.2 — o trace `[EOSGATE]` apanha o momento exacto do desvio

Boot armado com `PS3_TRACE_SMPD=1` adicional (sondas pré-existentes de
`patch_smpd_probe.py`, sites já instrumentados em `func_002C05F8`/estado 3 e
`func_002C0788`/estado 10 — **não** instrumentado em `func_002C069C`/estado 4
por esta task ainda, ver secção 9):

```
[MOVIEFSM] st620 0 -> 1
[EOSGATE] site=002C07D8 val=0 branch=wait      (estado 1, ainda fresco)
[EOSGATE] site=002C05C8 val=0 branch=wait
[MOVIEFSM] st620 1 -> 3                          (via sticky FIOS, Task 8 — não via +0x744)
[MOVIEFSM] st620 3 -> 3   (parado, ~15s, duração ≈ do .wav SmLogo_v2.wav, 2 829 884 B / 192 512 B/s ≈ 14,7 s)
[MOVIEEOS] time-based done (st620=3) -> arming EOS read-hook at 0x00869F1C ([obj+0x744])
[MOVIEEOS] read-hook HIT [0x00869F1C]->1 ra=0x10183104c
[EOSGATE] site=002C05F8 obj=0x008697D8 ea=0x00869F1C val=1 branch=adv    <-- ESTADO 3 vê +0x744=1, desvia
[MOVIEEOS] read-hook HIT [0x00869F1C]->1 ra=0x101831fb8
[EOSGATE] site=002C0788 obj=0x008697D8 ea=0x00869F1C val=1 branch=adv    <-- ESTADO 10 (cascata continua)
[MOVIEEOS] read-hook HIT [0x00869F1C]->1 ra=0x1018329d0
[MOVIEFSM] st620 3 -> 0     (Stop/teardown fechou o ciclo; nenhum "site=002C069C" apareceu)
```

**Zero linhas `site=002C069C`** em toda a corrida — a prova directa (não só
inferida do grafo estático) de que o estado 4 nunca é despachado quando o
hook dispara enquanto `st620==3`.

---

## 6. Sondas adicionadas nesta task (read-only, gated, sem escrita de estado guest)

Ambas em `ps3recomp` (runtime, não-lift; não precisam de `patch_*.py`), sem
gate novo — reaproveitam o `PS3_DUMP_IMPORTS`/log incondicional já existente:

1. `libs/codec/cellVdec.c` — `[cellVdec] QueryAttrEx`/`Open` passam a incluir
   `lr=` (guest LR no momento da chamada) + `guest_stack_hint=` (scan de
   fallback já existente em `ppu_hle.cpp`/`g_last_hle_caller_lr`/
   `g_last_hle_caller_guest[4]`). **Resultado: `lr=0x0`, hints todos `0x0`** —
   este caminho específico não deu o caller (LR zera em cadeias de tail-call
   via `DRAIN_TRAMPOLINE`, e o scan POSIX do stack guest é só 0x40 bytes, curto
   demais). Não foi o que resolveu a questão — o grep estático de `tramp` (item
   2) foi o que funcionou; mantenho esta sonda por ser honesta e barata, não
   por ter sido decisiva.
2. `runtime/ppu/ppu_imports.cpp` — a linha `[imp-nid]` (gate `PS3_DUMP_IMPORTS`)
   passa a imprimir também `tramp=0x%08X` (o EA que o `bl` do jogo chama
   directamente), não só `slot=` (a célula de ponteiro que o tramp lê). Foi
   **esta** sonda que deu os endereços da secção 1.

Ambas foram apanhadas por um `git stash -u` de outra sessão (integração de
upstream a meio desta task — secção 8) e acabaram commitadas por essa sessão
em `ps3recomp` commit `2883a19` ("docs+diag: plano pos-st3/SMPD/WAD, INDEX, e
probes G4 de caller vdec"). Não as re-commitei eu — já estão em histórico,
com o conteúdo exacto que escrevi. Confirmado via `git show --stat 2883a19` e
`grep` dos marcadores (`g_last_hle_caller_lr`, `tramp=0x%08X`) no ficheiro
actual.

---

## 7. Fix honesto identificado, não implementado

**A hipótese com mais evidência:** o mecanismo de arm de EOS
(`movie_eos_arm.c`, produtor `PS3_MOVIE_DONE_MS=auto`) dispara com base em
**tempo de relógio** (duração real do `.wav`), sem olhar para o estado da
FSM. Isso está correcto para o que ele foi construído a resolver (Task 3 do
plano `macos-movie-eos-fsm`: sair do `st620=1`) mas **colide** com o
significado alternativo de `+0x744` nos estados 3/4 ("nada para abrir"). Um
fix fiel, sem forjar nada, seria: **só armar o hook depois de `st620` já ter
passado o estado 4** (ex.: gate adicional `st620>=5` na condição de arm, ao
lado do gate de tempo já existente) — assim os estados 3/4 continuam a ver
`+0x744==0` (verdade, o filme não acabou) e o `cellVdecOpenEx`/`StartSeq`
correm pela via natural do jogo; o hook só entraria em jogo para o que quer
que seja o gate de "vídeo realmente terminou" mais à frente (estado 5+, fora
do escopo desta task — não segui essa cadeia).

**Não implementei este fix** porque:

1. Exige editar `movie_eos_arm.c` — ficheiro listado explicitamente no brief
   como pertencente a outra sessão em curso (estava `M` no início desta task;
   passou a commitado, `04d651e`, a meio da minha sessão, como parte de um
   feature maior de PERF/LIFT_OPT dessa outra sessão). Editar por cima
   arriscava colidir com trabalho activo.
2. Mesmo que editasse, **não consigo verificar em boot agora** — secção 8.

**Não sei se este fix, sozinho, chega a abrir o WAD.** Mesmo que os estados
3→4 avancem naturalmente e `cellVdecOpenEx`/`StartSeq` corram, falta saber se
o WAD-loader (disparado por algum estado mais à frente, ainda não localizado
nesta task — não é o mesmo código que a FSM do movie player, dado que
`R_LglScA`/`R_PermA` nunca aparecem como string no lift, só via `cellFsOpen`
com o nome resolvido pelo `movie_io` do host) chega a ser invocado só por
`st620` avançar, ou se depende ainda de outro sinal a jusante (ex.: o próprio
SEQDONE do vídeo, que por sua vez precisaria do `PS3_VDEC_FORCE_SEQDONE_MS`
já portado para POSIX em `049fdf9` — esse watchdog HONESTAMENTE chama o
callback OPD do próprio guest, não escreve estado; seria a próxima peça a
testar, IF o estado 4 passar a correr).

---

## 8. Porque parei os boots ao vivo — contaminação de ambiente partilhado

A meio desta task, outra sessão fez `git stash push -u` + `git merge
upstream/master` (v0.7.0 "First Draw") em `ps3recomp`, seguido de correcções
de portabilidade e `git stash pop` — tudo dentro da MESMA árvore de trabalho
que eu estava a usar (confirmado via `git reflog`/`git log` em `ps3recomp`:
`25b0110` merge, `28367b2` fix portabilidade, `2883a19` stash-pop+commit). A
mesma sessão **rebuildou** `ps3recomp/build-macos/libps3recomp_runtime.a`
(mtime 09:41) e o `gow2-recomp/boot_gow2` partilhado (mtime 09:43) **por
cima** do binário que eu vinha a usar (build meu de 09:31, o que produziu toda
a secção 5).

O binário novo está com uma regressão que a PRÓPRIA sessão já documentou no
`ps3recomp/CLAUDE.md` (secção "Alternativa mais segura que merge total"):
*"como no merge v0.7 de 2026-07-21: st620 ficou 0, OOB stack"*. Reproduzi
isto directamente: corri o MESMO recipe que tinha dado a secção 5 (que
funcionava) contra o binário novo e `st620` fica preso em 0 a corrida
inteira, sem excepção — não é nondeterminismo nem efeito de qualquer coisa
que eu tenha mudado (não toquei `movie_eos_arm.c`, `ppu_loader.cpp`, nem
nada do caminho da FSM).

**Decisão:** parei de tentar boots ao vivo depois de confirmar a regressão
(2 corridas, ambas presas em `st620=0`, ambas limpas por PID — `pgrep -f
'boot_gow2 EBOOT'` = 0 no fim de cada uma). Insistir contra um binário
partilhado que a outra sessão está activamente a corrigir arriscava gastar
tempo a diagnosticar o problema ERRADO (o deles, não o meu) ou pisar o
trabalho deles. As secções 1–5 (achado principal, correcção do lead, e a
prova `[EOSGATE]`) foram todas obtidas **antes** desta contaminação, com o
binário de 09:31 — válidas e reprodutíveis independentemente disto assim que
o `boot_gow2` partilhado voltar a um estado São (a RE estática, secções 1–3,
é 100% independente de qualquer binário — é leitura de texto do lift).

---

## 9. O que não resolvi

**Se o gate do estado 3 (`func_0045B2A8`/`obj+0x720`, agora identificado como
sessão de ÁUDIO) alguma vez resolve sozinho, sem qualquer hook do host.** A
experiência discriminadora óbvia (`PS3_MOVIE_EOS=0`, deixar correr 45-50s sem
armar nada, ver se `st620` sai de 3 por si) foi tentada duas vezes (`run5`,
`run6`) mas caiu exactamente na janela da contaminação da secção 8 — os dois
resultados mostram `st620` preso em **0** (nem chega a 1), inconsistente com
todas as corridas anteriores desta sessão e com o baseline histórico, então
não os conto como medição válida desta questão (são medição válida da
regressão da outra sessão, não da minha pergunta).

Isto importa porque decide se o fix da secção 7 basta sozinho: se
`+0x1B8` do handle de áudio progride por si via o `cellAudio` HLE real (que
existe, `libs/audio/cellAudio.c`, 7 funções resolvidas nesta build) mais o
polling que o próprio jogo já faz, então "só atrasar o arm para depois do
estado 4" é suficiente. Se `+0x1B8` só é escrito por um caminho que a nossa
HLE de áudio não completa (ex.: um sub-evento específico do `snd_stream` que
não implementámos), o estado 3 ficaria parado para sempre sem o hook, e o
mesmo fix da secção 7 teria de incluir também um produtor honesto para ESSE
campo (não escrevê-lo directo — chamar o que quer que o jogo espere, no
mesmo espírito do watchdog SEQDONE do vídeo). Não segui `func_004479E8` /
a tabela geracional (`TOC-0x394`, stride `0x1E4`) nem o resto do subsistema
`cellAudio`/`snd_stream` para responder isto — fica para quem continuar.

---

## 10. Regras honradas

- Nenhum `vm_write` de host a `st620`, `obj+0x744`, `obj+0x720`,
  `obj+0x668`, ou qualquer campo de sessão. Todas as sondas (secção 6) só
  leem e imprimem valores já computados pelo próprio guest/HLE existente.
- Nenhum fix aplicado — só diagnóstico. Não tentei "destravar" nada por
  escrita directa em nenhum momento, mesmo depois de identificar o mecanismo
  exacto.
- `M3` (forge-trap: `PS3_MOVIE_EOS=1` sem produtor ⇒ zero arm) não foi
  re-executado nesta task (não mudei nada que o pudesse afectar — as duas
  sondas são só `fprintf` adicionais numa linha já incondicional/já gated
  por `PS3_DUMP_IMPORTS`), mas também não foi verificado de novo por falta
  de um binário são no fim da sessão (secção 8). Recomendo à próxima sessão
  reconfirmar M3 assim que o `boot_gow2` partilhado estabilizar.
- Todos os boots mortos por PID (`TERM` depois `-9`, `wait`, sem `pkill`
  genérico). `pgrep -f 'boot_gow2 EBOOT'` = 0 confirmado depois de cada uma
  das 6 corridas desta task (nenhum órfão deixado).
- Não toquei `build_macos.sh`, `movie_eos_arm.c`, `smoke_perf_macos.sh`,
  `boot_gow2_O1` (ficheiros de outra sessão) nem `ppu_loader.cpp` do
  `ps3recomp` (idem — tinha WIP de PERF/fairness de outra sessão quando
  cheguei).
- Linhas de nota antiga (`2026-07-20-st620-3to0-static.md`, linha
  425951 para `func_0045B2A8`) foram re-verificadas, não assumidas — o lift
  já tinha sido regerado e a linha real é 426000. Confirma a própria regra
  do projecto ("nunca confiar em linha de plano antigo").

---

## Ficheiros/EAs citados (para quem continuar)

| O quê | Onde |
|---|---|
| Estado 3 (gate `+0x744`, 1ª pergunta) | `recomp_macos_v2/ppu_recomp_001.cpp:36610` (`func_002C05F8`), branch :36629 |
| Estado 4 (Open+StartSeq) | `recomp_macos_v2/ppu_recomp_001.cpp:36675` (`func_002C069C`), branch :36686, calls :36727/:36730 |
| Cadeia `+0x746`/áudio | `recomp_macos_v2/ppu_recomp_002.cpp:224843` (`func_002C0688`), `:224852` (`func_002C0694`), `:224858` (`func_002C0FA0`) |
| Gate de áudio (mal identificado antes como vdec) | `recomp_macos_v2/ppu_recomp_001.cpp:426000` (`func_0045B2A8`) |
| Handle de vídeo real (OpenEx output) | `obj+0x668` (não `obj+0x720`) |
| Handle de áudio (snd_stream, é o `obj+0x720`) | escrito por `func_0045E230`, doc `2026-07-20-macos-intro-audio-open-wall.md` §(a) |
| Trampolins do import `libvdec` | OpenEx=`0x004B9398`, StartSeq=`0x004B9458`, QueryAttrEx=`0x004B9478` (via `PS3_DUMP_IMPORTS=1`) |
| Sondas novas (read-only) | `ps3recomp` commit `2883a19` — `libs/codec/cellVdec.c`, `runtime/ppu/ppu_imports.cpp` |
| Regressão de ambiente (não-minha) | `ps3recomp/CLAUDE.md` §"Alternativa mais segura que merge total"; commits `25b0110`/`28367b2`/`2883a19` |

---

## 11. Reconfirmação RED em binário recuperado — 2026-07-21 (Task 1, plano de bring-up macOS/arm64)

Medição pura (sem alteração de código), Task 1 do plano de bring-up
macOS/arm64 (`gow2-recomp/.superpowers/sdd/task-1-brief.md`). Entre a
secção 8 (contaminação de ambiente pelo merge v0.7 concorrente) e agora,
outra sessão **recuperou** o motor (`ps3recomp` commit `11a1c3c`); esta
task reconfirma formalmente que a parede da secção 5.2 continua verdadeira
no binário recuperado, antes de qualquer fix (Task 1 é RED baseline; o fix
fica para task posterior). `boot_gow2` usado: rebuild de 21/jul 10:20
contra o motor recuperado, árvore limpa, sem tocar `movie_eos_arm.c`.
Ambas as corridas mortas por PID (`TERM`→`-9`→`wait`); `pgrep -f
boot_gow2 | wc -l` = 0 confirmado após cada uma (nenhum órfão; a caixa
usa o `pgrep` BSD do macOS, que não tem `-c`).

**Passo 1 — M0 (sem arm), `/tmp/vdec_m0.log`, 30s:**

| métrica | valor |
|---|---|
| st620 max | 3 (0→1→3→3 sticky) |
| cellVdec Open | 0 |
| StartSeq | 0 |
| wad (R_LglScA/R_PermA) | 0 |
| órfãos pós-kill | 0 |

GREEN confirmado (`st620≥3` — motor efectivamente recuperado; `Open=0` é
esperado em M0, não é regressão).

**Passo 2 — RED, arm cedo (`PS3_MOVIE_EOS=1 PS3_MOVIE_DONE_MS=4000
PS3_VDEC_FORCE_SEQDONE_MS=8000`), `/tmp/vdec_red.log`, 45s:**

| métrica | valor | esperado |
|---|---|---|
| arm | 1 | ≥1 |
| hit | 3 | ≥1 |
| open | 0 | ==0 |
| start | 0 | ==0 |
| force | 0 | ==0 |
| st4 (`site=002C069C`) | 0 | ==0 |
| wad | 0 | ==0 |

RED confirmado, 7/7 métricas batem com o esperado. Narrativa igual à
secção 5.2: hook arma em `st620=3` (`0x00869F1C`), 2 hits desviam os
estados 3 e 10 (`site=002C05F8`, `site=002C0788`) para a cascata
`st620 3→0`, e `site=002C069C` (estado 4, onde vivem
`cellVdecOpenEx`/`StartSeq`) nunca dispara — 0 WADs. Confirma que a
parede não era artefacto do binário regredido da secção 8: persiste,
idêntica, no motor recuperado. Fix continua o da secção 7 (gate
`st620>=5` adicional no arm), não aplicado aqui (fora de escopo desta
task).
