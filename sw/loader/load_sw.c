// Baseline: software AES (T-tables, no AES instructions). One pass per tile:
// CMAC over header || C and CTR decryption of C, block by block.
#include <string.h>
#include "aes.h"
#include "image.h"
#include "platform.h"

static aes128_key_t rk_ctr, rk_mac;
static uint8_t subkey[16] __attribute__((aligned(8)));

void sw_init(void) {
    static const uint8_t k1[16] __attribute__((aligned(8))) = IMG_K1;
    static const uint8_t k2[16] __attribute__((aligned(8))) = IMG_K2;
    uint8_t zero[16] __attribute__((aligned(8))) = {0}, l[16] __attribute__((aligned(8)));
    aes_sw_init();
    aes_sw_expand(&rk_ctr, k1);
    aes_sw_expand(&rk_mac, k2);
    aes_sw_encrypt(&rk_mac, l, zero);
    cmac_subkey(subkey, l);
}

int sw_tile(uint32_t tile, uint8_t *rec, uint32_t payload, uint64_t *wait) {
    uint64_t x[2], ks[2], ctr[2];
    uint64_t *p = (uint64_t *)rec, *end = p + 2 + payload / 8;
    const uint64_t *sk = (const uint64_t *)subkey;
    (void)wait;
    tile_counter((uint8_t *)ctr, tile);
    aes_sw_encrypt(&rk_mac, (uint8_t *)x, rec);              // header block
    for (p += 2; p < end; p += 2) {
        x[0] ^= p[0]; x[1] ^= p[1];
        if (p + 2 == end) { x[0] ^= sk[0]; x[1] ^= sk[1]; }  // last block of the message
        aes_sw_encrypt(&rk_mac, (uint8_t *)x, (uint8_t *)x);
        aes_sw_encrypt(&rk_ctr, (uint8_t *)ks, (uint8_t *)ctr);
        p[0] ^= ks[0]; p[1] ^= ks[1];
        for (int i = 15; i >= 12 && ++((uint8_t *)ctr)[i] == 0; i--) ;   // big-endian +1
    }
    return tag_equal((uint8_t *)x, (uint8_t *)end);
}
