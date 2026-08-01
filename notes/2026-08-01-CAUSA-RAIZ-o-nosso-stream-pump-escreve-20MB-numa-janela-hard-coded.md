# CAUSA RAIZ: o nosso `F2B-STREAM-PUMP` escreve 20 MB numa janela hard-coded e passa por cima dos objectos de tipo do jogo

**Data:** 2026-08-01 · **MEDIDO em 2/2 corridas, byte a byte iguais, incluindo o valor
final do veneno.** É o achado desta sessão, e é um defeito **nosso**.

## A linha que fecha o caso

```
[WATCHSTORE] BULK who=movie_io_pread fread [0x400C0000,+131072) cobre alvo 0x400C3D88 -> agora 0x9102FFFF
```

`0x9102FFFF` é exactamente o valor que o `[WADLD-VT28] #49` lê como vtable do tipo do WAD,
e de onde saem os `[ICALL-BAD] ctr=0x40637408` e os `UNCOMMITTED` em `0x91030027`/`0x91030047`
(= `0x9102FFFF+0x28` / `+0x48`).

## O código, com os números todos

O bloco `F2B-STREAM-PUMP` (instalado no lift por
`recomp_mid_v2/patch_fios_f2b_open_block_install.py`, corpo de `func_002B4274`) tem isto:

```c
uint32_t ring    = 0x40080000u;
uint32_t ring_sz = 0x00100000u;      /* 1 MiB ring  <- HARD-CODED */
uint32_t pos = 0, chunk = 0x20000u;  /* 128 KiB */
while (pos < _sz && nchunk < 400) {
    uint32_t n = _sz - pos; if (n > chunk) n = chunk;
    uint32_t dst = ring + (pos % ring_sz);
    if (dst + n > ring + ring_sz) n = ring + ring_sz - dst;
    movie_io_pread(_mfd, vm_base + dst, n, pos);   /* escrita HOST directa */
    total += got; pos += got; nchunk++;
}
```

`_sz` é o tamanho do ficheiro. Para o `r_perma.wad_ps3` isso são **20 169 344 bytes**, que o
pump despeja em **154 chunks** de 128 KiB dentro de `[0x40080000, 0x40180000)`, dando
**20 voltas** à janela de 1 MiB. Confirmado no log:

```
[FIOSOPEN] F2B-STREAM-PUMP fo=0x430189D8 mfd=0x4D560003 pumped=20169344/20169344 chunks=154
```

E a janela **não é dele**. O ring verdadeiro do guest, lido do próprio objecto de stream
pelo `f2b_stream_fill` (`host_gow2_f2b.c`), é:

```
[FIOSOPEN] F2B-STREAM-FILL stream=0x4007FCD0 base=0x40083D40 avail=262144 ...
```

| | início | fim | tamanho |
|---|---|---|---|
| ring **real** do guest (`base`/`cap` lidos do objecto) | `0x40083D40` | `0x400C3D40` | 256 KiB |
| janela **hard-coded** do pump | `0x40080000` | `0x40180000` | 1 MiB |

O pump escreve **0xBC2C0 bytes (770 KiB) para lá do fim do ring real**, em cheio no heap do
guest. E é lá que vivem os objectos que a fábrica de tipos acabou de construir:

| objecto | endereço | tipo |
|---|---|---|
| `tab[0x14]` — `WadServer` e os 20 outros `*Server` | `0x400C3D48` | dentro da janela |
| `tab[0x58]` — `WAD_R_LglScA` / `WAD_R_Perm` (`w0=0x80000016`) | **`0x400C3D88`** | dentro da janela |

## A cadeia causal completa, cada elo medido

```
1.  ctor constroi o objecto de tipo do WAD e escreve a vtable
      [WATCHSTORE] w32 [0x400C3D88]=0x005170B8  ra0=func_002B11B8+0x8344
2.  func_0042B078 publica-o em tab[0x58]
      [WATCHSTORE] w32 [0x00868DA0]=0x400C3D88
3.  1o WAD (r_lglsca, 3 KB): a fabrica resolve BEM
      [WADLD-VT28] #28 obj=0x400C3D88 vt=0x005170B8 opd=0x0051B2F8 code=0x0039E6B4
4.  abre o r_perma (20 MB) -> o NOSSO pump despeja 20 MB em [0x40080000,+1MiB)
      19 x [WATCHSTORE] BULK who=movie_io_pread fread [0x400C0000,+131072)
      ... a ultima deixa 0x9102FFFF na palavra 0 do objecto
5.  2o WAD: a fabrica resolve para lixo
      [WADLD-VT28] #49 obj=0x400C3D88 vt=0x9102FFFF opd=0x00000000 code=0x00000000
6.  o walk do typemap despacha atraves do lixo
      [ICALL-BAD] ctr=0x40637408 lr=0x002B0EBC r3=0x400C3D88
      [vm] UNCOMMITTED read32 access 0x91030027   (= 0x9102FFFF + 0x28)
```

## Como se chegou aqui (e porque não se chegou antes)

O `PS3_WATCH_W32` do motor só vive dentro de `vm_write32`. Foi acrescentado um
`PS3_WATCH_STORE` no `heap_w()` — o ponto por onde passam `vm_write8/16/32/64` — e **também
não apanhou nada**: 8 escritas, todas da construção, em 2/2 corridas.

Isso foi o que resolveu o caso: **provou que o escritor não é o guest**. Um `pread` host
escreve directamente em `vm_base + dst` e é invisível a qualquer watch que viva nos
acessores. Foram então instrumentados os cinco sítios do motor+port que escrevem host-directo
em `vm_base` (`ps3_watch_store_bulk`, commit `92c6705`), e o primeiro disparo nomeou o
culpado.

**Lição:** um watch que "não dispara" não prova que ninguém escreve — prova que ninguém
escreve *por aquele caminho*. A pergunta a fazer a seguir é sempre "que caminhos é que este
watch não vê?".

## O gate para desligar já existia

O próprio bloco tem `PS3_FIOS_STREAM_PUMP=0`. A experiência discriminadora está a correr:
com o pump desligado, o critério é `[WADLD-VT28] #49 vt=0x005170B8` (em vez de `0x9102FFFF`)
e zero `[ICALL-BAD] ctr=0x40637408` — sem regressão nos elos a montante
(`r_perma bytes_read=20169344`, `startseq=2`, `thr_auto_load end`).

## O fix, quando a experiência confirmar

O pump existe porque *"Guest never reaches 002B3D1C for WAD (freelist desync first)"*. Mas:

1. Escrever 20 MB numa janela de 1 MiB significa que **só o último MiB sobrevive** — o resto
   do trabalho é deitado fora de qualquer maneira.
2. A janela é **hard-coded** e não pertence ao pump; o `f2b_stream_fill`, chamado
   imediatamente a seguir, faz a coisa certa: lê `base` e `cap` do próprio objecto de stream
   do guest e enche só `[base, base+cap)`.

O fix mínimo e fiel é **o pump passar a ler `base`/`cap` do objecto de stream**
(`st = *(type_sys+0x1A8)`, `base = *(st+0)`, `cap = *(st+0xC)`) em vez das constantes, e
nunca escrever fora desse intervalo — exactamente a disciplina que o `f2b_stream_fill` já
tem. Vira `patch_*.py` idempotente, como manda o CLAUDE.md.

## Ressalva honesta

Isto explica a corrupção de `tab[0x58]` e os `ICALL-BAD`. **Não está provado** que seja a
única coisa entre aqui e um menu — o `2B2DD0 tot=2001` (limite duro, ver a nota irmã de hoje)
continua por explicar, e nada garante que o desenho volte só por isto. O que está provado é
que este stomp é real, é nosso, e destrói o objecto que o walk do typemap precisa.
