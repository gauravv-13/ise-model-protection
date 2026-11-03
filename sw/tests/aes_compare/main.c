// AES-128 three ways on one CVA6 core: software (T-tables), Zkne instructions,
// and the OpenTitan AES accelerator on CVA6's bus (PLATFORM_CVA6 only; Spike
// runs the first two).
// 1. Check each against the FIPS-197 Appendix C.1 vector.
// 2. Count cycles and instructions for key setup and for buffers of each size.
// Output lines start with KAT / RESULT / BUF / ALL.
#include <stdint.h>
#include <string.h>
#include "aes.h"
#include "htif.h"

#ifndef MAX_BYTES
#define MAX_BYTES 65536
#endif
static const uint32_t sizes[] = { 16, 1024, MAX_BYTES };

static const uint8_t key[16] __attribute__((aligned(8))) = {
  0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f };
static const uint8_t pt[16] __attribute__((aligned(8))) = {
  0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff };
static const uint8_t ct[16] = {
  0x69,0xc4,0xe0,0xd8,0x6a,0x7b,0x04,0x30,0xd8,0xcd,0xb7,0x80,0x70,0xb4,0xc5,0x5a };

static uint8_t buf_in[MAX_BYTES] __attribute__((aligned(8)));
static uint8_t buf_sw[MAX_BYTES] __attribute__((aligned(8)));
static uint8_t buf_zk[MAX_BYTES] __attribute__((aligned(8), unused));
#ifdef PLATFORM_CVA6
static uint8_t buf_ot[MAX_BYTES] __attribute__((aligned(8), unused));
#endif

typedef void (*expand_fn)(aes128_key_t *, const uint8_t *);
typedef void (*buf_fn)(const aes128_key_t *, uint8_t *, const uint8_t *, uint32_t);

static inline uint64_t rd_cycle(void)   { uint64_t v; __asm__ volatile("csrr %0, mcycle"   : "=r"(v)); return v; }
static inline uint64_t rd_instret(void) { uint64_t v; __asm__ volatile("csrr %0, minstret" : "=r"(v)); return v; }

// ECB over a buffer: enough to measure raw block throughput.
static void sw_buf(const aes128_key_t *k, uint8_t *out, const uint8_t *in, uint32_t n) {
    for (uint32_t i = 0; i < n; i += 16) aes_sw_encrypt(k, out + i, in + i);
}
static void zkne_buf(const aes128_key_t *k, uint8_t *out, const uint8_t *in, uint32_t n) {
    for (uint32_t i = 0; i < n; i += 16) aes_zkne_encrypt(k, out + i, in + i);
}

static void result(const char *impl, const char *what, uint32_t bytes, uint64_t cyc, uint64_t ins) {
    print("RESULT "); print(impl); print(" "); print(what);
    print(" bytes="); print_dec(bytes);
    print(" cycles="); print_dec(cyc);
    print(" instret="); print_dec(ins); print("\n");
}

static int __attribute__((unused)) check_kat(const char *impl, expand_fn ex, buf_fn enc) {
    aes128_key_t k; uint8_t out[16] __attribute__((aligned(8)));
    ex(&k, key); enc(&k, out, pt, 16);
    int ok = memcmp(out, ct, 16) == 0;
    print("KAT "); print(impl); print(" ct="); print_hex(out, 16);
    print(ok ? " PASS\n" : " FAIL\n");
    return ok;
}

static void __attribute__((unused)) measure(const char *impl, expand_fn ex, buf_fn enc, uint8_t *out) {
    aes128_key_t k;
    uint64_t c, i;
    ex(&k, key);                                 // warm-up (caches, branch predictor)
    c = rd_cycle(); i = rd_instret();
    ex(&k, key);
    result(impl, "expand", 0, rd_cycle() - c, rd_instret() - i);
    for (unsigned s = 0; s < sizeof sizes / sizeof sizes[0]; s++) {
        enc(&k, out, buf_in, 16);                // warm-up
        c = rd_cycle(); i = rd_instret();
        enc(&k, out, buf_in, sizes[s]);
        result(impl, "encrypt", sizes[s], rd_cycle() - c, rd_instret() - i);
    }
}

#ifdef ONLY
// Power runs (make ONLY=sw|zkne|ot): just one method's key setup and largest
// buffer, so the switching activity of the whole run belongs to it.
#define STR2(x) #x
#define STR(x)  STR2(x)
int main(void) {
    aes128_key_t k;
    for (uint32_t i = 0; i < MAX_BYTES; i++) buf_in[i] = (uint8_t)(i * 7 + 3);
    if (__builtin_strcmp(STR(ONLY), "sw") == 0) {
        aes_sw_init(); aes_sw_expand(&k, key); sw_buf(&k, buf_sw, buf_in, MAX_BYTES);
    } else if (__builtin_strcmp(STR(ONLY), "zkne") == 0) {
        aes_zkne_expand(&k, key); zkne_buf(&k, buf_sw, buf_in, MAX_BYTES);
    }
#ifdef PLATFORM_CVA6
    else if (__builtin_strcmp(STR(ONLY), "ot") == 0) {
        aes_ot_expand(&k, key); aes_ot_encrypt_buf(&k, buf_sw, buf_in, MAX_BYTES);
    }
#endif
    print("ONLY " STR(ONLY) " done\n");
    return 0;
}
#else
int main(void) {
    int ok = 1;
    aes_sw_init();
    ok &= check_kat("sw", aes_sw_expand, sw_buf);
    ok &= check_kat("zkne", aes_zkne_expand, zkne_buf);
#ifdef PLATFORM_CVA6
    ok &= check_kat("ot", aes_ot_expand, aes_ot_encrypt_buf);
#endif

    for (uint32_t i = 0; i < MAX_BYTES; i++) buf_in[i] = (uint8_t)(i * 7 + 3);
    measure("sw", aes_sw_expand, sw_buf, buf_sw);
    measure("zkne", aes_zkne_expand, zkne_buf, buf_zk);

    // All must give the same ciphertext for the whole buffer.
    int same = memcmp(buf_sw, buf_zk, MAX_BYTES) == 0;
    print(same ? "BUF zkne PASS\n" : "BUF zkne FAIL\n");
    ok &= same;
#ifdef PLATFORM_CVA6
    measure("ot", aes_ot_expand, aes_ot_encrypt_buf, buf_ot);
    same = memcmp(buf_sw, buf_ot, MAX_BYTES) == 0;
    print(same ? "BUF ot PASS\n" : "BUF ot FAIL\n");
    ok &= same;
#endif

    print(ok ? "ALL PASS\n" : "SOME FAILED\n");
    return ok ? 0 : 1;
}
#endif

// The compiler may call these even at -O2; no C library here.
void *memcpy(void *d, const void *s, size_t n) {
    uint8_t *dp = d; const uint8_t *sp = s;
    while (n--) *dp++ = *sp++;
    return d;
}
int memcmp(const void *a, const void *b, size_t n) {
    const uint8_t *p = a, *q = b;
    for (; n; n--, p++, q++) if (*p != *q) return *p - *q;
    return 0;
}
