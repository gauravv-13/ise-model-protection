// AES-128 with the RISC-V scalar crypto instructions (Zkne, RV64).
// Each aes64es/aes64esm does SubBytes+ShiftRows(+MixColumns) for half the state.
#include <string.h>
#include "aes.h"

#define KS1I(rs1, rnum) ({ uint64_t _r; __asm__("aes64ks1i %0, %1, %2" : "=r"(_r) : "r"(rs1), "i"(rnum)); _r; })
#define KS2(rs1, rs2)   ({ uint64_t _r; __asm__("aes64ks2 %0, %1, %2"  : "=r"(_r) : "r"(rs1), "r"(rs2)); _r; })
#define ESM(rs1, rs2)   ({ uint64_t _r; __asm__("aes64esm %0, %1, %2"  : "=r"(_r) : "r"(rs1), "r"(rs2)); _r; })
#define ES(rs1, rs2)    ({ uint64_t _r; __asm__("aes64es %0, %1, %2"   : "=r"(_r) : "r"(rs1), "r"(rs2)); _r; })

void aes_zkne_expand(aes128_key_t *k, const uint8_t key[16]) {
    uint64_t *rk = k->rk;
    memcpy(rk, key, 16);                        // little-endian: byte 0 is the low byte
    // rnum must be a constant, so the 10 rounds are written out.
#define ROUND(i) do { uint64_t t = KS1I(rk[2*(i)+1], i);  \
        rk[2*(i)+2] = KS2(t, rk[2*(i)]);                  \
        rk[2*(i)+3] = KS2(rk[2*(i)+2], rk[2*(i)+1]); } while (0)
    ROUND(0); ROUND(1); ROUND(2); ROUND(3); ROUND(4);
    ROUND(5); ROUND(6); ROUND(7); ROUND(8); ROUND(9);
#undef ROUND
}

void aes_zkne_encrypt(const aes128_key_t *k, uint8_t out[16], const uint8_t in[16]) {
    const uint64_t *rk = k->rk;
    const uint64_t *p = (const uint64_t *)in;   // buffers are 8-byte aligned
    uint64_t s0 = p[0] ^ rk[0], s1 = p[1] ^ rk[1], n0, n1;
    for (int r = 1; r < 10; r++) {
        n0 = ESM(s0, s1); n1 = ESM(s1, s0);     // low half, high half of the new state
        s0 = n0 ^ rk[2*r]; s1 = n1 ^ rk[2*r+1];
    }
    n0 = ES(s0, s1); n1 = ES(s1, s0);           // last round: no MixColumns
    s0 = n0 ^ rk[20]; s1 = n1 ^ rk[21];
    ((uint64_t *)out)[0] = s0; ((uint64_t *)out)[1] = s1;
}
