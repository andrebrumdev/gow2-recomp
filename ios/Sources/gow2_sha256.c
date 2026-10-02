/* gow2_sha256.c -- see gow2_sha256.h. */
#include "gow2_sha256.h"

#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static const uint32_t K[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

#define ROR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))

static void block(gow2_sha256_ctx* c, const uint8_t* p)
{
    uint32_t w[64], a, b, cc, d, e, f, g, h;
    for (int i = 0; i < 16; i++)
        w[i] = (uint32_t)p[4 * i] << 24 | (uint32_t)p[4 * i + 1] << 16 | (uint32_t)p[4 * i + 2] << 8 | p[4 * i + 3];
    for (int i = 16; i < 64; i++) {
        uint32_t s0 = ROR(w[i - 15], 7) ^ ROR(w[i - 15], 18) ^ (w[i - 15] >> 3);
        uint32_t s1 = ROR(w[i - 2], 17) ^ ROR(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    a = c->h[0]; b = c->h[1]; cc = c->h[2]; d = c->h[3]; e = c->h[4]; f = c->h[5]; g = c->h[6]; h = c->h[7];
    for (int i = 0; i < 64; i++) {
        uint32_t t1 = h + (ROR(e, 6) ^ ROR(e, 11) ^ ROR(e, 25)) + ((e & f) ^ (~e & g)) + K[i] + w[i];
        uint32_t t2 = (ROR(a, 2) ^ ROR(a, 13) ^ ROR(a, 22)) + ((a & b) ^ (a & cc) ^ (b & cc));
        h = g; g = f; f = e; e = d + t1; d = cc; cc = b; b = a; a = t1 + t2;
    }
    c->h[0] += a; c->h[1] += b; c->h[2] += cc; c->h[3] += d; c->h[4] += e; c->h[5] += f; c->h[6] += g; c->h[7] += h;
}

void gow2_sha256_init(gow2_sha256_ctx* c)
{
    static const uint32_t H0[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                                   0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
    memcpy(c->h, H0, sizeof H0);
    c->len = 0;
    c->used = 0;
}

void gow2_sha256_update(gow2_sha256_ctx* c, const void* data, size_t n)
{
    const uint8_t* p = (const uint8_t*)data;
    c->len += n;
    while (n > 0) {
        size_t k = 64 - c->used;
        if (k > n) k = n;
        memcpy(c->buf + c->used, p, k);
        c->used += k; p += k; n -= k;
        if (c->used == 64) { block(c, c->buf); c->used = 0; }
    }
}

void gow2_sha256_final(gow2_sha256_ctx* c, uint8_t out[32])
{
    const uint64_t bits = c->len * 8;
    const uint8_t pad = 0x80, zero = 0;
    gow2_sha256_update(c, &pad, 1);
    while (c->used != 56) gow2_sha256_update(c, &zero, 1);
    uint8_t L[8];
    for (int i = 0; i < 8; i++) L[i] = (uint8_t)(bits >> (56 - 8 * i));
    gow2_sha256_update(c, L, 8);
    for (int i = 0; i < 8; i++) {
        out[4 * i] = (uint8_t)(c->h[i] >> 24); out[4 * i + 1] = (uint8_t)(c->h[i] >> 16);
        out[4 * i + 2] = (uint8_t)(c->h[i] >> 8); out[4 * i + 3] = (uint8_t)c->h[i];
    }
}

void gow2_sha256_hex(const uint8_t d[32], char hex[65])
{
    static const char* x = "0123456789abcdef";
    for (int i = 0; i < 32; i++) { hex[2 * i] = x[d[i] >> 4]; hex[2 * i + 1] = x[d[i] & 15]; }
    hex[64] = 0;
}

int gow2_sha256_file(const char* path, char hex[65])
{
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -1;
    gow2_sha256_ctx c;
    gow2_sha256_init(&c);
    static __thread uint8_t buf[1 << 16];
    for (;;) {
        ssize_t n = read(fd, buf, sizeof buf);
        if (n < 0) { close(fd); return -1; }
        if (n == 0) break;
        gow2_sha256_update(&c, buf, (size_t)n);
    }
    close(fd);
    uint8_t d[32];
    gow2_sha256_final(&c, d);
    gow2_sha256_hex(d, hex);
    return 0;
}
