# Ghidra MCP — montagem para a próxima sessão (2026-08-03)

> **Estado honesto (regra G5/4):** extensão **compilada e instalada**, projecto Ghidra
> **analisado e persistido**, ponte Python **a arrancar**, servidor `ghidra` **registado**
> no `~/.claude.json`. **NÃO está "a funcionar" ponta-a-ponta** — faltam **2 passos que só
> o humano faz** (abrir a GUI do Ghidra + reiniciar a sessão do Claude Code). Ver §6.
>
> Máquina: macOS/arm64. Caminho usado: **caminho 2 (build fiel contra o Ghidra 12.1.2)** —
> **NÃO** foi preciso o plano B (remendo do `extension.properties`). A compilação passou
> limpa, sem quebras de API 11→12.
>
> Contexto/política: [`docs/GHIDRA_MCP_SETUP.md`](../../../docs/GHIDRA_MCP_SETUP.md) —
> MCP = **leitura e anotação**; whitelist §5, proibidos §6. Isto aqui só monta a
> ferramenta; a política de uso não muda.

---

## 1. Ambiente (confirmado, não re-descoberto)

| item | valor medido |
|---|---|
| Ghidra | `12.1.2` em `/opt/homebrew/Cellar/ghidra/12.1.2` (symlink `/opt/homebrew/opt/ghidra`), `application.version=12.1.2`, release `PUBLIC` |
| `GHIDRA_INSTALL_DIR` | `/opt/homebrew/opt/ghidra/libexec` |
| JDK 21 (keg-only) | `/opt/homebrew/opt/openjdk@21` → `openjdk 21.0.12` (o Ghidra 12 exige 21) |
| JDK no PATH | `17.0.20` (insuficiente para compilar contra jars do Ghidra 12 → usei o 21 explicitamente) |
| EBOOT | `/Users/andrebrumcortezferreira/Documents/PESSOAL/gow2-recomp/EBOOT.ELF` (5 673 936 bytes) |
| user settings dir do Ghidra | `~/Library/ghidra/ghidra_12.1.2_PUBLIC/` (é aqui que vivem as Extensions no macOS) |

**Nada de dados de jogo, clones ou projecto Ghidra entrou nos repos** — tudo em `~/`
(`~/tools/GhidraMCP`, `~/ghidra_projects/gow2`). O EBOOT ficou onde já estava.

---

## 2. Passos executados, comando a comando (com `rc` real)

### Passo 1 — Maven
```bash
/opt/homebrew/bin/brew install maven          # rc=0 (puxou openjdk 26 como dep)
mvn -v                                         # rc=0 -> Apache Maven 3.9.16 (corre em Java 17)
```

### Passo 2 — clonar + COMPILAR contra o Ghidra 12.1.2 (caminho fiel)
```bash
git clone https://github.com/LaurieWired/GhidraMCP.git ~/tools/GhidraMCP   # rc=0
# HEAD == tag 1.4 == commit 27f316f80139e2d5dec882519a1bdf4aa46ac04c
# (releases API: 1.4 e' a mais recente; NAO ha' release > 1.4. O pin do doc esta' certo.)

# copiar os 8 jars do Ghidra 12.1.2 para lib/ (lista do README "Building from Source")
G=/opt/homebrew/opt/ghidra/libexec
cp "$G/Ghidra/Features/Base/lib/Base.jar"                         ~/tools/GhidraMCP/lib/
cp "$G/Ghidra/Features/Decompiler/lib/Decompiler.jar"            ~/tools/GhidraMCP/lib/
cp "$G/Ghidra/Framework/Docking/lib/Docking.jar"                ~/tools/GhidraMCP/lib/
cp "$G/Ghidra/Framework/Generic/lib/Generic.jar"               ~/tools/GhidraMCP/lib/
cp "$G/Ghidra/Framework/Project/lib/Project.jar"               ~/tools/GhidraMCP/lib/
cp "$G/Ghidra/Framework/SoftwareModeling/lib/SoftwareModeling.jar" ~/tools/GhidraMCP/lib/
cp "$G/Ghidra/Framework/Utility/lib/Utility.jar"               ~/tools/GhidraMCP/lib/
cp "$G/Ghidra/Framework/Gui/lib/Gui.jar"                       ~/tools/GhidraMCP/lib/

# declarar 12.1.2 (extensao FIEL, nao remendo): extension.properties e pom.xml
#   src/main/resources/extension.properties: version/ghidraVersion 11.3.2 -> 12.1.2
#   pom.xml: os 8 <version>11.3.2</version> das deps ghidra -> 12.1.2

# build com JDK 21
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
mvn -q -DskipTests clean package               # rc=0  <-- passou SEM quebras de API 11->12
```

Artefactos produzidos (`~/tools/GhidraMCP/target/`):
```
GhidraMCP-1.0-SNAPSHOT.zip    (extensao Ghidra)
GhidraMCP.jar                 (o plugin)
```

### Passo 3 — instalar a extensão (ficheiro, sem GUI)
```bash
D=~/Library/ghidra/ghidra_12.1.2_PUBLIC/Extensions
mkdir -p "$D"
unzip -o ~/tools/GhidraMCP/target/GhidraMCP-1.0-SNAPSHOT.zip -d "$D"   # rc=0
# -> $D/GhidraMCP/{extension.properties, Module.manifest, lib/GhidraMCP.jar}
# extension.properties instalado declara: version=12.1.2  ghidraVersion=12.1.2
```
Colocar o ficheiro **não** precisa da GUI. **Activar** o plugin precisa (passo humano, §6).

### Passo 4 — projecto Ghidra PERSISTIDO com o EBOOT analisado
```bash
# analyzeHeadless com JDK 21, SEM -deleteProject, projecto fica em disco
JAVA_HOME=/opt/homebrew/opt/openjdk@21 \
/opt/homebrew/opt/ghidra/libexec/support/analyzeHeadless \
  ~/ghidra_projects/gow2 gow2 \
  -import /Users/andrebrumcortezferreira/Documents/PESSOAL/gow2-recomp/EBOOT.ELF \
  -overwrite -analysisTimeoutPerFile 3600         # rc=0  (~8,6 min de auto-analise)
# script reutilizavel: ~/ghidra_projects/run_headless_gow2.sh
# log: ~/ghidra_projects/headless_gow2.log
```
Log final: `Analysis succeeded` / `Import succeeded` / `Save succeeded for: /EBOOT.ELF
(gow2:/EBOOT.ELF)`. Linguagem auto-detectada: **`PowerPC:BE:64:A2ALT:default`** (PPU Cell).

### Passo 6 — ponte Python + registo no cliente
```bash
# venv fora dos repos (Python 3.14.6; o system 3.9 nao serve — mcp exige >=3.10)
/opt/homebrew/bin/python3 -m venv ~/tools/GhidraMCP/.venv
~/tools/GhidraMCP/.venv/bin/python -m pip install 'mcp==1.5.0' 'requests==2.32.3'  # rc=0
~/tools/GhidraMCP/.venv/bin/python bridge_mcp_ghidra.py --help                      # rc=0 (imports carregam)

# registo no ~/.claude.json (backup primeiro, edicao cirurgica)
cp ~/.claude.json ~/.claude.json.bak-ghidra-mcp
# -> adicionado o server "ghidra" ao mcpServers de topo, SEM apagar "MCP_DOCKER"
```

---

## 3. Caminho usado: **2 (build)**, não plano B

A compilação contra os jars do Ghidra 12.1.2 **passou limpa** (`mvn ... clean package` → rc=0).
Logo a extensão instalada foi **construída de raiz contra a API 12.1.2** e o
`extension.properties` declara **`12.1.2`** de verdade — **não** é o remendo do plano B
(pegar na build de 11.3.2 e mudar só o campo de versão). Sem risco de runtime por
incompatibilidade de API, porque foi compilada contra as classes desta versão.

---

## 4. Versão exacta da extensão + sha

| campo | valor |
|---|---|
| repo | `LaurieWired/GhidraMCP` |
| fonte (commit) | `27f316f80139e2d5dec882519a1bdf4aa46ac04c` (== tag `1.4`, o mais recente) |
| construída contra | Ghidra **12.1.2** (8 jars locais) + JDK **21.0.12** |
| declara | `version=12.1.2`, `ghidraVersion=12.1.2` |
| `GhidraMCP-1.0-SNAPSHOT.zip` sha256 | `c63bba6375a4a5f437f0ff12f64db4e2f4b918a39e3bf3e9c644382320360b80` |
| `GhidraMCP.jar` sha256 | `f33f7b506b8579e89a7649e2b0775780a7bddd8a3c7efc5c45c96aa87d060516` |
| instalada em | `~/Library/ghidra/ghidra_12.1.2_PUBLIC/Extensions/GhidraMCP/` |

*(A build não é bit-reprodutível — o sha do zip depende de timestamps do Maven; fica
registado como identidade **desta** build, não como pin verificável por terceiros.)*

---

## 5. Projecto Ghidra — onde ficou e prova de que persiste

```
~/ghidra_projects/gow2/
  gow2.gpr        (0 bytes — NORMAL num projecto local; e' so' o descritor)
  gow2.rep/       (17 MB — a base de dados do programa ja' analisado)
    idata/00/~00000000.db   <- o EBOOT.ELF analisado, guardado
```
Provas de persistência:
- `du -sh gow2.rep` → **17M** (auto-análise gravada em disco).
- log: `Save succeeded for: /EBOOT.ELF (gow2:/EBOOT.ELF)`.
- **sem** `*.lock` no fim → o projecto foi libertado, pronto a abrir na GUI.
- **`-deleteProject` NÃO foi usado.**

Isto é o que evita a re-análise de "dezenas de minutos" a cada arranque: o humano só
tem de **abrir** este projecto; a análise já está feita.

> É **dado de jogo** (o EBOOT está lá dentro): fica **FORA do git**, nunca commitado.

---

## 6. O QUE FALTA — 2 passos que SÓ O HUMANO faz (checklist copy-paste)

O MCP não pode ficar "ligado" por um agente: (a) activar um plugin do Ghidra é GUI, e
(b) uma sessão do Claude Code já a correr **não** adquire tools MCP a meio — só lê o
`~/.claude.json` ao arrancar.

### PASSO HUMANO A — abrir o Ghidra e ligar o plugin (serve o EBOOT no porto 8080)
```
1. Lançar a GUI:            ghidraRun
2. Se o Ghidra avisar "New extension(s) detected" -> aceitar/OK.
   (Ou confirmar em:  File -> Install Extensions -> "GhidraMCP" deve estar marcado.)
   Se acabaste de marcar agora, REINICIA o Ghidra uma vez.
3. Abrir o projecto ja' analisado:
   File -> Open Project -> ~/ghidra_projects/gow2/gow2.gpr
4. Abrir o programa: duplo-clique em  EBOOT.ELF  (abre a janela CodeBrowser).
5. Ligar o plugin:  File -> Configure -> "Developer" -> marcar  GhidraMCPPlugin  -> OK.
   (O plugin sobe um servidor HTTP em  http://127.0.0.1:8080/ .)
6. (Opcional) mudar o porto:  Edit -> Tool Options -> "GhidraMCP HTTP Server".
   Se mudares o porto, muda tambem o --ghidra-server no ~/.claude.json (§7).
```
Confirmar que o servidor do plugin está vivo (com o EBOOT aberto):
```bash
curl -s http://127.0.0.1:8080/methods | head      # deve devolver dados, nao "connection refused"
```

### PASSO HUMANO B — reiniciar a sessão do Claude Code
```
1. Fechar ESTA sessao do Claude Code.
2. (rede de seguranca) confirmar que o server 'ghidra' ainda esta' no config,
   porque uma sessao a correr pode reescrever o ~/.claude.json ao sair:
       python3 -c "import json,os;d=json.load(open(os.path.expanduser('~/.claude.json')));print(list(d['mcpServers']))"
   Esperado:  ['ghidra', 'MCP_DOCKER']
   Se 'ghidra' tiver desaparecido, reaplicar o snippet da §7 (ou restaurar do backup e reaplicar).
3. Abrir uma NOVA sessao do Claude Code neste repo.
4. Verificar que as tools apareceram:  /mcp   (deve listar o servidor 'ghidra').
   As tools chamam-se  mcp__ghidra__decompile_function, mcp__ghidra__get_xrefs_to, etc.
```
Só depois destes dois passos é que a próxima sessão tem o Ghidra **ao vivo**. Enquanto
não acontecerem, o `RE-03` fecha na mesma pelo caminho duro (playbook + `ghidra_lookup.py`).

Teste de fumo de 1 minuto para a próxima sessão (paridade §8/§9 do doc de política):
pedir `get_xrefs_to` / `get_function_xrefs` para `0x00420A44` — **tem de** conter
`0x00254C40` (o controlo positivo já medido offline). Se não contiver → falha, registar.

---

## 7. Registo no `~/.claude.json` — FEITO (edição cirúrgica, reversível)

- **Backup:** `~/.claude.json.bak-ghidra-mcp` (sufixo fixo, criado antes da edição).
- Adicionado o server `ghidra` ao `mcpServers` de **topo**, ao lado de `MCP_DOCKER`
  (que ficou intacto). JSON validado após a edição; `mcpServers` = `['ghidra','MCP_DOCKER']`.
- **Aviso honesto:** entre o backup e a edição o próprio Claude Code reescreveu o ficheiro
  (contadores de sessão) — a edição foi aplicada ao estado **corrente**, mas uma sessão a
  correr **pode** reescrever o `~/.claude.json` ao sair e apagar o `ghidra`. Por isso o
  passo B pede para **verificar** antes de abrir a sessão nova.

Snippet exacto (para reaplicar/colar se necessário — o bloco `ghidra` dentro de `mcpServers`):
```json
"ghidra": {
  "command": "/Users/andrebrumcortezferreira/tools/GhidraMCP/.venv/bin/python",
  "args": [
    "/Users/andrebrumcortezferreira/tools/GhidraMCP/bridge_mcp_ghidra.py",
    "--ghidra-server",
    "http://127.0.0.1:8080/"
  ]
}
```
> O `command` aponta directo ao Python do venv (`~/tools/GhidraMCP/.venv`) — tem o
> `mcp==1.5.0` + `requests==2.32.3`; não depende do `python3` do PATH (system 3.9, que não
> serve). O `~/.claude.json` nunca é commitado (fora do repo).

---

## 8. Segurança (política do doc, §4.3/§6)

- Servidor do plugin em `127.0.0.1:8080` — **nunca** `0.0.0.0`. Sem autenticação: aceita
  POSTs que **renomeiam/comentam** na base do Ghidra. Desligar (fechar o Ghidra) quando não
  estiver em uso.
- Uso permitido: **leitura + anotação na base do Ghidra**. Proibido: export/rewrite do
  programa, patch de bytes, gerar `ppu_recomp_*.cpp`/produto, substituir o oráculo estático
  (`ghidra_out/` + `MANIFEST.json`). O CI **não** depende disto.

---

## 9. Reverter (se preciso)

```bash
# tirar o server do config:
cp ~/.claude.json.bak-ghidra-mcp ~/.claude.json     # (ou apagar so' o bloco "ghidra")
# remover a extensao:
rm -rf ~/Library/ghidra/ghidra_12.1.2_PUBLIC/Extensions/GhidraMCP
# (e desmarcar GhidraMCPPlugin na GUI se ja' foi activado)
# o clone, o venv e o projecto Ghidra sao descartaveis:
rm -rf ~/tools/GhidraMCP ~/ghidra_projects/gow2
```

---

## 10. Resumo de uma linha

Extensão **compilada fiel contra o 12.1.2** + **instalada**, projecto Ghidra do EBOOT
**analisado e persistido** (`~/ghidra_projects/gow2`, 17 MB), ponte Python **ok**, server
`ghidra` **registado** no `~/.claude.json` — **faltam os 2 passos humanos** (§6): abrir a
GUI e ligar o `GhidraMCPPlugin` com o projecto/EBOOT aberto, e **reiniciar** a sessão do
Claude Code.

---

## 11. Re-semear com 13k — projecto `gow2_full` (2026-08-04)

**Problema:** o projecto do §5 (`~/ghidra_projects/gow2`) foi importado com a linguagem
**auto-detectada** `PowerPC:BE:64:A2ALT:default` → só **1 488** funções (a `.opd` não é
processada, logo os ~13 mil descritores de função não viram funções). O export estático bom
(`../gow2-recomp/ghidra_out`, **13 143** funções) foi feito com **`-processor
PowerPC:BE:64:64-32addr`** (o default do `tools/ghidra_analyze.py:35`). **Fix: reimportar
com o processador certo, num projecto NOVO** (o antigo estava aberto/trancado na GUI —
`gow2.lock` presente — e **não** foi tocado).

### Comando exacto (corrido em background, ~1 min)
```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@21          # Ghidra 12 exige JDK 21 (keg-only)
export PATH="$JAVA_HOME/bin:$PATH"
mkdir -p ~/ghidra_projects/gow2_full /tmp/gow2_full_verify
/opt/homebrew/opt/ghidra/libexec/support/analyzeHeadless \
  ~/ghidra_projects/gow2_full gow2_full \
  -import /Users/andrebrumcortezferreira/Documents/PESSOAL/gow2-recomp/EBOOT.ELF \
  -processor PowerPC:BE:64:64-32addr \
  -scriptPath /Users/andrebrumcortezferreira/Documents/PESSOAL/ps3recomp/tools/ghidra \
  -postScript ExportAnalysisJson.java /tmp/gow2_full_verify \
  -analysisTimeoutPerFile 3600
```
- **SEM `-deleteProject`** (o projecto tem de ficar em disco para a GUI/MCP o servir).
- `-postScript ExportAnalysisJson.java /tmp/gow2_full_verify` só serve para **verificar** a
  contagem (JSON descartável, fora dos dois repos, nunca commitado). Sem `decompile` (o
  count vem só do `functions.json`, que é rápido).
- Diferença-chave vs. §4: **`-processor PowerPC:BE:64:64-32addr`** explícito e **sem**
  `-deleteProject`.

### `rc` e verificação REAL (regra G5/4 — contar JSON, não linhas)
| item | valor medido |
|---|---|
| `ANALYZE_RC` | **0** (`Analysis succeeded` / `Save succeeded for: /EBOOT.ELF (gow2_full:/EBOOT.ELF)` / `Import succeeded`) |
| log da GhidraScript | `[export] functions: 13143` |
| **`functions.json` parseado** (`json.load`, `len()`) | **13 143** ✓ (idêntico ao export bom de referência) |
| dos quais `.opd.FUN_*` | **13 006** (o que o A2ALT perdia) |
| símbolos | 114 065 |
| **`0x0041F700` presente** | **SIM** → `{"addr":"0x0041F700","size":296,"name":".opd.FUN_0041f700",...}` |
| `~/ghidra_projects/gow2_full/gow2_full.gpr` | existe (0 bytes — normal, é só o descritor) |
| `~/ghidra_projects/gow2_full/gow2_full.rep` | **97 MB** (base de dados analisada, persistida) |
| lock no projecto novo | **nenhum** (libertado, pronto a abrir na GUI) |
| projecto antigo `~/ghidra_projects/gow2` | **intacto** (`gow2.lock` continua lá) |

> `13 143` (não `1 488`): o processador **resolveu** a `.opd`. Log: `~/ghidra_projects/headless_gow2_full.log`.

### Passo do humano na GUI — trocar o MCP para este projecto
O `GhidraMCPPlugin` serve o programa **activo** no CodeBrowser (não o projecto em si). Com o
plugin já activado (§6), basta:
```
1. File -> Open Project -> ~/ghidra_projects/gow2_full/gow2_full.gpr
   (pode fechar o programa/projecto 'gow2' antigo antes, ou deixar ambos abertos)
2. Duplo-clique em EBOOT.ELF (abre o CodeBrowser com as 13 143 funções)
3. Confirmar que serve as 13k:
     curl -s http://127.0.0.1:8080/methods | head       # servidor vivo
   Pedir get_function_by_address 0x0041F700 -> deve devolver .opd.FUN_0041f700
```
Nada mais a reiniciar: o servidor HTTP do plugin passa a responder sobre o programa que
ficar em foco no CodeBrowser. Se o Ghidra já estava aberto no `gow2` antigo, é só abrir o
`gow2_full` e pôr o EBOOT dele em foco.
