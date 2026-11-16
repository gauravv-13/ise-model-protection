# Option A tile routine: AES-128 CMAC + CTR with the Zkne instructions (RV64).
#
#   void zkne_tile_asm(const uint64_t *rk_ctr,   a0  11 round keys of K1
#                      const uint64_t *rk_mac,   a1  11 round keys of K2
#                      uint8_t *rec,             a2  header (16 B) then payload
#                      uint64_t payload,         a3  bytes, multiple of 16, >= 16
#                      const uint64_t *ctr,      a4  first counter block
#                      const uint64_t *subkey,   a5  CMAC subkey K1
#                      uint64_t *tag);           a6  out: CMAC over header || payload
#
# The payload is decrypted in place. Per block, the two AES computations
# (counter block under K1, MAC state under K2) run interleaved: each round is
# 4 round-key loads, 4 aes64esm and 4 xor. Only Zkne is used (no Zbb/Zbkb).
#
#   s0,s1 MAC state   s2,s3 counter block   s4,s5 key stream   s6,s7 data block

  .text
  .option arch, +zkne

  # One AES round of the MAC state only (header block).
  .macro MAC_ROUND r, op
  ld    t2, 16*\r(a1)
  ld    t3, 16*\r+8(a1)
  \op   t6, s0, s1
  \op   a7, s1, s0
  xor   s0, t6, t2
  xor   s1, a7, t3
  .endm

  # One AES round of both the key stream (s4,s5) and the MAC state (s0,s1).
  .macro BOTH_ROUND r, op
  ld    t0, 16*\r(a0)
  ld    t1, 16*\r+8(a0)
  ld    t2, 16*\r(a1)
  ld    t3, 16*\r+8(a1)
  \op   t4, s4, s5
  \op   t5, s5, s4
  \op   t6, s0, s1
  \op   a7, s1, s0
  xor   s4, t4, t0
  xor   s5, t5, t1
  xor   s0, t6, t2
  xor   s1, a7, t3
  .endm

  # Key stream block from the counter (s2,s3) and next MAC state, 10 rounds.
  .macro BOTH_AES
  ld    t0, 0(a0)
  ld    t1, 8(a0)
  ld    t2, 0(a1)
  ld    t3, 8(a1)
  xor   s4, s2, t0
  xor   s5, s3, t1
  xor   s0, s0, t2
  xor   s1, s1, t3
  BOTH_ROUND 1, aes64esm
  BOTH_ROUND 2, aes64esm
  BOTH_ROUND 3, aes64esm
  BOTH_ROUND 4, aes64esm
  BOTH_ROUND 5, aes64esm
  BOTH_ROUND 6, aes64esm
  BOTH_ROUND 7, aes64esm
  BOTH_ROUND 8, aes64esm
  BOTH_ROUND 9, aes64esm
  BOTH_ROUND 10, aes64es
  .endm

  .globl zkne_tile_asm
  .type  zkne_tile_asm, @function
zkne_tile_asm:
  addi  sp, sp, -64
  sd    s0, 0(sp)
  sd    s1, 8(sp)
  sd    s2, 16(sp)
  sd    s3, 24(sp)
  sd    s4, 32(sp)
  sd    s5, 40(sp)
  sd    s6, 48(sp)
  sd    s7, 56(sp)

  ld    s2, 0(a4)               # counter block: nonce | tile | block number
  ld    s3, 8(a4)
  li    a4, 1
  slli  a4, a4, 56              # +1 on the last counter byte (big-endian)
  add   a3, a2, a3              # address of the last payload block

  # Header block: MAC state = AES_K2(header).
  ld    s0, 0(a2)
  ld    s1, 8(a2)
  ld    t2, 0(a1)
  ld    t3, 8(a1)
  xor   s0, s0, t2
  xor   s1, s1, t3
  MAC_ROUND 1, aes64esm
  MAC_ROUND 2, aes64esm
  MAC_ROUND 3, aes64esm
  MAC_ROUND 4, aes64esm
  MAC_ROUND 5, aes64esm
  MAC_ROUND 6, aes64esm
  MAC_ROUND 7, aes64esm
  MAC_ROUND 8, aes64esm
  MAC_ROUND 9, aes64esm
  MAC_ROUND 10, aes64es
  addi  a2, a2, 16
  beq   a2, a3, .Llast

.Lblock:                        # all payload blocks but the last
  ld    s6, 0(a2)
  ld    s7, 8(a2)
  xor   s0, s0, s6              # MAC over the ciphertext
  xor   s1, s1, s7
  BOTH_AES
  xor   s6, s6, s4              # plaintext = ciphertext ^ key stream
  xor   s7, s7, s5
  sd    s6, 0(a2)
  sd    s7, 8(a2)
  add   t0, s3, a4              # counter + 1
  bltu  t0, s3, .Lcarry         # last byte wrapped: carry into the next bytes
  mv    s3, t0
.Lnext:
  addi  a2, a2, 16
  bne   a2, a3, .Lblock

.Llast:                         # last block: MAC input also gets the subkey
  ld    s6, 0(a2)
  ld    s7, 8(a2)
  ld    t0, 0(a5)
  ld    t1, 8(a5)
  xor   s0, s0, s6
  xor   s1, s1, s7
  xor   s0, s0, t0
  xor   s1, s1, t1
  BOTH_AES
  xor   s6, s6, s4
  xor   s7, s7, s5
  sd    s6, 0(a2)
  sd    s7, 8(a2)
  sd    s0, 0(a6)               # tag
  sd    s1, 8(a6)

  ld    s0, 0(sp)
  ld    s1, 8(sp)
  ld    s2, 16(sp)
  ld    s3, 24(sp)
  ld    s4, 32(sp)
  ld    s5, 40(sp)
  ld    s6, 48(sp)
  ld    s7, 56(sp)
  addi  sp, sp, 64
  ret

.Lcarry:                        # once per 256 blocks: big-endian +1 over bytes 15..12
  li    t1, 56                  # bit position of the byte being incremented
1:
  srl   t2, s3, t1
  andi  t2, t2, 0xff
  li    t3, 0xff
  bne   t2, t3, 2f
  sll   t2, t3, t1              # byte is 0xff: becomes 0, carry on
  not   t2, t2
  and   s3, s3, t2
  addi  t1, t1, -8
  li    t2, 32
  bgeu  t1, t2, 1b
  j     .Lnext
2:
  li    t2, 1
  sll   t2, t2, t1
  add   s3, s3, t2
  j     .Lnext
  .size zkne_tile_asm, .-zkne_tile_asm
