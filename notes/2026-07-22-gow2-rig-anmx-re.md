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

## 7. Codec do clip (RE em curso, sessão 2026-07-22 tarde)

Sub-anim (ex.: attAirSlashH1 @clip+0x80): header 0x60 {u32le 0x3042, 0, 4,
f32 1.0, 0, f32 DURACAO_s (x30 = frames), u16 0xffff, u16 ANIM_ID,
u32 hash, nome[24], ..., u32 size}; descritores 16B em +0x60:
{u16 0, u16 b, u16 c, u16 d, u32 OFF, f32 1/30} ate dt!=1/30 — 3 secções:

- sec1 (b=5,c=2,d=2, maior): tracks de rotação dos bones. Header
  {u16 0, u16 N?, u16 ?, u16 1, u16 NFRAMES, u16 ?} + registos de track
  possivelmente VARIÁVEIS terminando em {u16 NKEYS=frames+1, u16 OFFSET}
  com offsets ascendentes (ex.: 0x6dc, 0x748, 0x944, 0xaac). Tamanho
  total ≈ frames*128 bytes (H1: 22f→0xb00; H2: 26f→0xcc0 ≈ 121-122/f).
  Dados nos offsets: streams de deltas s8 (fc/fa/fb/fd/fe...).
- sec2 (b=2..3,c=1..2,d=4): mesma estrutura de header {0, 0x62, 0, 1,
  NFRAMES, ...} — provável translação/root motion (elementos de 4B).
- sec3 (b=0,c=0,d=2, 0x40): DECODIFICADA: 3 registos
  {u32le bone, u32le 2, u16 a, u16 b} para bones 0x74/0x76/0x77
  (rWeapOH/lWeapOH/lChainW) + pad 01010101 — refs de arma/anexo por
  anim (a=0x2b em H1, 0x33 em H2; b=0x24/0x1c/0x14 fixos por bone).

Constantes: dt=1/30 em TODOS os descritores; NKEYS = frames+1;
ANIM_ID sequencial (H1=0x15, H2=0x16, H3=0x17). Falta: semântica exata
dos campos A/B dos registos de sec1 (canal/bone), formato do stream de
keys (delta s8 com base? escala?), e mapear bone→track.

### 7.1 Tracks (attAirSlashH1, dumps de referência)

Secção = N registos de **12B** `{u16 a,b,c,d,e,off}`; os registos acabam
exactamente em `off` do 1º (sec1: 5 tracks, sec2: 2). Tamanho do track k =
off[k+1]-off[k].

sec1 t0 {0,0xc2,0,1,0x16} sz=1696, dados:
`01021400 01000100 4e000200 15000000 62051e41 8200007f 777f0000 00..00
 00609a0f 00000000 0000f7f9 ...` (sub-header `01 02 14 00`; 0x15=21=ANIM_ID;
 depois maioria zeros + rajadas de deltas s8)
sec2 t0 {0,0x62,0,1,0x16} sz=512:
`01021400 01000100 2a000200 15000000 92011e09 4a000007 ...` (mesmo shape)
sec1 t1 {0x80,0xa2,0,0,0x17} sz=108:
`8409e432 45e2f4c0 9bf5e928 01021400 02000100 ee060300 00000000 16071502
 32000400 ...`
sec1 t2 {0,2,2,0,0} sz=508: `07fb0300 03f505e6 06e503f0 d6259efd a5259ffd
 f423c0fd 1e724000 007f777f 07...` (deltas s8 densos)
sec1 t3 {0x70,2,0x17,0,0} sz=360: `2e0d00fc 84e1ee26 d111463e 00000000
 00007d51 cfeff3be c8e78027 00000000 00007d51 16073000 ...` (`7d51`
 recorrente ≈ w de quat quantizado 0.637?)
sec1 t4 {0xc9,0,0xd,0,0} sz=84: **6 keys de 14B (7×s16le)**:
`95e8 e5bd 2707 7b0b b209 1d11 78b4` → `95e8 b6be 2707 cd09 b209 1d11 78b4`
→ `95e8 b5bf 2707 0908 ...` — 5 componentes constantes, 2 variam
(quat(4)+trans(3) quantizados s16?). Termina `3cc1 3cc1 0000`.

Hipóteses vivas: tracks tipo-A (a=0,d=1) = stream comprimido c/ sub-header
`01 02 14 00` + ANIM_ID; tipo-B = arrays de keys 14B (7×s16); campos a/b/c
ainda sem semântica (0x80/0xa2/0x70/0xc9 nao sao ids de bone directos).
Próximo: decodificar t4 como 7×s16 (escala 1/32767?) e correlacionar com o
bind dos bones de arma (sec3 aponta rWeapOH/lWeapOH/lChainW).
