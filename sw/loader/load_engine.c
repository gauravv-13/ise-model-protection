// Option B: OpenTitan AES + DMA (hw/engine). The CPU only sets up the engine;
// the DMA moves the data. Two passes per tile, as one AES block serves both:
//   1. CBC with K2, output dropped   -> CMAC over header || C
//   2. CTR with K1, in place         -> plaintext
// Also the DMA copy used as "system DMA" by every method (COPY mode).
#include "image.h"
#include "platform.h"

#define AES_KEY_SHARE0(i)   (0x04 + 4 * (i))
#define AES_KEY_SHARE1(i)   (0x24 + 4 * (i))
#define AES_IV(i)           (0x44 + 4 * (i))
#define AES_DATA_IN(i)      (0x54 + 4 * (i))
#define AES_DATA_OUT(i)     (0x64 + 4 * (i))
#define AES_CTRL_SHADOWED   0x74
#define AES_STATUS          0x84
#define DMA_SRC             0x100
#define DMA_DST             0x104
#define DMA_LEN             0x108
#define DMA_CTRL            0x10c
#define DMA_STATUS          0x110

#define STATUS_IDLE         (1u << 0)
#define STATUS_OUTPUT_VALID (1u << 3)
#define STATUS_INPUT_READY  (1u << 4)
// CTRL: OPERATION=ENC, KEY_LEN=128, PRNG_RESEED_RATE=PER_64, automatic mode.
#define CTRL_BASE           ((1u << 0) | (1u << 8) | (1u << 13))
#define CTRL_ECB            (CTRL_BASE | (1u << 2))
#define CTRL_CBC            (CTRL_BASE | (1u << 3))
#define CTRL_CTR            (CTRL_BASE | (1u << 6))
#define DMA_START           1u
#define DMA_MODE_COPY       (0u << 1)
#define DMA_MODE_AES        (1u << 1)
#define DMA_MODE_SINK       (2u << 1)
#define DMA_DONE            (1u << 1)
#define DMA_ERROR           (1u << 2)

#define REG(base, off)  (*(volatile uint32_t *)((base) + (off)))
// CVA6 may merge two stores to the same address; a fence keeps them apart
// (the shadowed CTRL register needs two real writes).
#define fence() __asm__ volatile("fence" ::: "memory")

static uintptr_t eng = ENG_UNMASKED;              // engine used by eng_tile
static const uint8_t k1[16] __attribute__((aligned(8))) = IMG_K1;
static const uint8_t k2[16] __attribute__((aligned(8))) = IMG_K2;
static uint8_t subkey[16] __attribute__((aligned(8)));

static void wait_status(uint32_t bits) { while ((REG(eng, AES_STATUS) & bits) != bits) ; }

// Mode, key and IV for a new message. The key is given as two shares
// (share0 ^ share1); share1 = 0 here. All 8 words of both shares must be
// written, even for AES-128.
static void aes_setup(uint32_t ctrl, const uint8_t *key, const uint8_t *iv) {
    const uint32_t *kw = (const uint32_t *)key, *ivw = (const uint32_t *)iv;
    wait_status(STATUS_IDLE);
    REG(eng, AES_CTRL_SHADOWED) = ctrl; fence();
    REG(eng, AES_CTRL_SHADOWED) = ctrl; fence();
    for (int i = 0; i < 8; i++) {
        REG(eng, AES_KEY_SHARE0(i)) = i < 4 ? kw[i] : 0;
        REG(eng, AES_KEY_SHARE1(i)) = 0;
    }
    fence();
    wait_status(STATUS_IDLE);                    // a key write starts a PRNG reseed
    if (iv) for (int i = 0; i < 4; i++) REG(eng, AES_IV(i)) = ivw[i];
    fence();
    wait_status(STATUS_IDLE | STATUS_INPUT_READY);
}

// One block by hand: write DATA_IN, wait, read DATA_OUT.
static void aes_block(uint32_t out[4], const uint32_t in[4]) {
    for (int i = 0; i < 4; i++) REG(eng, AES_DATA_IN(i)) = in[i];
    wait_status(STATUS_OUTPUT_VALID);
    for (int i = 0; i < 4; i++) out[i] = REG(eng, AES_DATA_OUT(i));
}

// Start the DMA and wait until it is done. A real system would take an
// interrupt and do other work; the cycles spent here count as "waiting".
static uint64_t dma_run(uintptr_t base, uint32_t src, uint32_t dst, uint32_t len, uint32_t mode) {
    REG(base, DMA_SRC) = src;
    REG(base, DMA_DST) = dst;
    REG(base, DMA_LEN) = len;
    REG(base, DMA_CTRL) = mode | DMA_START;
    uint64_t t = rd_cycle();
    while (!(REG(base, DMA_STATUS) & DMA_DONE)) ;
    return rd_cycle() - t;
}

uint64_t dma_copy(void *dst, const void *src, uint32_t len) {
#ifdef PLATFORM_CVA6
    return dma_run(ENG_UNMASKED, (uint32_t)(uintptr_t)src, (uint32_t)(uintptr_t)dst, len, DMA_MODE_COPY);
#else   // Spike has no DMA: plain copy, nothing to wait for
    const uint64_t *s = src; uint64_t *d = dst;
    for (uint32_t i = 0; i < len / 8; i++) d[i] = s[i];
    return 0;
#endif
}

void eng_init(uintptr_t base) {
    uint32_t zero[4] = {0}, l[4];
    eng = base;
    aes_setup(CTRL_ECB, k2, 0);                  // CMAC subkey: K1 = dbl(AES_K2(0))
    aes_block(l, zero);
    cmac_subkey(subkey, (const uint8_t *)l);
}

int eng_tile(uint32_t tile, uint8_t *rec, uint32_t payload, uint64_t *wait) {
    static const uint8_t zero_iv[16] __attribute__((aligned(8)));
    uint8_t ctr[16] __attribute__((aligned(8)));
    uint32_t last[4], tag[4];
    const uint32_t *c_last = (const uint32_t *)(rec + payload), *sk = (const uint32_t *)subkey;
    uint32_t addr = (uint32_t)(uintptr_t)rec;

    // Pass 1: CMAC. The DMA feeds header || C without the last block; the CPU
    // adds the subkey to the last block and reads the tag.
    aes_setup(CTRL_CBC, k2, zero_iv);
    *wait += dma_run(eng, addr, 0, payload, DMA_MODE_SINK);
    for (int i = 0; i < 4; i++) last[i] = c_last[i] ^ sk[i];
    aes_block(tag, last);
    if (!tag_equal((const uint8_t *)tag, rec + 16 + payload)) return 0;

    // Pass 2: CTR decryption in place.
    tile_counter(ctr, tile);
    aes_setup(CTRL_CTR, k1, ctr);
    *wait += dma_run(eng, addr + 16, addr + 16, payload, DMA_MODE_AES);
    return !(REG(eng, DMA_STATUS) & DMA_ERROR);
}
