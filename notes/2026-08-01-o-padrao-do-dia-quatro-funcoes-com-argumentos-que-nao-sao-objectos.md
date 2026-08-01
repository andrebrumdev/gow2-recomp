# O padrão do dia: quatro funções a receber argumentos que não são objectos

**Data:** 2026-08-01 · Tudo medido, com o número de corridas indicado em cada caso.

Passei o dia a caçar quem estraga memória. Encontrei **um** caso real e corrigi-o (o
`F2B-STREAM-PUMP`, ver a nota da causa raiz). Mas os sintomas que sobraram têm outra
natureza, e o `PS3_WATCH_STORE` mostrou-o **quatro vezes**: ninguém estraga bytes. A
memória escrita está toda correcta onde foi escrita.

O que há é **despacho**: funções a correr com `this`/argumentos que não são o que elas
assumem.

| # | função | o que devia ser | o que lá está | corridas |
|---|---|---|---|---|
| 1 | `func_002545D4` | `rec`, payload do nó | **`0`** → lê "tipo" do endereço guest 2 | 4/4 |
| 2 | `func_002545B0` (2.ª chamada) | objecto com lista em `+0x7C` | objecto cuja `+0x7C` é `matriz[0][3]` | 1/1, com contra-exemplo são ao lado |
| 3 | `func_00263554` | `pool` | **`5`** → lê `*(9)` | 1/1 |
| 4 | `func_00220284` | `this` | **`0`** → lê os campos de memória baixa | 1/1 |

## O #4 é o mais limpo, e prova a direcção

A sonda `PS3_TRACE_CPY284` mostra **12 chamadas perfeitamente sãs** e depois uma má:

```
[CPY284] #11 this=0x407D44F0 n=8 p50=0x407CFD20 dst60=0x407CE840 p5C=0x407CE7C0
[CPY284] #12 this=0x407D46E8 n=3 p50=0x407CFF54 dst60=0x00000000 p5C=0x407E4E50
[CPY284] #13 this=0x00000000 <THIS-MAU> n=4 p50=0x4077CAB8 dst60=0x00000000 ...
```

E a correlação com as escritas más é **linha a linha, no mesmo log**:

```
4391: [CPY284] #13 this=0x00000000 <THIS-MAU>
4392: [vm] UNCOMMITTED write32 access 0x726D5B32 ra=func_00220284+0x1244
4393: [vm] UNCOMMITTED write32 access 0x726D5B3A ra=func_00220284+0x1274
4394: [vm] UNCOMMITTED write32 access 0x726D5B2E ra=func_00220284+0x12A4
4395: [vm] UNCOMMITTED write32 access 0x726D5B36 ra=func_00220284+0x12D4
4396: [vm] UNCOMMITTED write32 access 0x726D5B42 ra=func_00220284+0x1244   (ciclo)
```

Com `this = 0`, a função lê os seus próprios campos da base da memória guest
(`*(0x50)`, `*(0x60)`, `*(0x68)`…), apanha valores que *parecem* ponteiros, e escreve
quatro floats por iteração através deles. **As escritas por ponteiro-texto que persegui
duas rondas são consequência, não causa.**

## O que isto invalida do que escrevi hoje

- *"A free-list do allocator tem uma string lá dentro"* — **errado**. O `pool` é que vale
  `5`; não há lista nenhuma envolvida.
- *"É corrupção de memória a montante"* — **errado** para estes quatro. Há uma corrupção
  real e corrigida (o pump), mas não é esta.

## Onde isto põe o trabalho

Deixa de fazer sentido caçar escritores. O que interessa agora é **quem escolhe o alvo e
os argumentos da chamada**, e para isso existe agora a ferramenta certa:

- `PS3_TRACE_ICALL_TO=0xEA` — apanha o despacho no ponto de resolução, com `r3/r4/r5` e a
  cadeia host simbolizada. Foi assim que se apanharam as duas únicas chamadas a
  `0x002545B0` de uma corrida inteira.
- Sonda na **entrada** da função chamada — o único método que se provou fiável neste lift
  para atribuir uma chamada indirecta. Nem o `lr` do guest nem o rbp frame walk servem
  (ambos me mandaram para funções erradas hoje, cada um custou uma ronda).

**Próxima medição:** `PS3_TRACE_ICALL_TO=0x00220284` — quem despacha para lá com `r3=0`,
e com que `this` as 12 boas foram despachadas. Se as boas vierem de um sítio e a má de
outro, o defeito fica reduzido a um único call site.

## O estado do objectivo

**O menu continua por alcançar.** Gate 0/6, elo `AUTO_LOAD`. O que mudou hoje é que a
investigação deixou de ser "o boot pára algures" e passou a ter quatro sintomas do mesmo
mecanismo, nomeados à função e ao argumento, com contra-exemplos sãos medidos ao lado de
cada um.
