/*
 * God of War II HD - macOS/arm64 boot host
 *
 * Phase F4 of ps3recomp/docs/MACOS_PORT_PLAN.md: the POSIX counterpart of the
 * Windows boot_v2_new.exe launcher. Brings up guest memory, loads the
 * decrypted EBOOT, registers the lifted function table and enters the guest.
 *
 * The plan's acceptance for this phase is deliberately modest: the native
 * arm64 binary should start and reach the same hang point the Windows build
 * reaches (the SPURS chain), rather than dying on a platform problem. Anything
 * further is SPURS work (F6), shared with Windows and not macOS-specific.
 *
 * Graphics backend is chosen with PS3_RSX_BACKEND (sdl | metal | vulkan),
 * mirroring the d3d12 selection on Windows. PS3_NO_RSX=1 skips the window
 * entirely, which is how the CPU/SPURS path is exercised headless.
 *
 * Build: ./build_macos.sh
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>

#include "ppu_recomp.h"

extern "C" {

/*
 * Guest address space. ppu_loader.cpp declares this and expects the host to
 * own it; vm_init() in vm.h fills it in.
 *
 * Note for anyone porting further: the guest's 4 GB window is mapped with
 * mmap(NULL, ...) and every guest address is an offset from vm_base, so macOS
 * reserving the low 4 GB as __PAGEZERO never comes into it. No -pagezero_size
 * link flag is needed.
 */
uint8_t* vm_base = nullptr;

/* g_trampoline_fn (the cross-fragment branch trampoline) is defined by
 * ppu_loader.cpp, which also drains it in its run loop. Do not define it here
 * as well -- the lifted chunks only declare it extern. */

uint32_t ppu_load_elf(const char* path);
void     ppu_recomp_register(void);
int      ppu_run(uint32_t entry_opd, uint32_t stack_top);
uint32_t ppu_function_count(void);

/* HLE registries. These have to be populated before ppu_resolve_imports runs,
 * otherwise the guest's PRX import stubs have nothing to bind to and the first
 * indirect call through one jumps into whatever the slot happened to hold. */
void     ppu_hle_init(void);
void     ppu_fs_register(void);
void     ppu_sysprx_register(void);
uint32_t ppu_resolve_imports(void);

int  rsx_null_backend_init(uint32_t w, uint32_t h, const char* title);
void rsx_null_backend_shutdown(void);
int  rsx_null_backend_pump_messages(void);

int  rsx_metal_backend_init(uint32_t w, uint32_t h, const char* title);
void rsx_metal_backend_shutdown(void);
int  rsx_metal_backend_pump_messages(void);

int  rsx_vulkan_backend_init(uint32_t w, uint32_t h, const char* title);
void rsx_vulkan_backend_shutdown(void);
int  rsx_vulkan_backend_pump_messages(void);

} /* extern "C" */

#include "vm.h"

namespace {

enum class Backend { None, Sdl, Metal, Vulkan };

Backend g_backend = Backend::None;

Backend pick_backend()
{
    if (getenv("PS3_NO_RSX")) {
        return Backend::None;
    }

    const char* want = getenv("PS3_RSX_BACKEND");
    if (!want || !*want) {
        want = "sdl";
    }
    if (strcmp(want, "metal")  == 0) return Backend::Metal;
    if (strcmp(want, "vulkan") == 0) return Backend::Vulkan;
    if (strcmp(want, "sdl")    == 0) return Backend::Sdl;

    fprintf(stderr, "[boot] unknown PS3_RSX_BACKEND '%s', falling back to sdl\n", want);
    return Backend::Sdl;
}

int backend_init(Backend b)
{
    switch (b) {
    case Backend::Sdl:    return rsx_null_backend_init(1280, 720, "God of War II HD (ps3recomp)");
    case Backend::Metal:  return rsx_metal_backend_init(1280, 720, "God of War II HD (ps3recomp)");
    case Backend::Vulkan: return rsx_vulkan_backend_init(1280, 720, "God of War II HD (ps3recomp)");
    case Backend::None:   return 0;
    }
    return -1;
}

void backend_shutdown(Backend b)
{
    switch (b) {
    case Backend::Sdl:    rsx_null_backend_shutdown();   break;
    case Backend::Metal:  rsx_metal_backend_shutdown();  break;
    case Backend::Vulkan: rsx_vulkan_backend_shutdown(); break;
    case Backend::None:   break;
    }
}

} /* namespace */

int main(int argc, char** argv)
{
    const char* elf_path = (argc > 1) ? argv[1] : "EBOOT.ELF";

    fprintf(stderr, "[boot] God of War II HD -- macOS/arm64 host\n");
    fprintf(stderr, "[boot] ELF: %s\n", elf_path);

    if (vm_init() != CELL_OK) {
        fprintf(stderr, "[boot] FATAL: vm_init failed\n");
        return 1;
    }
    fprintf(stderr, "[boot] guest memory mapped at host %p\n", (void*)vm_base);

    /*
     * Back the guest pages below main memory with zeros.
     *
     * A real PS3 leaves address 0 unmapped and traps on a null dereference,
     * and so does vm_init. The GoW2 CRT reads through a null pointer during
     * early init, which on this host is a SIGBUS that ends the process before
     * anything interesting happens. Mapping the low window as zeros makes that
     * read return 0 and lets the boot proceed to the real wall.
     *
     * This is a bring-up aid, not correct emulation: it hides null
     * dereferences instead of reporting them. Whether that CRT read is a
     * faithful reproduction of the guest or a lifting bug is still open.
     */
    if (vm_commit(0, VM_MAIN_MEM_BASE) == CELL_OK) {
        memset(vm_base, 0, VM_MAIN_MEM_BASE);
        fprintf(stderr, "[boot] zero page mapped for guest 0x0..0x%X (bring-up aid)\n",
                VM_MAIN_MEM_BASE);
    } else {
        fprintf(stderr, "[boot] WARNING: could not map the guest zero page; "
                        "a null dereference will fault\n");
    }

    ppu_recomp_register();
    fprintf(stderr, "[boot] registered %u lifted functions\n", ppu_function_count());

    ppu_hle_init();
    ppu_fs_register();
    ppu_sysprx_register();
    fprintf(stderr, "[boot] HLE, filesystem and sysprx registries populated\n");

    uint32_t entry = ppu_load_elf(elf_path);
    if (!entry) {
        fprintf(stderr, "[boot] FATAL: could not load %s\n", elf_path);
        vm_shutdown();
        return 1;
    }
    fprintf(stderr, "[boot] entry OPD 0x%08X\n", entry);

    /* Binds the guest's PRX import stubs to the registries above. Needs the
     * PT_PROC_PRX_PARAM address that ppu_load_elf captures, so it runs after
     * the load, not before. */
    uint32_t imports = ppu_resolve_imports();
    fprintf(stderr, "[boot] resolved %u PRX imports\n", imports);

    g_backend = pick_backend();
    if (backend_init(g_backend) != 0) {
        fprintf(stderr, "[boot] FATAL: RSX backend failed to initialise\n");
        vm_shutdown();
        return 1;
    }

    vm_stack_alloc sa;
    vm_stack_alloc_init(&sa);
    uint32_t stack_base = vm_stack_allocate(&sa, VM_PPU_STACK_SIZE);
    if (!stack_base) {
        fprintf(stderr, "[boot] FATAL: could not allocate guest stack\n");
        backend_shutdown(g_backend);
        vm_shutdown();
        return 1;
    }
    /* The PPU stack grows down, so the guest starts at the top of the region,
     * kept 16-byte aligned as the ABI requires. */
    uint32_t stack_top = (stack_base + VM_PPU_STACK_SIZE) & ~15u;
    fprintf(stderr, "[boot] guest stack 0x%08X..0x%08X\n", stack_base, stack_top);

    fprintf(stderr, "[boot] entering guest\n");
    fflush(stderr);

    int rc = ppu_run(entry, stack_top);

    fprintf(stderr, "[boot] guest returned rc=%d\n", rc);

    backend_shutdown(g_backend);
    vm_shutdown();
    return rc == 0 ? 0 : 1;
}
