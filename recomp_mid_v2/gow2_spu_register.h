/* GoW2: which lifted SPU images the SPURS dispatcher gets, registered
 * explicitly by the boot host after it has its configuration (no static
 * constructor: spec 2026-09-24 iOS, resolution 1). */
#ifndef GOW2_SPU_REGISTER_H
#define GOW2_SPU_REGISTER_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct gow2_spu_config {
    unsigned char spu0, spu1, spu2, spu3, spu4, spu5, spu6;   /* 1 = register the workload image */
} gow2_spu_config;

/* The historical switches: spu0 on unless PS3_SPU0 starts with '0'; spu1..spu5
 * on when PS3_SPU<n> or PS3_SPU_ALL is PRESENT (any value); spu6 on unless
 * PS3_SPU6 is empty or starts with '0' (PS3_SPU_ALL forces it on). */
void gow2_spu_config_from_env(gow2_spu_config* cfg);

/* Registers the lifted functions of every image and the enabled workload
 * images. Call once, before the guest runs. NULL registers nothing. */
void gow2_register_spu_workloads(const gow2_spu_config* cfg);

#ifdef __cplusplus
}
#endif
#endif /* GOW2_SPU_REGISTER_H */
