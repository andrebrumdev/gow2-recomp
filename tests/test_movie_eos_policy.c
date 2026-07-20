/*
 * Unit offline do amostrador do movie player (Task 1 do plano
 * ../../ps3recomp/docs/superpowers/plans/2026-07-20-macos-movie-eos-fsm.md).
 *
 * O que se prova aqui, sem boot nenhum:
 *
 *  1. movie_eos_peek32/peek8 NAO tocam na memoria do guest quando o range nao
 *     esta commitado. Isto nao e' testado por inspeccao: o "range nao
 *     commitado" e' uma pagina real com PROT_NONE, portanto uma leitura
 *     indevida mata o processo com SIGSEGV e o teste reprova de facto.
 *     Era exactamente o papel do VirtualQuery no host Windows.
 *
 *  2. movie_eos_can_sample rejeita obj=0, obj fora da janela do guest,
 *     vm_base=NULL e ranges nao commitados -- os quatro casos em que o
 *     amostrador do Windows fazia `continue`.
 *
 * Build/run: ../smoke_moviefsm_mac.sh (ou clang -std=c11 este ficheiro +
 * ../movie_eos_arm.c).
 */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include "../movie_eos_arm.h"

/* --- simbolos que o movie_eos_arm.c espera do runtime/host ---------------- */

unsigned char* vm_base = NULL;
uint32_t       g_movie_eos_ea = 0;
long           movie_hle_overlay_done(void) { return 0; }

/* Mapa de commits falso: so a primeira pagina conta como commitada. A segunda
 * fica PROT_NONE de propósito (ver o cabecalho).
 *
 * O tamanho de pagina e' lido em runtime: no arm64 da Apple sao 16 KB, nao os
 * 4 KB habituais, e o mprotect recusa enderecos que nao estejam alinhados a
 * pagina real. */
static uint32_t PAGE = 0;
static int g_committed_consulted = 0;

/*
 * A banda alta (>= 0x4E000000) e' declarada COMMITADA de proposito, apesar de
 * nao ter memoria nenhuma por tras. Sem isso o teste da guarda de objecto era
 * falso: com o mapa de commits a recusar tudo la em cima, apagar a guarda
 * `obj_ea >= MOVIE_OBJ_MAX_EA` do can_sample continuava a passar (mutacao M3
 * escapou na primeira versao deste teste). Com a banda aberta, so a guarda de
 * objecto pode rejeitar aqueles enderecos -- e a mutacao morre. O limiar fica
 * ABAIXO de MOVIE_OBJ_MAX_EA (0x4F000000) para os dois lados da fronteira
 * caírem na banda aberta e o teste ser mesmo de fronteira.
 *
 * Nada nestes enderecos e' lido: o can_sample so decide, nao desreferencia.
 */
int ppu_guest_range_committed(uint32_t addr, uint32_t n)
{
    g_committed_consulted++;
    if (addr >= 0x4E000000u) return 1;
    return ((uint64_t)addr + n) <= (uint64_t)PAGE;
}

/* --- helpers -------------------------------------------------------------- */

static int g_fail = 0;

#define CHECK(cond, msg) do {                                            \
        if (!(cond)) { printf("  FAIL: %s\n", (msg)); g_fail++; }        \
        else         { printf("  ok:   %s\n", (msg)); }                  \
    } while (0)

int main(void)
{
    unsigned char* buf;
    uint32_t v;
    uint8_t  b;

    PAGE = (uint32_t)sysconf(_SC_PAGESIZE);
    printf("page size = %u bytes\n", PAGE);

    /* Duas paginas: [0,PAGE) legivel, [PAGE,2*PAGE) PROT_NONE. */
    buf = (unsigned char*)mmap(NULL, PAGE * 2, PROT_READ | PROT_WRITE,
                               MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (buf == MAP_FAILED) { printf("FAIL: mmap\n"); return 1; }
    memset(buf, 0, PAGE * 2);
    if (mprotect(buf + PAGE, PAGE, PROT_NONE) != 0) { printf("FAIL: mprotect\n"); return 1; }

    /* Palavra big-endian conhecida em EA 0x10 e byte em EA 0x20. */
    buf[0x10] = 0x11; buf[0x11] = 0x22; buf[0x12] = 0x33; buf[0x13] = 0x44;
    buf[0x20] = 0xA5;

    printf("== peek com vm_base=NULL ==\n");
    vm_base = NULL;
    v = 0xDEADBEEFu;
    CHECK(movie_eos_peek32(0x10, &v) == 0, "peek32 recusa vm_base=NULL");
    CHECK(v == 0xDEADBEEFu,                "peek32 nao mexe no *out quando recusa");
    CHECK(movie_eos_can_sample(0x100) == 0, "can_sample recusa vm_base=NULL");

    vm_base = buf;

    printf("== leitura big-endian dentro do commit ==\n");
    v = 0;
    CHECK(movie_eos_peek32(0x10, &v) == 1, "peek32 aceita range commitado");
    CHECK(v == 0x11223344u,                "peek32 desempacota big-endian");
    b = 0;
    CHECK(movie_eos_peek8(0x20, &b) == 1,  "peek8 aceita range commitado");
    CHECK(b == 0xA5,                       "peek8 devolve o byte certo");

    printf("== range NAO commitado: nao pode tocar na memoria ==\n");
    /* EA 0x1000 cai na pagina PROT_NONE. Se o peek ler antes de verificar o
     * commit, o processo morre aqui com SIGSEGV -- e' esse o teste. */
    v = 0xDEADBEEFu;
    g_committed_consulted = 0;
    CHECK(movie_eos_peek32(PAGE, &v) == 0, "peek32 recusa range nao commitado");
    CHECK(v == 0xDEADBEEFu,                "peek32 nao escreveu *out (nao leu)");
    CHECK(g_committed_consulted > 0,       "peek32 consultou o mapa de commits");
    b = 0x5A;
    CHECK(movie_eos_peek8(PAGE, &b) == 0,  "peek8 recusa range nao commitado");
    CHECK(b == 0x5A,                       "peek8 nao escreveu *out (nao leu)");

    /* Leitura que COMECA dentro e ATRAVESSA a fronteira tem de ser recusada
     * inteira: 4 bytes a partir de 0xFFE passam para a pagina PROT_NONE. */
    v = 0xDEADBEEFu;
    CHECK(movie_eos_peek32(PAGE - 2, &v) == 0, "peek32 recusa leitura que atravessa a fronteira");
    CHECK(v == 0xDEADBEEFu,                    "peek32 nao leu a fronteira");

    printf("== can_sample: guardas do objecto ==\n");
    CHECK(movie_eos_can_sample(0) == 0,          "can_sample recusa obj=0");
    /* Estes dois estao marcados como commitados pelo mock (ver o comentario
     * la em cima): so a guarda de objecto os pode rejeitar. */
    CHECK(movie_eos_can_sample(0x4F000000u) == 0, "can_sample recusa obj no limite alto (commitado)");
    CHECK(movie_eos_can_sample(0x80000000u) == 0, "can_sample recusa obj fora da janela (commitado)");
    CHECK(movie_eos_can_sample(0x4EFFFFFFu) == 1, "can_sample aceita o ultimo obj valido");
    /* obj valido mas o span (0x780) sai da pagina commitada -> recusa. */
    CHECK(movie_eos_can_sample(PAGE - 0x100) == 0, "can_sample recusa span que sai do commit");
    /* obj valido com o span inteiro dentro do commit -> aceita. */
    CHECK(movie_eos_can_sample(0x100) == 1,      "can_sample aceita obj com span commitado");

    printf("== arm: proibido nesta task ==\n");
    /* Nada em movie_eos_arm.c pode mexer no g_movie_eos_ea na Task 1. */
    CHECK(g_movie_eos_ea == 0, "g_movie_eos_ea continua 0 (sem arm na Task 1)");

    munmap(buf, PAGE * 2);
    vm_base = NULL;

    if (g_fail) { printf("\nFAIL: %d assercao(oes)\n", g_fail); return 1; }
    printf("\nPASS: test_movie_eos_policy\n");
    return 0;
}
