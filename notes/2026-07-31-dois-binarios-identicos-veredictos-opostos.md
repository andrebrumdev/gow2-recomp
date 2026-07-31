# Dois binários byte-idênticos deram veredictos opostos

**Data:** 2026-07-31 · **Descoberto por:** o planeador da Fase 9, ao preparar o bisect.
**Estado: confirmado quanto à identidade; a medição repetida está a correr.**

## O facto

```
$ md5 -q boot_gow2.pre_v3 boot_gow2.pre_v4
ef5f53ef71f1eb3f6230a2ff3ac55dad
ef5f53ef71f1eb3f6230a2ff3ac55dad
$ cmp boot_gow2.pre_v3 boot_gow2.pre_v4 && echo IDENTICOS
IDENTICOS
```

**São o mesmo binário.** E a tabela do `bisect_regression.sh`, corrida sobre os nove,
registou-os assim:

```
boot_gow2.pre_v3   25 Jul 18:23   4111 linhas   StartSeq=2  thr_end=1  r_perma=1   OK
boot_gow2.pre_v4   25 Jul 18:23    813 linhas   StartSeq=0  thr_end=0  r_perma=0   REGRESSAO
```

O mesmo ficheiro, medido duas vezes na mesma sessão, com a mesma recipe, deu
`StartSeq=2 / thr_end=1` numa corrida e `StartSeq=0 / thr_end=0` na outra.

## O que isto implica, se se confirmar

**Não há necessariamente um commit que "partiu" o boot.** A falha pode ser
**não-determinista** — e nesse caso:

1. **O bisect da Fase 9 procuraria um commit que não existe.** Um `git bisect` sobre uma
   falha intermitente converge para um inocente qualquer, com confiança total e resultado
   errado.
2. **Os nove candidatos eliminados foram-no correctamente**, mas por uma razão que não
   sabíamos: não havia nada partido para reverter.
3. **As quatro corridas iniciais desta investigação** (todas `REGRESSAO`, que foi o que
   fez levantar a hipótese de regressão) podem ter sido uma sequência infeliz.
4. **O `boot_gow2.pre_v3` "que funciona"** pode simplesmente ter tido sorte na corrida que
   o classificou.

## O que já apontava para aqui, e não foi seguido

- A **Fase 7 observou flakiness de timing sob carga** e documentou-a — mas tratou-a como
  ruído a descartar, não como sinal sobre a natureza da falha.
- O `smoke_relift_equiv.sh` do marco v1.0 tem um **discriminador FLAKE/REGRESSAO** e um
  portão de **≥4 em 6 corridas** — ou seja, o projecto já sabia que uma corrida só não
  decide. **Todas as medições desta investigação usaram UMA corrida por binário.**
- O `FATAL 0` em todas as corridas: o boot não falha, **pára**. Uma race condition ou um
  deadlock intermitente encaixa; um bug determinista de código gerado encaixa pior.

## O erro de método, e é meu

Corri o bissect inteiro — nove binários — com **uma corrida cada**, e tratei cada
resultado como veredicto. O próprio projecto tinha um portão de 4-em-6 para isto, escrito
no marco anterior, e eu não o apliquei ao bissect.

Pior: **eu escrevi no contexto da Fase 9 que "uma corrida por passo do bisect chega"**,
com a justificação de que o gate de seis é só para o aceite final. Estava errado — se a
falha é intermitente, uma corrida por passo é exactamente o que faz o bisect mentir.

## A medição a decorrer

Cinco corridas do **mesmo** `boot_gow2.pre_v3`, mesma recipe, mesmo ambiente. O resultado
decide o rumo:

| desfecho | significado | consequência |
|---|---|---|
| 5/5 `OK` | o registo do `pre_v4` foi um artefacto isolado | o bisect faz sentido, mas com N corridas por passo |
| mistura `OK`/`REGRESSAO` | **a falha é não-determinista** | o bisect não se aplica; o problema é uma race |
| 5/5 `REGRESSAO` | o `pre_v3` nunca foi bom | a janela inteira está mal posta |

## Ressalva

Neste momento só está **confirmada a identidade dos ficheiros**. A conclusão sobre
não-determinismo é hipótese até as cinco corridas terminarem. Não alterar planos nem
retirar conclusões antes disso.
