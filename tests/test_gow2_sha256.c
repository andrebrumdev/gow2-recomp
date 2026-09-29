/* gow2_sha256 against the FIPS 180-4 vectors and shasum-computed files. */
#include "gow2_sha256.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_fail;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); g_fail++; } } while (0)
static void hs(const void* d, size_t n, char hex[65])
{
    gow2_sha256_ctx c; uint8_t out[32];
    gow2_sha256_init(&c); gow2_sha256_update(&c, d, n); gow2_sha256_final(&c, out); gow2_sha256_hex(out, hex);
}
int main(void)
{
    char h[65];
    hs("", 0, h); CHECK(strcmp(h, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == 0);
    hs("abc", 3, h); CHECK(strcmp(h, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") == 0);
    const char* two = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    hs(two, strlen(two), h); CHECK(strcmp(h, "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1") == 0);
    char* a = malloc(1000000); memset(a, 'a', 1000000);
    gow2_sha256_ctx c; uint8_t out[32]; gow2_sha256_init(&c);
    for (int i = 0; i < 1000000; i += 999) gow2_sha256_update(&c, a + i, (1000000 - i) < 999 ? (size_t)(1000000 - i) : 999);
    gow2_sha256_final(&c, out); gow2_sha256_hex(out, h);
    CHECK(strcmp(h, "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0") == 0);
    char path[] = "/tmp/gow2shaXXXXXX"; int fd = mkstemp(path); FILE* f = fdopen(fd, "wb");
    fwrite(a, 1, 1000000, f); fclose(f); free(a);
    CHECK(gow2_sha256_file(path, h) == 0 && strcmp(h, "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0") == 0);
    remove(path);
    CHECK(gow2_sha256_file("/nonexistent/x", h) == -1);
    printf(g_fail ? "test_gow2_sha256: FAIL\n" : "test_gow2_sha256: PASS\n");
    return g_fail ? 1 : 0;
}
