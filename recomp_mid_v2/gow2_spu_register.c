#include <stdlib.h>
/* GoW2: register all four lifted SPU images with the workload dispatcher.
 *
 * Fingerprints are FNV-1a-64 of the extracted ELF (verified byte-identical to
 * the in-memory image at dispatch time). Entry LS addresses come from each
 * ELF's e_entry. spu1 is the intro MPEG decoder (dispatched during the SCE
 * logo movie); spu2/3 come up later in gameplay.
 */
#include <stdint.h>

typedef struct spu_context spu_context;
typedef void (*spu_lifted_entry_fn)(spu_context*);

extern void spu_workload_register(uint64_t fingerprint, spu_lifted_entry_fn fn,
                                  const char* name);

extern void spu0_spu_func_00003070(spu_context* ctx);   /* spu0 e_entry 0x3070 */
extern void spu1_spu_func_00003050(spu_context* ctx);   /* spu1 e_entry 0x3050 */
extern void spu2_spu_func_00004080(spu_context* ctx);   /* spu2 e_entry 0x4080 */
extern void spu3_spu_func_00004080(spu_context* ctx);   /* spu3 e_entry 0x4080 */
extern void spu0_spu_recomp_register(void);
extern void spu1_spu_recomp_register(void);
extern void spu2_spu_recomp_register(void);
extern void spu3_spu_recomp_register(void);

void gow2_register_spu_workloads(void)
{
    spu0_spu_recomp_register();
    spu1_spu_recomp_register();
    spu2_spu_recomp_register();
    spu3_spu_recomp_register();
    spu_workload_register(0xDE6DC3A5EA2BE487ull, spu0_spu_func_00003070, "gow2_spu0");
    /* spu1/2/3 lifted entries crash mid-run (LS/DMA paths incomplete) --
     * leave them UNregistered (dispatch MISS -> clean no-op) until the SPU
     * channel/DMA layer is solid. Registering a buggy entry regressed a
     * stable 40fps loop into a SIGSEGV. Toggle with PS3_SPU_ALL. */
    if (getenv("PS3_SPU_ALL") || getenv("PS3_SPU1"))
        spu_workload_register(0x2A5C4E67A14505B8ull, spu1_spu_func_00003050, "gow2_spu1");
    /* spu2/3 stay opt-in: their lifted entries may still fault mid-run. The
     * host is now protected by the SEH isolation in spu_workload.c (a job crash
     * kills only the job thread, not the process), so they can be registered
     * for bring-up without regressing the stable loop. Fine gates PS3_SPU2 /
     * PS3_SPU3 allow enabling one at a time; PS3_SPU_ALL enables both. NOT a
     * default -- promotion waits on a full no-kill boot validation. */
    if (getenv("PS3_SPU_ALL") || getenv("PS3_SPU2"))
        spu_workload_register(0xABCD0BA4D18DED49ull, spu2_spu_func_00004080, "gow2_spu2");
    if (getenv("PS3_SPU_ALL") || getenv("PS3_SPU3"))
        spu_workload_register(0xED6A0C318DEB46C6ull, spu3_spu_func_00004080, "gow2_spu3");
}

#if defined(__GNUC__)
__attribute__((constructor))
static void gow2_spu_autoregister(void) { gow2_register_spu_workloads(); }
#endif
