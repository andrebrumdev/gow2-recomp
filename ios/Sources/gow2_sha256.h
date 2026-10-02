/* gow2_sha256 -- portable SHA-256 (FIPS 180-4) for the host shells: the install manifest
 * check (iOS and Android) and the Android probe routines. No platform crypto library. */
#ifndef GOW2_SHA256_H
#define GOW2_SHA256_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct gow2_sha256_ctx {
    uint32_t h[8];
    uint64_t len;
    uint8_t  buf[64];
    size_t   used;
} gow2_sha256_ctx;

void gow2_sha256_init(gow2_sha256_ctx* c);
void gow2_sha256_update(gow2_sha256_ctx* c, const void* data, size_t n);
void gow2_sha256_final(gow2_sha256_ctx* c, uint8_t out[32]);
/* 64 lowercase hex digits + NUL into hex[65]. */
void gow2_sha256_hex(const uint8_t d[32], char hex[65]);
/* Hash a whole file with open(2)/read(2) (0 = ok, -1 = open/read error). */
int gow2_sha256_file(const char* path, char hex[65]);

#ifdef __cplusplus
}
#endif
#endif /* GOW2_SHA256_H */
