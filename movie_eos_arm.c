/*
 * Amostrador portatil do objecto do movie player + canal NATURAL de EOS.
 * Ver movie_eos_arm.h para a API.
 *
 * Task 1 era so observacao. Task 3 acrescenta o ARM do read-hook de EOS pelo
 * MESMO caminho do host Windows (boot_main.cpp:367): quando o produtor de
 * "done" dispara, arma-se g_movie_eos_ea = obj+0x744 e o vm_read8 do runtime
 * passa a devolver 1 na proxima leitura NORMAL que o guest faca a esse EA. NAO
 * se escreve o byte no guest nem se toca no st620 -- so se arma o hook.
 *
 * A LINHA replay/forja (o ponto todo da task):
 *   - Arma-se SO apos um evento real de conclusao E com a FSM ja passada do
 *     estado de abertura, via a politica pura movie_eos_should_arm
 *     (PS3_MOVIE_EOS ligado, ainda nao armado, produtor!=0, st620>=5 -- Task 2
 *     do plano 2026-07-21-intro-vdec-open-force-wad.md).
 *   - No Windows o produtor e' o overlay ffmpeg (movie_hle_overlay_done).
 *   - No macOS nao ha overlay E o .m2v e' servido pelo dearchiver psarc do
 *     PROPRIO guest (MEDIDO: 0 opens em movie_io / 0 [AREAD] para o filme),
 *     logo o host NAO ve um evento consumido==total para replicar. O player
 *     ainda por cima para em st620=3 bloqueado no DMA de EOS do SPU. Na falta
 *     de sinal observavel, o produtor POSIX e' TIME-BASED (movie_done_*),
 *     gated por PS3_MOVIE_DONE_MS, com o intervalo medido do stream real (a
 *     duracao do .wav) e assumido como time-based no log -- nao EOF real.
 *   - Sem produtor (M3: PS3_MOVIE_EOS=1 e PS3_MOVIE_DONE_MS ausente) NADA arma.
 *
 * Commit-check: como VirtualQuery nao tem equivalente POSIX barato, usa-se o
 * ppu_guest_range_committed do runtime -- a mesma lista de ranges registada
 * pelo host, partilhada com o guard dos vm_read*.
 *
 * EAs e offsets sao MEDIDOS, nao derivados:
 *   [0x540054]      -> objecto do player (0x008697D8 na sessao de 2026-07-20)
 *   obj+0x620       -> estado da FSM (documentado: 1->3->5->11->done)
 *   obj+0x630/0x634 -> handles FIOS (open / o que o poll do estado 1 espera)
 *   obj+0x744       -> byte de EOS que o decoder MPEG do SPU normalmente DMAia
 *   obj+0x746       -> flag adjacente, dumpada junto para contexto
 *
 * PARIDADE COM O WINDOWS (parcial). O host de referencia (runtime/ppu/tests/
 * boot_main.cpp) mantem a thread inline com VirtualQuery e o arm em linha
 * (:367). NAO foi substituido pela chamada partilhada a
 * movie_eos_sampler_start(): esta sessao corre em macOS/arm64 e nao pode
 * compilar nem correr o host Windows, e uma troca as cegas (a) perderia o
 * dump [MOVIEOP] que so o boot_main.cpp tem, e (b) obrigaria a mover este
 * ficheiro para libs/video, entrando no glob de build do Windows por testar.
 *
 * A partir da Task 2 (2026-07-21, plano intro-vdec-open-force-wad.md),
 * movie_eos_should_arm JA NAO espelha byte-a-byte a condicao de 3 argumentos
 * de boot_main.cpp:367: alem das tres condicoes originais (env, one-shot,
 * produtor de done), o macOS exige tambem st620>=MOVIE_STATE_POST_OPEN (5) --
 * o valor que o estado 4 da FSM (Open+StartSeq) escreve DEPOIS de correr. Sem
 * este gate, o arm cedo (a partir de st620=3) fazia o vm_read8(obj+0x744)
 * devolver 1 ainda em estado 3, o handler saltava 3->4->5 sem despachar o
 * corpo do estado 4, e o vdec/WADs nunca abriam. O encanamento do amostrador
 * continua diferente (Windows: VirtualQuery inline; macOS: aqui, via
 * ppu_guest_range_committed); agora tambem a POLITICA de arm diverge nesta
 * unica condicao extra, especifica desta build macOS/arm64.
 *
 * Task 3b / A3b (2026-07-21): com o arm atrasado, st620 fica preso em 3 porque
 * o gate real e' func_0045B2A8(obj+0x720) -> *(sessao_audio+0x1B8). O handle
 * resolve (h720!=0, rc=0 literal) mas +0x1B8 nunca sai de 0 -- o service loop
 * guest (func_00463368) nao completa o stream no Mac. HLE de stream-complete:
 * apos o produtor de done (duracao REAL do .wav) e com open de audio real
 * (h720 valido), escreve-se UMA vez sessao+0x1B8=1. NAO forja st620/+0x744.
 * Opt-out: PS3_AUDIO_STREAM_DONE=0. Default ON quando o amostrador corre.
 */
#include "movie_eos_arm.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <time.h>
#include <dirent.h>     /* scan do .wav no cache para a duracao real do stream */
#include <strings.h>    /* strcasecmp */
#endif

/* Fornecidos pelo runtime (ppu_loader.cpp) e pelo host de boot. */
extern unsigned char* vm_base;
extern int            ppu_guest_range_committed(uint32_t addr, uint32_t n);
extern uint32_t       g_movie_eos_ea;      /* ponto de injeccao (vm_read8 devolve 1) */
extern long           movie_hle_overlay_done(void);   /* movie_hle.c (C linkage) */

/* Gates do amostrador, latched em movie_eos_sampler_start (thread unica). */
static int s_sampler_mo  = 0;   /* PS3_TRACE_MOVIEOBJ: dump verboso [MOVIEOBJ]   */
static int s_sampler_eos = 0;   /* PS3_MOVIE_EOS:      autoriza o arm do read-hook */
static int s_sampler_perf = 0;  /* PS3_PERF_FSM: thin [MOVIEFSM] only (no probes) */
static int s_audio_stream_done = 1; /* HLE A3b: mark sess+0x1B8 (opt-out =0) */

#define MOVIE_OBJ_SLOT_EA  0x540054u
#define MOVIE_OBJ_MAX_EA   0x4F000000u   /* acima disto o slot e' lixo, nao objecto */
#define MOVIE_OBJ_SPAN     0x780u        /* cobre ate obj+0x746 inclusive */

#define MOVIE_OFF_STATE    0x620u
#define MOVIE_OFF_IO_OPEN  0x630u
#define MOVIE_OFF_IO_READ  0x634u
#define MOVIE_OFF_SND_H    0x720u        /* handle snd_stream (audio da intro) */
#define MOVIE_OFF_EOS      0x744u
#define MOVIE_OFF_EOS2     0x746u

#define MOVIE_IO_DONE_OFF  0x90u         /* [io+0x90] = palavra de conclusao FIOS */

/* Sessao de audio (tabela geracional TOC-0x394, stride 0x1E4). GoW2 HD
 * NPUA80491: TOC de entrada 0x541178 (ELF entry OPD). O 1o word de cada slot
 * e' o handle quando o path de match directo corre; +0x1B8 e' o flag que
 * func_0045B2A8 le. Fallback: g_movie_audio_gate_force (override no site vivo
 * func_002C0FA0) quando o resolve host nao encontra o slot. */
#define MOVIE_AUDIO_TOC           0x541178u
#define MOVIE_AUDIO_TABLE_TOC_OFF 0x394u
#define MOVIE_AUDIO_SESS_STRIDE   0x1E4u
#define MOVIE_AUDIO_SESS_MAX      256u
#define MOVIE_AUDIO_DONE_OFF      0x1B8u

/* Quando 1, o patch em func_002C0FA0 forca o retorno de func_0045B2A8 a !=0
 * (equivalente a sessao+0x1B8 != 0). Exportado para o lift (C linkage). */
int g_movie_audio_gate_force = 0;

/* Cadencia: 200 ms como no Windows. O heartbeat re-emite a linha [MOVIEFSM]
 * de 5 em 5 s mesmo sem transicao -- sem isso um estado PARADO produz uma
 * unica linha em todo o boot e "parado" fica indistinguivel de "nunca lido". */
#define MOVIE_TICK_MS      200
#define MOVIE_HEARTBEAT_TICKS (5000 / MOVIE_TICK_MS)

/* Estado da FSM do intro-movie a partir do qual e' seguro armar o read-hook
 * de EOS: func_002C069C so escreve st620=5 DEPOIS de o estado 4 (Open+
 * StartSeq) correr. Armar antes disso (em st620=3, onde o handler antigo
 * arrancava cedo demais) faz o vm_read8(obj+0x744) devolver 1 cedo demais e o
 * handler do estado 3 salta 3->4->5 sem NUNCA despachar o corpo do estado 4
 * -- o vdec nunca abre e nenhum WAD carrega. */
#define MOVIE_STATE_POST_OPEN  5u
/* Estado em que a FSM park a espera do audio-ready (+0x1B8) / EOS. */
#define MOVIE_STATE_WAIT_EOS   3u

/* Politica pura de arm -- ver movie_eos_arm.h. Task 2 (2026-07-21): ja NAO e'
 * a mesma condicao de 3 argumentos do Windows -- acrescenta o gate
 * st620>=MOVIE_STATE_POST_OPEN para so armar depois do estado 4 abrir o vdec. */
int movie_eos_should_arm(int eos_env, uint32_t eos_ea, long overlay_done, uint32_t st620)
{
    if (!eos_env || eos_ea != 0 || !overlay_done)      return 0;
    if (st620 == 0xFFFFFFFFu)                          return 0; /* sentinela: FSM ainda nao lida */
    if (st620 < MOVIE_STATE_POST_OPEN)                 return 0; /* estado 4 ainda nao correu */
    return 1;
}

int movie_audio_should_mark_done(int enabled, long done, uint32_t st620,
                                 uint32_t h720, int already_marked)
{
    /* HLE de stream-complete (A3b). Politica pura -- o sampler e' que escreve.
     * Exige: gate ON, produtor de done (mesmo do MOVIEDONE -- duracao real do
     * .wav ou overlay), FSM no park do estado 3 (WAIT_EOS / audio gate),
     * handle de audio real (open sobreviveu), one-shot. */
    if (!enabled || already_marked)                    return 0;
    if (!done)                                         return 0;
    if (st620 == 0xFFFFFFFFu)                          return 0;
    if (st620 != MOVIE_STATE_WAIT_EOS)                 return 0; /* so desbloqueia o park em 3 */
    if (!h720 || h720 == 0xFFFFFFFFu)                  return 0; /* sem open real de audio */
    return 1;
}

int movie_eos_peek32(uint32_t ea, uint32_t* out)
{
    const unsigned char* p;
    if (!vm_base || !out) return 0;
    if (!ppu_guest_range_committed(ea, 4)) return 0;
    p = vm_base + ea;
    *out = ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8)  |  (uint32_t)p[3];
    return 1;
}

int movie_eos_peek8(uint32_t ea, uint8_t* out)
{
    if (!vm_base || !out) return 0;
    if (!ppu_guest_range_committed(ea, 1)) return 0;
    *out = vm_base[ea];
    return 1;
}

/* Escrita big-endian de 32 bits -- so usada pelo HLE A3b de stream-complete. */
static int movie_eos_poke32(uint32_t ea, uint32_t val)
{
    unsigned char* p;
    if (!vm_base) return 0;
    if (!ppu_guest_range_committed(ea, 4)) return 0;
    p = vm_base + ea;
    p[0] = (unsigned char)((val >> 24) & 0xFFu);
    p[1] = (unsigned char)((val >> 16) & 0xFFu);
    p[2] = (unsigned char)((val >>  8) & 0xFFu);
    p[3] = (unsigned char)( val        & 0xFFu);
    return 1;
}

/* Resolve handle snd_stream -> EA da sessao (tabela geracional). Devolve 0 se
 * o handle nao bater em nenhum slot. */
static uint32_t movie_audio_resolve_session(uint32_t handle)
{
    uint32_t table = 0;
    uint32_t toc_slot = MOVIE_AUDIO_TOC - MOVIE_AUDIO_TABLE_TOC_OFF;
    uint32_t i;

    if (!handle || handle == 0xFFFFFFFFu) return 0;
    if (!movie_eos_peek32(toc_slot, &table) || !table) return 0;
    if (table >= MOVIE_OBJ_MAX_EA) return 0;

    for (i = 0; i < MOVIE_AUDIO_SESS_MAX; i++) {
        uint32_t slot = table + i * MOVIE_AUDIO_SESS_STRIDE;
        uint32_t h = 0;
        if (slot + MOVIE_AUDIO_DONE_OFF + 4u >= MOVIE_OBJ_MAX_EA) break;
        if (!movie_eos_peek32(slot, &h)) continue;
        if (h == handle) return slot;
    }
    return 0;
}

/* HLE one-shot de stream-complete. Preferencia:
 *  1) escrever sessao+0x1B8=1 se o resolve host achar o slot (fiel ao writer
 *     guest func_00463368);
 *  2) senao armar g_movie_audio_gate_force=1 e o patch em func_002C0FA0 forca
 *     o retorno do gate a 1 (HLE do resultado de 0045B2A8, mesmo efeito na FSM).
 * Em ambos os casos NAO se toca st620 nem +0x744. */
static int movie_audio_mark_stream_done(uint32_t obj, uint32_t h720)
{
    uint32_t sess, cur = 0;
    (void)obj;

    sess = movie_audio_resolve_session(h720);
    if (sess) {
        if (!movie_eos_peek32(sess + MOVIE_AUDIO_DONE_OFF, &cur)) {
            fprintf(stderr, "[AUDDONE] FAIL peek sess+0x1B8 @0x%08X\n",
                    sess + MOVIE_AUDIO_DONE_OFF);
            fflush(stderr);
            /* cai no force-flag */
        } else if (cur != 0) {
            fprintf(stderr,
                    "[AUDDONE] ja marcado sess=0x%08X +0x1B8=%u (h720=0x%08X)\n",
                    sess, cur, h720);
            fflush(stderr);
            g_movie_audio_gate_force = 1;
            return 1;
        } else if (movie_eos_poke32(sess + MOVIE_AUDIO_DONE_OFF, 1u)) {
            g_movie_audio_gate_force = 1; /* belt+suspenders: force gate too */
            fprintf(stderr,
                    "[AUDDONE] HLE stream-complete FIELD: h720=0x%08X sess=0x%08X "
                    "+0x1B8 0->1 (desbloqueia func_0045B2A8 / estado 3)\n",
                    h720, sess);
            fflush(stderr);
            return 1;
        }
    }

    /* Fallback: force no site vivo (resolve host falhou -- path de match do
     * guest pode ser o indirect 00447A60, nao o slot linear). */
    g_movie_audio_gate_force = 1;
    fprintf(stderr,
            "[AUDDONE] HLE stream-complete GATE-FORCE: h720=0x%08X sess_resolve=%s "
            "-> g_movie_audio_gate_force=1 (patch func_002C0FA0; NAO forja st620/+0x744)\n",
            h720, sess ? "poke_failed" : "0");
    fflush(stderr);
    return 1;
}

int movie_eos_can_sample(uint32_t obj_ea)
{
    if (!vm_base) return 0;
    if (!obj_ea || obj_ea >= MOVIE_OBJ_MAX_EA) return 0;
    return ppu_guest_range_committed(obj_ea, MOVIE_OBJ_SPAN) ? 1 : 0;
}

/* Palavra de conclusao de um handle FIOS. -1 = handle invalido,
 * -2 = handle fora do mapa de commits (nao lido). */
static long long movie_io_done(uint32_t io)
{
    uint32_t v;
    if (!io || io >= MOVIE_OBJ_MAX_EA) return -1;
    if (!movie_eos_peek32(io + MOVIE_IO_DONE_OFF, &v)) return -2;
    return (long long)v;
}

static void movie_sleep_tick(void)
{
#ifdef _WIN32
    Sleep(MOVIE_TICK_MS);
#else
    struct timespec ts;
    ts.tv_sec  = 0;
    ts.tv_nsec = (long)MOVIE_TICK_MS * 1000000L;
    nanosleep(&ts, NULL);
#endif
}

/* ======================================================================== */
/* Produtor time-based de "done" -- canal NATURAL de EOS no POSIX.          */
/*                                                                          */
/* NAO e' EOF real, e o log diz isso. No macOS o .m2v e' servido pelo       */
/* dearchiver psarc + SPU inflate DO PROPRIO guest: MEDIDO neste boot, 0    */
/* opens em movie_io e 0 linhas [AREAD] para o filme, portanto o host nao   */
/* ve o consumo do stream para poder replicar um evento consumido==total.   */
/* Pior: o player PARA em st620=3 bloqueado a espera do DMA de EOS do       */
/* descodificador SPU -- ou seja, nem chega a consumir o stream todo de     */
/* forma observavel (o consumo e' que esta bloqueado no EOS que queremos    */
/* produzir). Na ausencia desse sinal, este produtor arma depois de um      */
/* intervalo de playback REAL, ancorado no instante em que o proprio FSM do */
/* player entra em estado activo (st620>=1). Nao e' "armar ao entrar no     */
/* estado": a ancora so marca o t0; o arm so vem quando decorre o intervalo */
/* real do filme.                                                            */
/*                                                                            */
/* Gate PS3_MOVIE_DONE_MS (independente de PS3_MOVIE_EOS, para a armadilha    */
/* M3 aguentar):                                                             */
/*   ausente / vazio / "0" -> DESLIGADO (PS3_MOVIE_EOS=1 sem produtor NAO     */
/*                            arma -- e' o teste de forja M3).                */
/*   "auto"                -> intervalo = duracao REAL do .wav no cache (a    */
/*                            faixa de audio do proprio filme, o mesmo        */
/*                            comprimento do video; medida do stream real).   */
/*   inteiro N>0           -> intervalo = N ms.                              */
/* ======================================================================== */

static unsigned long long movie_now_ms(void)
{
#ifdef _WIN32
    return (unsigned long long)GetTickCount64();
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (unsigned long long)ts.tv_sec * 1000ull
         + (unsigned long long)(ts.tv_nsec / 1000000L);
#endif
}

/* Duracao real (ms) do unico .wav em PS3_MOVIE_CACHE: le o cabecalho RIFF e
 * devolve data_bytes/byterate. Medicao do stream real, nao constante inventada.
 * 0 se nao houver .wav legivel. POSIX-only: no Windows o produtor e' o overlay
 * ffmpeg (movie_hle_overlay_done), nao este. */
#ifndef _WIN32
static long long movie_wav_duration_ms(void)
{
    const char* cache = getenv("PS3_MOVIE_CACHE");
    if (!cache || !*cache) cache = "../movie_cache";

    char path[1024]; path[0] = 0;
    DIR* d = opendir(cache);
    if (d) {
        struct dirent* e;
        while ((e = readdir(d)) != NULL) {
            size_t L = strlen(e->d_name);
            if (L > 4 && strcasecmp(e->d_name + L - 4, ".wav") == 0) {
                snprintf(path, sizeof path, "%s/%s", cache, e->d_name);
                break;
            }
        }
        closedir(d);
    }
    if (!path[0]) return 0;

    FILE* f = fopen(path, "rb");
    if (!f) return 0;

    long long dur = 0;
    unsigned char hdr[12];
    if (fread(hdr, 1, 12, f) == 12 &&
        memcmp(hdr, "RIFF", 4) == 0 && memcmp(hdr + 8, "WAVE", 4) == 0) {
        unsigned  byterate   = 0;
        long long data_bytes = 0;
        for (;;) {
            unsigned char ch[8];
            if (fread(ch, 1, 8, f) != 8) break;
            unsigned clen = (unsigned)ch[4] | ((unsigned)ch[5] << 8)
                          | ((unsigned)ch[6] << 16) | ((unsigned)ch[7] << 24);
            if (memcmp(ch, "fmt ", 4) == 0) {
                unsigned char fb[16];
                unsigned want = clen < 16 ? clen : 16;
                if (fread(fb, 1, want, f) != want) break;
                byterate = (unsigned)fb[8] | ((unsigned)fb[9] << 8)
                         | ((unsigned)fb[10] << 16) | ((unsigned)fb[11] << 24);
                if (clen > want) fseek(f, (long)(clen - want), SEEK_CUR);
                if (clen & 1u)   fseek(f, 1, SEEK_CUR);
            } else if (memcmp(ch, "data", 4) == 0) {
                data_bytes = (long long)clen;
                break;
            } else {
                fseek(f, (long)(clen + (clen & 1u)), SEEK_CUR);
            }
        }
        if (byterate > 0 && data_bytes > 0)
            dur = (data_bytes * 1000ll) / (long long)byterate;
    }
    fclose(f);
    return dur;
}
#else
static long long movie_wav_duration_ms(void) { return 0; }
#endif

/* Intervalo configurado (ms), latched. -1 = por decidir, 0 = desligado. */
static long long movie_done_interval_ms(void)
{
    static long long ivl = -1;
    if (ivl != -1) return ivl;

    const char* e = getenv("PS3_MOVIE_DONE_MS");
    if (!e || !e[0] || (e[0] == '0' && e[1] == 0)) {
        ivl = 0;                                  /* desligado */
    } else if (strcmp(e, "auto") == 0) {
        long long ms = movie_wav_duration_ms();
        if (ms > 0) {
            ivl = ms;
            fprintf(stderr, "[MOVIEDONE] PS3_MOVIE_DONE_MS=auto -> duracao REAL do .wav = %lld ms\n", ms);
        } else {
            ivl = 0;
            fprintf(stderr, "[MOVIEDONE] PS3_MOVIE_DONE_MS=auto mas sem .wav legivel no cache -> produtor DESLIGADO\n");
        }
    } else {
        long long ms = strtoll(e, NULL, 10);
        ivl = ms > 0 ? ms : 0;
    }

    if (ivl > 0)
        fprintf(stderr,
                "[MOVIEDONE] produtor time-based LIGADO: intervalo=%lld ms. AVISO: HLE por temporizador, NAO EOF real do stream.\n",
                ivl);
    fflush(stderr);
    return ivl;
}

/* Chamado a cada tick. Ancora o t0 do playback no primeiro st620 activo (o
 * filme abriu) e devolve 1 (sticky) quando (a) ja decorreu o intervalo REAL do
 * filme desde essa ancora E (b) o player ja esta no estado parado que espera o
 * EOS (st>=3). A condicao (b) NAO e' "armar ao entrar no estado 3" -- o
 * intervalo real do filme tem de ter decorrido primeiro; e' so uma guarda para
 * nao injectar EOS enquanto o player ainda esta a abrir/bufferizar (st=1), o que
 * so o faz resetar antes de sequer parar em 3. 0 se desligado ou ainda nao. */
static long movie_done_timebased_poll(uint32_t st)
{
    static unsigned long long start_ms = 0;   /* 0 = playback ainda nao comecou */
    static int fired = 0;

    long long ivl = movie_done_interval_ms();
    if (ivl <= 0) return 0;                    /* produtor desligado (M3) */
    if (fired) return 1;

    unsigned long long now = movie_now_ms();
    if (start_ms == 0) {
        if (st >= 1 && st != 0xFFFFFFFFu) start_ms = now;   /* filme abriu (playback comecou) */
        return 0;
    }
    if (now - start_ms < (unsigned long long)ivl) return 0;      /* filme ainda a "decorrer" */
    if (st < MOVIE_STATE_WAIT_EOS || st == 0xFFFFFFFFu) return 0; /* espera o player parar em >=3 */

    fired = 1;
    fprintf(stderr,
            "[MOVIEDONE] done time-based (NAO e' EOF real): %llu ms desde st620 activo >= %lld ms, player parado em st620=%u -> sinal \"filme acabou\"\n",
            (unsigned long long)(now - start_ms), ivl, st);
    fflush(stderr);
    return 1;
}

static void movie_sampler_loop(void)
{
    uint32_t prev = 0xFFFFFFFFu;   /* edge-trigger: 1a leitura imprime sempre */
    int      since_log = 0;

    for (;;) {
        uint32_t obj = 0, st = 0, io_open = 0, io_read = 0;
        uint8_t  f744 = 0, f746 = 0;

        movie_sleep_tick();

        if (!vm_base) continue;
        if (!movie_eos_peek32(MOVIE_OBJ_SLOT_EA, &obj)) continue;

        if (!obj || obj >= MOVIE_OBJ_MAX_EA) {
            fprintf(stderr, "[MOVIEOBJ] obj=0x%08X (unset)\n", obj);
            fflush(stderr);
            continue;
        }
        if (!movie_eos_can_sample(obj)) continue;

        if (!movie_eos_peek32(obj + MOVIE_OFF_STATE, &st)) continue;
        movie_eos_peek8(obj + MOVIE_OFF_EOS,  &f744);
        movie_eos_peek8(obj + MOVIE_OFF_EOS2, &f746);

        /* Sinal REAL de "filme acabou" (produtor). No Windows vem do overlay
         * ffmpeg; no POSIX o overlay nao existe (movie_hle_overlay_done()==0) e
         * o produtor e' o time-based gated por PS3_MOVIE_DONE_MS. Chamado TODOS
         * os ticks (poe a ancora e verifica o temporizador), nao so no log. */
        long done_overlay = movie_hle_overlay_done() ? 1 : 0;
        long done         = done_overlay ? 1 : movie_done_timebased_poll(st);

        /* Mesmo formato do host Windows, para os dois logs se compararem
         * linha a linha. Emitido na transicao OU no heartbeat. */
        since_log++;
        if (st != prev || since_log >= MOVIE_HEARTBEAT_TICKS) {
            fprintf(stderr,
                    "[MOVIEFSM] st620 %u -> %u  f744=%u f746=%u eos_ea=0x%08X overlay_done=%ld\n",
                    prev, st, f744, f746, g_movie_eos_ea, done);
            fflush(stderr);
            prev = st;
            since_log = 0;
        }

        /* Canal NATURAL de EOS (Task 3): arma UMA vez o read-hook do vm_read8 em
         * [obj+0x744], mas SO quando a politica pura movie_eos_should_arm o
         * autoriza -- PS3_MOVIE_EOS ligado, ainda nao armado, o produtor de
         * done disparou, E a FSM ja passou o estado de abertura do vdec
         * (st620>=5, Task 2). Sem produtor real (M3), done==0 e isto nunca
         * dispara. Sem o gate de estado, armar cedo (st620=3) fazia o handler
         * do estado 3 saltar para 5 sem nunca abrir o vdec no estado 4. Nao
         * escrevemos o byte no guest: so armamos o hook para que a proxima
         * leitura NORMAL do guest a [obj+0x744] devolva 1. */
        if (movie_eos_should_arm(s_sampler_eos, g_movie_eos_ea, done, st)) {
            g_movie_eos_ea = obj + MOVIE_OFF_EOS;
            fprintf(stderr,
                    "[MOVIEEOS] %s done (st620=%u) -> arming EOS read-hook at 0x%08X ([obj+0x744])\n",
                    done_overlay ? "overlay" : "time-based", st, g_movie_eos_ea);
            fflush(stderr);
        }

        /* A3b: HLE stream-complete do audio. Com o arm EOS atrasado (st>=5), o
         * estado 3 park em func_0045B2A8 ate sessao+0x1B8 != 0. O service loop
         * guest nao completa isso no Mac; apos o produtor de done (duracao real
         * do .wav) e com handle de audio real, marca-se o campo UMA vez. Opt-out
         * PS3_AUDIO_STREAM_DONE=0. Nao toca st620 nem +0x744. */
        {
            static int s_aud_marked = 0;
            uint32_t h720 = 0;
            movie_eos_peek32(obj + MOVIE_OFF_SND_H, &h720);
            if (movie_audio_should_mark_done(s_audio_stream_done, done, st,
                                             h720, s_aud_marked)) {
                if (movie_audio_mark_stream_done(obj, h720))
                    s_aud_marked = 1;
            }
        }

        /* Dump verboso do objecto SO com PS3_TRACE_MOVIEOBJ: evita encher o log
         * quando so PS3_MOVIE_EOS esta ligado (recipe normal). Handles FIOS que
         * o poll do estado 1 (func_002B4224) espera: container=obj+0x62C,
         * io=[container+8], done=[io+0x90]. */
        if (s_sampler_mo) {
            movie_eos_peek32(obj + MOVIE_OFF_IO_OPEN, &io_open);
            movie_eos_peek32(obj + MOVIE_OFF_IO_READ, &io_read);
            fprintf(stderr,
                    "[MOVIEOBJ] obj=0x%08X st620=%u f744=%u f746=%u | open=0x%08X d=%lld read=0x%08X d=%lld\n",
                    obj, st, f744, f746,
                    io_open, movie_io_done(io_open),
                    io_read, movie_io_done(io_read));
            fflush(stderr);
        }
    }
}

#ifdef _WIN32
static DWORD WINAPI movie_sampler_thread(LPVOID unused)
{
    (void)unused;
    movie_sampler_loop();
    return 0;
}
#else
static void* movie_sampler_thread(void* unused)
{
    (void)unused;
    movie_sampler_loop();
    return NULL;
}
#endif

static int movie_env_on(const char* name)
{
    const char* v = getenv(name);
    return (v && v[0] && v[0] != '0') ? 1 : 0;
}

void movie_eos_sampler_start(void)
{
    /* Tres portas: PS3_TRACE_MOVIEOBJ liga dump verboso [MOVIEOBJ];
     * PS3_MOVIE_EOS autoriza o arm do read-hook; PS3_PERF_FSM liga um
     * amostrador MAGRO so com [MOVIEFSM] (sem TRACE_*, para smokes de perf).
     * A thread arranca se QUALQUER uma estiver ligada; sem nenhuma e' no-op
     * total (nem thread se cria), portanto o baseline fica byte a byte igual. */
    s_sampler_mo   = movie_env_on("PS3_TRACE_MOVIEOBJ");
    s_sampler_eos  = movie_env_on("PS3_MOVIE_EOS");
    s_sampler_perf = movie_env_on("PS3_PERF_FSM");
    /* A3b HLE: default ON (fix, nao probe). Opt-out explicito =0. */
    {
        const char* a = getenv("PS3_AUDIO_STREAM_DONE");
        if (a && a[0] == '0' && a[1] == 0) s_audio_stream_done = 0;
        else s_audio_stream_done = 1;
    }
    if (!s_sampler_mo && !s_sampler_eos && !s_sampler_perf) {
        return;   /* OFF por default */
    }

    fprintf(stderr, "[MOVIEFSM] sampler on (mo=%d eos=%d perf_fsm=%d aud_done=%d)%s\n",
            s_sampler_mo, s_sampler_eos, s_sampler_perf, s_audio_stream_done,
            s_sampler_eos ? " -- pode armar EOS quando o produtor de done disparar"
                          : " -- obs-only EOS; A3b HLE audio se aud_done=1 e done disparar");
    fflush(stderr);

#ifdef _WIN32
    CreateThread(NULL, 0, movie_sampler_thread, NULL, 0, NULL);
#else
    {
        pthread_t th;
        pthread_attr_t attr;
        pthread_attr_init(&attr);
        pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
        if (pthread_create(&th, &attr, movie_sampler_thread, NULL) != 0) {
            fprintf(stderr, "[MOVIEFSM] pthread_create falhou -- sem amostragem\n");
            fflush(stderr);
        }
        pthread_attr_destroy(&attr);
    }
#endif
}
