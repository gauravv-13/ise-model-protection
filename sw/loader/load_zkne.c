// Option A: AES instructions (Zkne) on CVA6. Key setup here; the per-tile
// work is the assembly routine in zkne_tile.S.
#include "aes.h"
#include "image.h"
#include "platform.h"

static aes128_key_t rk_ctr, rk_mac;
static uint8_t subkey[16] __attribute__((aligned(8)));

// CMAC(K2; header || C) -> tag, and CTR decryption of C in place.
void zkne_tile_asm(const uint64_t *rk_ctr, const uint64_t *rk_mac, uint8_t *rec, uint64_t payload,
                   const uint64_t *ctr, const uint64_t *subkey, uint64_t *tag);

void zkne_init(void) {
    static const uint8_t k1[16] __attribute__((aligned(8))) = IMG_K1;
    static const uint8_t k2[16] __attribute__((aligned(8))) = IMG_K2;
    uint8_t zero[16] __attribute__((aligned(8))) = {0}, l[16] __attribute__((aligned(8)));
    aes_zkne_expand(&rk_ctr, k1);
    aes_zkne_expand(&rk_mac, k2);
    aes_zkne_encrypt(&rk_mac, l, zero);
    cmac_subkey(subkey, l);
}

int zkne_tile(uint32_t tile, uint8_t *rec, uint32_t payload, uint64_t *wait) {
    uint64_t ctr[2], tag[2];
    (void)wait;
    tile_counter((uint8_t *)ctr, tile);
    zkne_tile_asm(rk_ctr.rk, rk_mac.rk, rec, payload, ctr, (const uint64_t *)subkey, tag);
    return tag_equal((uint8_t *)tag, rec + 16 + payload);
}
