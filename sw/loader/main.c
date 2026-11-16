// Model load on one CVA6 core, one method per build (-DMETHOD=...):
//   M_NONE   no protection: plain model, copy only
//   M_SW     software AES (T-tables)                     baseline
//   M_ZKNE   Zkne AES instructions                       Option A
//   M_ENG_U  OpenTitan AES + DMA, unmasked               Option B
//   M_ENG_M  OpenTitan AES + DMA, masked (OpenTitan default)
//
// Per tile, the scheme of the proposal:
//   1. system DMA copies the record (header, C, tag) from off-chip memory to L2
//   2. CMAC check     3. AES-CTR decryption, in place in L2
//   4. cluster DMA moves the plaintext to L1 (a DMA copy stands in for it)
// Then: the plaintext in L1 must equal the original model, the model must give
// the expected outputs on test images, and a flipped bit must be rejected.
// Output lines start with RESULT / CHECK / ALL.
#include <stdint.h>
#include <string.h>
#include "image.h"
#include "platform.h"
#include "htif.h"

#define M_NONE  0
#define M_SW    1
#define M_ZKNE  2
#define M_ENG_U 3
#define M_ENG_M 4
#ifndef METHOD
#define METHOD M_ZKNE
#endif
#ifndef REPS
#define REPS 2          // loads of the whole model (first one has cold caches)
#endif
#ifndef NN_IMAGES
#define NN_IMAGES 2     // test images to run after loading
#endif
#define N_VEC 64        // images in the vector file (models/train.py)

#if METHOD == M_NONE
#define NAME "none"
static void method_init(void) {}
#define method_tile ((tile_fn)0)
#elif METHOD == M_SW
#define NAME "sw"
static void method_init(void) { sw_init(); }
#define method_tile sw_tile
#elif METHOD == M_ZKNE
#define NAME "zkne"
static void method_init(void) { zkne_init(); }
#define method_tile zkne_tile
#elif METHOD == M_ENG_U
#define NAME "eng_unmasked"
static void method_init(void) { eng_init(ENG_UNMASKED); }
#define method_tile eng_tile
#else
#define NAME "eng_masked"
static void method_init(void) { eng_init(ENG_MASKED); }
#define method_tile eng_tile
#endif

typedef struct { uint64_t copy_in, crypto, wait, copy_out, total, instret; } cost_t;

static void field(const char *name, uint64_t v) { print(" "); print(name); print("="); print_dec(v); }

// Load tiles [0, n_tiles). Returns 0 as soon as a tile fails its check.
static int load(uint32_t n_tiles, cost_t *c) {
    const uint8_t *src = METHOD == M_NONE ? model_plain : model_enc;
    uint8_t *l1 = L1_BASE;
    uint64_t t_start = rd_cycle(), i_start = rd_instret();
    memset(c, 0, sizeof *c);
    for (uint32_t t = 0; t < n_tiles; t++) {
        uint32_t payload = IMG_TILE_BYTES;
        if ((t + 1) * IMG_TILE_BYTES > IMG_PLAIN_BYTES) payload = IMG_PLAIN_BYTES - t * IMG_TILE_BYTES;
        uint64_t t0 = rd_cycle();
        uint8_t *plain = L2_BUF;
        if (METHOD == M_NONE) {
            dma_copy(L2_BUF, src, payload);                  // step 1
            src += payload;
            c->copy_in += rd_cycle() - t0;
            t0 = rd_cycle();
        } else {
            dma_copy(L2_BUF, src, payload + 32);             // step 1
            dcache_flush();                                  // the CPU reads what the DMA wrote
            src += payload + 32;
            uint64_t t1 = rd_cycle();
            int ok = method_tile(t, L2_BUF, payload, &c->wait);   // steps 2 and 3
            stores_done();
            c->copy_in += t1 - t0;
            t0 = rd_cycle();
            c->crypto += t0 - t1;
            if (!ok) return 0;
            plain = L2_BUF + 16;
        }
        dma_copy(l1, plain, payload);                        // step 4
        l1 += payload;
        c->copy_out += rd_cycle() - t0;
    }
    c->total   = rd_cycle() - t_start;
    c->instret = rd_instret() - i_start;
    return 1;
}

int main(void) {
    int ok = 1;
    cost_t c;

    uint64_t t0 = rd_cycle();
    print("RESULT method=" NAME " what=boot"); field("cycles", t0); print("\n");
    t0 = rd_cycle();
    method_init();
    t0 = rd_cycle() - t0;
    print("RESULT method=" NAME " what=init");
    field("cycles", t0); print("\n");

    for (int rep = 0; rep < REPS; rep++) {
        int loaded = load(IMG_N_TILES, &c);
        print("RESULT method=" NAME " what=load");
        field("rep", rep); field("bytes", IMG_PLAIN_BYTES); field("tile", IMG_TILE_BYTES);
        field("tiles", IMG_N_TILES); field("total", c.total); field("copy_in", c.copy_in);
        field("crypto", c.crypto); field("wait", c.wait); field("copy_out", c.copy_out);
        field("instret", c.instret); print("\n");
        dcache_flush();
        int same = loaded && memcmp(L1_BASE, model_plain, IMG_PLAIN_BYTES) == 0;
        print(same ? "CHECK plain PASS\n" : "CHECK plain FAIL\n");
        ok &= same;
    }

    // The loaded model must give the outputs the host computed for the plain model.
    const uint8_t *images = model_vec, *labels = model_vec + N_VEC * 784;
    const int32_t *expect = (const int32_t *)(model_vec + N_VEC * 785);
    int nn_ok = 1, correct = 0;
    t0 = rd_cycle();
    for (int i = 0; i < NN_IMAGES; i++) {
        int32_t logits[10];
        int pred = nn_infer(L1_BASE, images + 784 * i, logits);
        nn_ok &= memcmp(logits, expect + 10 * i, sizeof logits) == 0;
        correct += pred == labels[i];
    }
    if (NN_IMAGES > 0) {
        t0 = rd_cycle() - t0;
        print("CHECK nn"); field("images", NN_IMAGES); field("correct", correct); field("cycles", t0);
        print(nn_ok ? " outputs_match PASS\n" : " outputs_match FAIL\n");
        ok &= nn_ok;
    }

    // One flipped bit in the stored image: the tile must be rejected.
    if (METHOD != M_NONE) {
        uint8_t *stored = (uint8_t *)(uintptr_t)model_enc;
        stored[16 + 5] ^= 0x10;
        stores_done();
        int rejected = !load(1, &c);
        stored[16 + 5] ^= 0x10;
        print(rejected ? "CHECK tamper REJECTED PASS\n" : "CHECK tamper ACCEPTED FAIL\n");
        ok &= rejected;
    }

    print("RESULT method=" NAME " what=end"); field("cycles", rd_cycle()); print("\n");
    print(ok ? "ALL PASS\n" : "SOME FAILED\n");
    return ok ? 0 : 1;
}

// No C library here; the compiler may still call these.
void *memcpy(void *d, const void *s, size_t n) {
    uint8_t *dp = d; const uint8_t *sp = s;
    while (n--) *dp++ = *sp++;
    return d;
}
void *memset(void *d, int v, size_t n) {
    uint8_t *dp = d;
    while (n--) *dp++ = (uint8_t)v;
    return d;
}
int memcmp(const void *a, const void *b, size_t n) {
    const uint8_t *p = a, *q = b;
    if ((((uintptr_t)a | (uintptr_t)b | n) & 7) == 0) {      // word by word when aligned
        const uint64_t *pw = a, *qw = b;
        for (; n; n -= 8, pw++, qw++) if (*pw != *qw) return 1;
        return 0;
    }
    for (; n; n--, p++, q++) if (*p != *q) return *p - *q;
    return 0;
}
