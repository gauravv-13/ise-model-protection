#pragma once
#include <stdint.h>
#include <stddef.h>

// AES-128 encryption, two implementations with the same interface.
// Round keys: 11 x 16 bytes = 22 x 64-bit words.
// in/out must be 8-byte aligned (word loads, as real code would do).
typedef struct { uint64_t rk[22]; } aes128_key_t;

void aes_sw_init(void);                     // builds the T-tables once
void aes_sw_expand(aes128_key_t *k, const uint8_t key[16]);
void aes_sw_encrypt(const aes128_key_t *k, uint8_t out[16], const uint8_t in[16]);

void aes_zkne_expand(aes128_key_t *k, const uint8_t key[16]);
void aes_zkne_encrypt(const aes128_key_t *k, uint8_t out[16], const uint8_t in[16]);

// OpenTitan AES accelerator (CVA6 test harness only, PLATFORM_CVA6).
// The key is loaded into the block; k is unused.
void aes_ot_expand(aes128_key_t *k, const uint8_t key[16]);
void aes_ot_encrypt_buf(const aes128_key_t *k, uint8_t *out, const uint8_t *in, uint32_t n);
