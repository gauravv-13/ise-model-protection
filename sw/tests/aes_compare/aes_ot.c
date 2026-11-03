// Driver for the OpenTitan AES block at 0x4000_0000 (CVA6 harness only).
// Follows the "Programmers Guide" in opentitan/hw/ip/aes/doc/_index.md:
// ECB, AES-128, automatic mode; the key is kept inside the block.
#include "aes.h"

#define AES_BASE            0x40000000UL
#define REG(off)            (*(volatile uint32_t *)(AES_BASE + (off)))
#define AES_KEY_SHARE0(i)   (0x04 + 4 * (i))
#define AES_KEY_SHARE1(i)   (0x24 + 4 * (i))
#define AES_DATA_IN(i)      (0x54 + 4 * (i))
#define AES_DATA_OUT(i)     (0x64 + 4 * (i))
#define AES_CTRL_SHADOWED   0x74
#define AES_STATUS          0x84

#define STATUS_IDLE         (1u << 0)
#define STATUS_OUTPUT_VALID (1u << 3)
#define STATUS_INPUT_READY  (1u << 4)

// CTRL: OPERATION=ENC (1), MODE=ECB (1 << 2), KEY_LEN=128 (1 << 8),
// PRNG_RESEED_RATE=PER_1 (1 << 12, the reset value), MANUAL_OPERATION=0.
#define CTRL_ENC_ECB_128    ((1u << 0) | (1u << 2) | (1u << 8) | (1u << 12))

// CVA6 may merge two stores to the same address; fence after each write that
// must arrive on its own (the shadowed CTRL register needs two real writes).
#define fence() __asm__ volatile("fence" ::: "memory")

static void wait_status(uint32_t bit) { while (!(REG(AES_STATUS) & bit)) ; }

// "Key setup" for the accelerator: configure and load the key. The key is
// given as two shares (share0 ^ share1); share1 = 0 here, which is fine for
// timing. All 8 words of both shares must be written, even for AES-128.
void aes_ot_expand(aes128_key_t *k, const uint8_t key[16]) {
    (void)k;                                     // the key stays in the block
    const uint32_t *kw = (const uint32_t *)key;  // key[] is 8-byte aligned
    wait_status(STATUS_IDLE);
    REG(AES_CTRL_SHADOWED) = CTRL_ENC_ECB_128; fence();
    REG(AES_CTRL_SHADOWED) = CTRL_ENC_ECB_128; fence();
    wait_status(STATUS_IDLE);
    for (int i = 0; i < 8; i++) {
        REG(AES_KEY_SHARE0(i)) = i < 4 ? kw[i] : 0;
        REG(AES_KEY_SHARE1(i)) = 0;
    }
    fence();
    wait_status(STATUS_IDLE);                    // key write starts a PRNG reseed
}

static inline void put_block(const uint32_t *in) {
    for (int i = 0; i < 4; i++) REG(AES_DATA_IN(i)) = in[i];
}

static inline void get_block(uint32_t *out) {
    for (int i = 0; i < 4; i++) out[i] = REG(AES_DATA_OUT(i));
}

// Encrypt n bytes (n a multiple of 16, buffers 8-byte aligned). While block i
// is being encrypted, block i+1 already waits in DATA_IN.
void aes_ot_encrypt_buf(const aes128_key_t *k, uint8_t *out, const uint8_t *in, uint32_t n) {
    (void)k;
    const uint32_t *src = (const uint32_t *)in;
    uint32_t *dst = (uint32_t *)out;
    uint32_t blocks = n / 16;
    if (blocks == 0) return;

    wait_status(STATUS_INPUT_READY);
    put_block(src);
    if (blocks > 1) {
        wait_status(STATUS_INPUT_READY);
        put_block(src + 4);
    }
    for (uint32_t i = 0; i < blocks; i++) {
        wait_status(STATUS_OUTPUT_VALID);
        get_block(dst + 4 * i);
        if (i + 2 < blocks) put_block(src + 4 * (i + 2));
    }
}
