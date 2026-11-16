# Minimal start-up: one hart, set the stack, clear .bss, call main, exit via HTIF.
  .section .text.init
  .globl _start
_start:
  csrr  t0, mhartid
1: bnez t0, 1b                 # only hart 0 runs
  la    sp, __stack_top
  la    t0, __bss_start
  la    t1, __bss_end
2: bgeu t0, t1, 3f
  sd    zero, 0(t0)
  addi  t0, t0, 8
  j     2b
3: call  main
  call  htif_exit              # a0 = main's return value
4: j     4b
