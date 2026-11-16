// Memory map and small helpers shared by the loaders.
#pragma once
#include <stdint.h>

// "Off-chip memory" (HyperRAM stand-in): the image as stored, see link.ld.
extern const uint8_t model_enc[], model_plain[], model_vec[];
// On-chip L2 scratchpad: one tile record at a time.
#define L2_BUF   ((uint8_t *)0x80600000UL)
// L1 (cluster TCDM) stand-in: where the cluster DMA puts verified plaintext.
#define L1_BASE  ((uint8_t *)0x80800000UL)

// AES engines (CVA6 harness): OpenTitan AES registers at +0x000, DMA at +0x100.
#define ENG_UNMASKED 0x40000000UL
#define ENG_MASKED   0x40000800UL

static inline uint64_t rd_cycle(void)   { uint64_t v; __asm__ volatile("csrr %0, mcycle"   : "=r"(v)); return v; }
static inline uint64_t rd_instret(void) { uint64_t v; __asm__ volatile("csrr %0, minstret" : "=r"(v)); return v; }

// After a DMA has written memory the CPU will read: drop CVA6's cached copies.
// CVA6 clears its data cache when the cache is switched off and on again
// (CSR 0x7c1); a plain fence does not flush it in this configuration.
static inline void dcache_flush(void) {
#ifdef PLATFORM_CVA6
    __asm__ volatile("csrw 0x7c1, zero\n li t0, 1\n csrw 0x7c1, t0" ::: "t0", "memory");
#endif
}
// Before a DMA reads memory the CPU has written: let pending stores reach it.
static inline void stores_done(void) { __asm__ volatile("fence" ::: "memory"); }

// One tile through one method. rec: the tile record in L2 (header, payload,
// tag). Checks the tag and decrypts the payload in place. Returns 1 if the
// tag matches. *wait gets the cycles the CPU only waited for the engine.
typedef int (*tile_fn)(uint32_t tile, uint8_t *rec, uint32_t payload, uint64_t *wait);

void sw_init(void);
int  sw_tile(uint32_t tile, uint8_t *rec, uint32_t payload, uint64_t *wait);
void zkne_init(void);
int  zkne_tile(uint32_t tile, uint8_t *rec, uint32_t payload, uint64_t *wait);
void eng_init(uintptr_t base);
int  eng_tile(uint32_t tile, uint8_t *rec, uint32_t payload, uint64_t *wait);

// DMA copy (8-byte aligned, length a multiple of 8). Returns the cycles waited.
uint64_t dma_copy(void *dst, const void *src, uint32_t len);

// Shared by the loaders.
void tile_counter(uint8_t ctr[16], uint32_t tile);       // first CTR block of a tile
int  tag_equal(const uint8_t *a, const uint8_t *b);       // constant time
void cmac_subkey(uint8_t k1[16], const uint8_t l[16]);    // K1 = dbl(AES_K(0))

// int8 inference on a plain model blob (nn.c). Returns the predicted class.
int nn_infer(const uint8_t *blob, const uint8_t *image, int32_t logits[10]);
