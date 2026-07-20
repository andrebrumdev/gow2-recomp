/*
 * Amostrador portatil do objecto do movie player -- ver movie_eos_arm.h.
 *
 * Task 1: SO OBSERVACAO. Nao arma o read-hook de EOS, nao escreve no guest.
 *
 * Porque existe: o host de referencia do Windows (boot_main.cpp) tem esta
 * thread inline no main() e usa VirtualQuery para so ler paginas commitadas.
 * O boot_macos.cpp nao tinha amostrador NENHUM, entao no macOS nao ha maneira
 * de ver onde a FSM do player pára. Como VirtualQuery nao tem equivalente
 * POSIX barato (e chamar mach_vm_region 5x/s seria pior), a verificacao de
 * commit passa pelo ppu_guest_range_committed do runtime -- a mesma lista de
 * ranges registada pelo host, partilhada com o guard dos vm_read*.
 *
 * EAs e offsets sao MEDIDOS, nao derivados:
 *   [0x540054]      -> objecto do player (0x008697D8 na sessao de 2026-07-20;
 *                      inicializador estatico em BSS, nao objecto construido)
 *   obj+0x620       -> estado da FSM (documentado: 1->3->5->11->done)
 *   obj+0x630/0x634 -> handles FIOS (open / o que o poll do estado 1 espera)
 *   obj+0x744       -> byte de EOS que o decoder MPEG do SPU normalmente DMAia
 *   obj+0x746       -> flag adjacente, dumpada junto para contexto
 */
#include "movie_eos_arm.h"

#include <stdio.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <time.h>
#endif

/* Fornecidos pelo runtime (ppu_loader.cpp) e pelo host de boot. */
extern unsigned char* vm_base;
extern int            ppu_guest_range_committed(uint32_t addr, uint32_t n);
extern uint32_t       g_movie_eos_ea;      /* ponto de injeccao; fica 0 nesta task */
extern long           movie_hle_overlay_done(void);   /* movie_hle.c (C linkage) */

#define MOVIE_OBJ_SLOT_EA  0x540054u
#define MOVIE_OBJ_MAX_EA   0x4F000000u   /* acima disto o slot e' lixo, nao objecto */
#define MOVIE_OBJ_SPAN     0x780u        /* cobre ate obj+0x746 inclusive */

#define MOVIE_OFF_STATE    0x620u
#define MOVIE_OFF_IO_OPEN  0x630u
#define MOVIE_OFF_IO_READ  0x634u
#define MOVIE_OFF_EOS      0x744u
#define MOVIE_OFF_EOS2     0x746u

#define MOVIE_IO_DONE_OFF  0x90u         /* [io+0x90] = palavra de conclusao FIOS */

/* Cadencia: 200 ms como no Windows. O heartbeat re-emite a linha [MOVIEFSM]
 * de 5 em 5 s mesmo sem transicao -- sem isso um estado PARADO produz uma
 * unica linha em todo o boot e "parado" fica indistinguivel de "nunca lido". */
#define MOVIE_TICK_MS      200
#define MOVIE_HEARTBEAT_TICKS (5000 / MOVIE_TICK_MS)

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

        /* Mesmo formato do host Windows, para os dois logs se compararem
         * linha a linha. Emitido na transicao OU no heartbeat. */
        since_log++;
        if (st != prev || since_log >= MOVIE_HEARTBEAT_TICKS) {
            fprintf(stderr,
                    "[MOVIEFSM] st620 %u -> %u  f744=%u f746=%u eos_ea=0x%08X overlay_done=%d\n",
                    prev, st, f744, f746, g_movie_eos_ea,
                    movie_hle_overlay_done() ? 1 : 0);
            fflush(stderr);
            prev = st;
            since_log = 0;
        }

        /* Handles FIOS que o poll do estado 1 (func_002B4224) espera:
         * container = obj+0x62C, io = [container+8], done = [io+0x90]. */
        movie_eos_peek32(obj + MOVIE_OFF_IO_OPEN, &io_open);
        movie_eos_peek32(obj + MOVIE_OFF_IO_READ, &io_read);

        fprintf(stderr,
                "[MOVIEOBJ] obj=0x%08X st620=%u f744=%u f746=%u | open=0x%08X d=%lld read=0x%08X d=%lld\n",
                obj, st, f744, f746,
                io_open, movie_io_done(io_open),
                io_read, movie_io_done(io_read));
        fflush(stderr);

        /*
         * O arm do g_movie_eos_ea aterra na Task 3 -- AQUI, com a mesma
         * condicao do boot_main.cpp:367 (s_eos && !g_movie_eos_ea &&
         * movie_hle_overlay_done()). Nao esta escrito ainda de proposito:
         * no POSIX o movie_hle_overlay_done() devolve 0 sempre, portanto
         * qualquer arm hoje seria por tempo/estado, sem evento de conclusao
         * nenhum -- isto e', forjar progresso do guest. Task 3 traz primeiro
         * o produtor de "done" e so depois o arm.
         */
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

void movie_eos_sampler_start(void)
{
    const char* trace = getenv("PS3_TRACE_MOVIEOBJ");
    if (!trace || !trace[0] || trace[0] == '0') {
        return;   /* OFF por default: nem thread se cria */
    }

    fprintf(stderr, "[MOVIEFSM] sampler on (PS3_TRACE_MOVIEOBJ), obs-only: nao arma EOS\n");
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
