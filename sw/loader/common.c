// Pieces every loader uses: CTR counter layout, tag compare, CMAC subkey.
#include <string.h>
#include "image.h"
#include "platform.h"

static const uint8_t nonce[8] = IMG_NONCE;

// nonce (8 B) || tile (u32 big-endian) || block number (u32 big-endian) = 0
void tile_counter(uint8_t ctr[16], uint32_t tile) {
    memcpy(ctr, nonce, 8);
    ctr[8] = tile >> 24; ctr[9] = tile >> 16; ctr[10] = tile >> 8; ctr[11] = tile;
    ctr[12] = ctr[13] = ctr[14] = ctr[15] = 0;
}

int tag_equal(const uint8_t *a, const uint8_t *b) {
    uint8_t d = 0;
    for (int i = 0; i < 16; i++) d |= a[i] ^ b[i];
    return d == 0;
}

// Doubling in GF(2^128), big-endian (RFC 4493).
void cmac_subkey(uint8_t k1[16], const uint8_t l[16]) {
    uint8_t carry = l[0] >> 7;
    for (int i = 0; i < 15; i++) k1[i] = (uint8_t)(l[i] << 1 | l[i + 1] >> 7);
    k1[15] = (uint8_t)(l[15] << 1) ^ (carry ? 0x87 : 0);
}
