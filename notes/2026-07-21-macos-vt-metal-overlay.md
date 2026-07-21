# Spike VideoToolbox/AVAsset no SmLogo_v2.m2v — M0 Task 0

Data: 2026-07-21 · macOS/arm64 (Darwin 25.5.0, arm64) · clang 21 (Apple) ·
spike standalone fora do repo (scratchpad da sessao), **nao** in-boot do
`boot_gow2` — este e o probe de viabilidade da Task 0 do plano M0
(`../ps3recomp/docs/superpowers/plans/2026-07-21-macos-videotoolbox-metal-overlay.md`),
nao a integracao real (`movie_vt_metal.m`, Tasks 1-6).

## Asset confirmado (Step 1)

```
$ ls -la movie_cache/SmLogo_v2.m2v movie_cache/SmLogo_v2.wav
-rw-r--r--  1 andrebrumcortezferreira  staff  19569933 20 jul 10:45 movie_cache/SmLogo_v2.m2v
-rw-r--r--  1 andrebrumcortezferreira  staff   2829928 20 jul 10:45 movie_cache/SmLogo_v2.wav
$ file movie_cache/SmLogo_v2.m2v
movie_cache/SmLogo_v2.m2v: MPEG sequence, v2, MP@H-14 progressive Y'CbCr 4:2:0 video, 30 fps
```

Elementary stream MPEG-2 puro (sem container PS/TS), como esperado.

## Spike (Step 2) — AVAssetReader directo no ES

Probe ObjC (`probe_a.m`, standalone, fora do repo): `AVURLAsset` no path absoluto
→ `AVAssetReader` + `AVAssetReaderTrackOutput` com `kCVPixelFormatType_32BGRA` →
loop `copyNextSampleBuffer`.

```
$ ./probe_a "$(pwd)/movie_cache/SmLogo_v2.m2v"
[probeA] asset.tracks(video) count=1
[probeA] track naturalSize=1280x720 nominalFrameRate=30.000 formatDescriptions=1
[probeA] formatDescription mediaSubType=mp2v (0x6d703276)
[probeA] reader.status final=1 (reading)
[probeA] RESULT frames=60 dims=1280x720 pixfmt=BGRA firstPTS=0.000 lastPTS=1.967
```

Extensao (sem cap em 60, ate EOS real) confirmou o stream completo:

```
$ ./probe_a_full "$(pwd)/movie_cache/SmLogo_v2.m2v" /tmp/.../frame.png
[probeA-full] reader.status final=2 (completed)
[probeA-full] RESULT frames=330 dims=1280x720 duration=10.967s wallclock_decode=0.17s (~1900 fps)
[probeA-full] VERDICT=GO-CLEAN-EOS
```

7 frames amostrados ao longo do stream (t=0, 2, 3.3, 5, 6.7, 8.3, 10.7s) e
inspeccionados visualmente (PNG no scratchpad, **nao commitado**): fade-in de
preto → esferas vermelhas retro-iluminadas (transicao) → **logo "SANTA MONICA
studio" legivel e correcto** (~t=8.3s) → fade final a preto. Pixels correctos,
cores correctas, texto nitido — nao e lixo/corrupcao.

`VTIsHardwareDecodeSupported(kCMVideoCodecType_MPEG2Video)` = **NO** neste Mac
(Apple Silicon nao tem bloco HW para MPEG-2; H.264 = YES confirma que a query
em si funciona). Decode e por software — irrelevante para o caso de uso (clip
de 11s, throughput medido ~1900 fps, ~60x mais rapido que realtime).

## Veredicto

```
SPIKE=A
frames=330
notes=AVAssetReader/AVURLAsset engole o .m2v elementary stream DIRECTO, sem
demux/remux/wrapper. mediaSubType=mp2v reconhecido nativamente. 330/330 frames
ate EOS limpo (reader.status=completed, zero erros). 1280x720 BGRA8, 30fps,
conteudo real do logo Santa Monica Studio verificado visualmente (nao so
contagem de frames). HW decode ausente neste arm64 mas SW decode e trivial
(~60x realtime) para um clip de intro de 11s. Priority B (remux ES->PS) e
Priority C (VTDecompressionSession manual) do plano M0 NAO sao necessarias —
A resolve sozinho. GO para Tasks 1-6 do plano M0 usando AVAssetReader.
```

**GO.** M0 pode prosseguir (Tasks 1-6) com `movie_vt_metal.m` a implementar a
Priority A (`AVAssetReader`/`AVURLAsset`) tal como planeado — sem ffmpeg, sem
reencode, sem necessidade de remux/parse manual de start codes.

Relatorio completo do spike (codigo exacto, todos os comandos, resultados):
`.superpowers/sdd/m0-task-0-report.md` (nao commitado — ledger interno).
