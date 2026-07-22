# RE do rig/animação do GoW2 HD — esqueleto, skinning e pacote ANMX (r_hero01)

Data: 2026-07-22. Fonte: `wad/r_hero01.wad_ps3` **de dentro do `gow2.psarc`**
(extração nativa provada md5-idêntica, `psarc_read.c`). Todos os offsets abaixo
são do WAD do herói (3.418.720 bytes); MODL do corpo do Kratos em `0x2d29cb`.
Método: arqueologia de hex clean-room (scripts em scratchpad, sessão 2026-07-22);
validações são somas/invariantes exatas, não impressão visual.

## 1. Malha (recap, já commitado em ps3recomp)

- Diretório de atributos 16B `TAG|type|off|sz` (MODL/POS0/NRM0/COL0/TEX0/BONI),
  offsets relativos ao MODL; **todo stream de vértice começa em off+12**
  (12B de header/sentinela).
- `POS0` = (x,y,z,w) f32 **BE** stride 16, w = peso de skin 0..1.
- `TEX0` = (u,v) half BE stride 4. `BONI` = (b0,b1,0,0) u8 — 2 bones/vértice,
  índices **locais da paleta do segmento**.
- Descritor MODL: `index_count` u32 BE em +12, depois lista de triângulos
  u32 BE (janelas de 3 alinhadas). Kratos: 4378 verts, 15321 índices.

## 2. Esqueleto (123 bones) — região ~0x33b7f4..0x33ea30

| Bloco | Offset | Formato |
|---|---|---|
| Hierarquia | `0x33b7f4` | 124 records × 16B: `{u32le flags, u16le self, u16le link, u16le parentRec, u16le ?, u32le 0xd1000000}`. **parent(bone) = parentRec + 1** (records indexam a partir de template.0; 0xFFFF = filho de main). Validado: pelvis→vertebrae2→3→4→neck→head. |
| Nomes | `0x33bfb4` | 124 × 24B ASCII (o 124º é lixo/terminador → 123 bones reais). `main(0), template.0(1), pelvis(2) … joint0(0x42)..joint47(0x6b) [saia] … linkJoint(122)` |
| Bind local | `0x33cb70` | 123 × matriz 4×4 f32 **LE** (column-major, coluna de translação em [12..14]). LOCAL (relativa ao pai). Ex.: pelvis t=(0, 21.654, −0.570); neck t=(0, 4.453, 0); head t=(0, 2.313, 0). |

Nota de endianness: streams de vértice são BE (PS3), mas hierarquia/bind/
segmentos usam campos LE ou BE conforme o bloco (herança de tooling PS2) —
seguir exatamente as tabelas acima.

## 3. Segmentos de skinning (matrix palette) — PROVADO

Após o index buffer do descritor MODL: `{u32be 5, u32be 16}` (significado do 5
em aberto; 16 = tamanho máx. de paleta) + bbox global 6×f32be, depois **16
records** contíguos:

```
record = { head 3B (00 SUB 00, SUB = id de submesh/grupo),
           u32be first_vert, num_verts, first_index, num_indices, nbones,
           u32be bones_globais[nbones],      # ids na tabela de nomes (§2)
           f32be bbox[6] }
```

Kratos (16 segmentos): 7 patches da saia (joint0..joint47, 15–23 verts cada),
corpo pelvis..rWrist (1205 v), 4 segmentos de rosto (head..lip joints), mão
esq. (lRadius..lThumbF3), mão dir., pernas (lTibia..rMetatarsal), baixo corpo
(pelvis..rPhalanges).

**Validação exata (script diag_segfinal.py):**
- (a) Σ num_verts = **4378** ✓ e Σ num_indices = **15321** ✓ (sem gaps);
- (b) todo vértice do range tem `b0,b1 < nbones` do seu segmento ✓;
- (c) **auto-contenção**: os índices de cada segmento só referenciam vértices
  do próprio range ✓ (16/16).

⇒ **bone global do vértice v = bones[seg(v)][b0(v)] / [b1(v)]**, peso = w do
POS0. Cadeia completa vértice→bone→hierarquia→bind fechada com dados reais.

Depois dos 16 records segue outro bloco (`41 00 00 00 …` @rel `0x35d58`) ainda
não decodificado (provável: mais tabelas por-mesh/LOD).

## 4. Pacote de animação ANM_hero — estrutura externa

Record em `0x1d8640`: `{u16le 1, u16le 0x1d, u32le size=0xf3d80(998784),
nome[24]="ANM_hero"}`; campos em `base+0x20`:
`{u32le 3, 0, 0x3001, size, (u16le 2, u16le NCLIPS=189), u32le 0x4ae,
u32le offsets[189]}` — offsets **relativos a base+0x20**, ascendentes
(0x340, 0x500, 0x2d940 … 0xf3d40).

Cada clip começa com header 0x40: `{u32le a, b, hdr=0x40, c, d,
nome ASCII embutido}` — ex.: clip0 "hero" (64B, placeholder), clip2
**"AirAttacks"** (63KB), clip1 sem-nome? 185KB (maior), clip46 82KB,
clip43 67KB. Mediana 128B ⇒ maioria são stubs/eventos; a animação de
verdade está nos ~dezenas de clips grandes.

**Em aberto (próximo passo): codec dos tracks/keyframes** dentro do clip.
Pistas observadas no clip "AirAttacks": campos internos `{0, 0x80, 0x1000,
0x2180}` (sub-offsets), runs de bytes `01 01 01…` (flags por bone?), pares
u16 com valores < 123 (ids de bone). Chunk `0x428` do diretório top-level:
entry `ANMX_R_Hero` (type 1, esz 0x30).

## 5. Chunk directory (top-level) — parcial

Entries tipo `{u32 type, u32 entry_sz, nome 32B, …}`; walk simples quebrou
(WAD_R_Hero esz=8) — framing do diretório raiz ainda por fechar (não bloqueia:
localização por scan de records funciona).

## 6. O que já roda nativo (ps3recomp/libs/video/tests)

`mesh_spin_tex` (psarc→WAD→malha+textura+skin em memória, zero Python) +
`--skin-test` (deformação com BONI+pesos reais, bones procedurais por cluster).
Com §2+§3 deste doc, o próximo incremento é skinning com o esqueleto REAL
(FK pela hierarquia + bind local) e, com o codec do §4, reprodução das
animações do jogo — 100% dados do psarc.
