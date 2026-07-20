/*
 * Amostrador portatil do objecto do movie player (Task 1 do plano
 * ../ps3recomp/docs/superpowers/plans/2026-07-20-macos-movie-eos-fsm.md).
 *
 * Equivalente POSIX da thread inline que o host de referencia do Windows
 * (ps3recomp/runtime/ppu/tests/boot_main.cpp) arranca no main(). NESTA TASK e
 * SO OBSERVACAO: nao arma o g_movie_eos_ea, nao escreve nada no guest.
 *
 * O arm do canal NATURAL depende de um produtor real de "done"
 * (movie_hle_overlay_done), que no POSIX ainda devolve 0 sempre -- armar sem
 * esse produtor seria forjar progresso do guest. Fica para a Task 3.
 */
#ifndef MOVIE_EOS_ARM_H
#define MOVIE_EOS_ARM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Arranca a thread de amostragem se PS3_TRACE_MOVIEOBJ estiver definido.
 * Sem essa variavel e um no-op total (nem thread se cria), por isso o baseline
 * fica byte a byte igual.
 *
 * Task 3 acrescenta PS3_MOVIE_EOS como segundo gate, quando existir de facto
 * o que armar.
 */
void movie_eos_sampler_start(void);

/*
 * Seam de teste: 1 se (obj_ea .. obj_ea+MOVIE_OBJ_SPAN) e' legivel segundo o
 * mapa de commits registado (ppu_guest_range_committed). Substitui o
 * VirtualQuery do host Windows, que nao tem equivalente POSIX barato.
 */
int movie_eos_can_sample(uint32_t obj_ea);

/*
 * Leitura big-endian de 32 bits do espaco do guest, com verificacao de commit
 * ANTES de tocar na memoria. Devolve 1 e preenche *out em caso de sucesso; 0 e
 * deixa *out intacto se o range nao estiver commitado (nesse caso NAO le).
 */
int movie_eos_peek32(uint32_t ea, uint32_t* out);

/* Leitura big-endian de 8 bits, mesmas regras do movie_eos_peek32. */
int movie_eos_peek8(uint32_t ea, uint8_t* out);

#ifdef __cplusplus
}
#endif

#endif /* MOVIE_EOS_ARM_H */
