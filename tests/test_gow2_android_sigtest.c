/* PS3_ANDROID_SIGTEST's routine on the Mac (the device run is the real acceptance): job A's
 * unmapped read and job B's read past EOF are recovered by the real spu_workload dispatch
 * and the clean job still runs; the routine returns 0 and prints "[SIGTEST] pass". */
#include "gow2_android_sigtest.h"
#include "spu_context.h"
#include "trace_link_stubs.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

unsigned char* vm_base = 0;
uint32_t ppu_vm_size = 0;
SPU_THREAD_LOCAL void (*g_spu_trampoline_fn)(spu_context*) = 0;

int main(void)
{
    char dir[] = "/tmp/g2sigXXXXXX";
    if (!mkdtemp(dir)) return 1;
    int rc = gow2_android_sigtest_run(dir);
    rmdir(dir);
    printf(rc == 0 ? "test_gow2_android_sigtest: PASS\n" : "test_gow2_android_sigtest: FAIL\n");
    return rc;
}
