# The model image as stored in "off-chip memory", the plain model (reference
# and no-protection baseline) and the test vectors. Paths come from the Makefile.
  .section .model_enc, "a"
  .balign 16
  .globl model_enc
model_enc:
  .incbin ENC_FILE

  .section .model_plain, "a"
  .balign 16
  .globl model_plain
model_plain:
  .incbin PLAIN_FILE

  .section .model_vec, "a"
  .balign 16
  .globl model_vec
model_vec:
  .incbin VEC_FILE
