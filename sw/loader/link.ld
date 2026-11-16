/* Bare-metal layout for Spike and the CVA6 test harness: 16 MB RAM at 0x80000000.
   0x8000_0000  program, data, stack
   0x8010_0000  encrypted model image   } "off-chip memory" (HyperRAM stand-in)
   0x8030_0000  plain model, test vectors }
   0x8060_0000  L2 scratchpad buffer (platform.h)
   0x8080_0000  L1 stand-in (platform.h) */
OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;
  .text.init : { *(.text.init) }
  .text      : { *(.text*) }
  . = ALIGN(64);
  .tohost    : { *(.tohost) }          /* HTIF mailbox, watched by Spike/harness */
  .rodata    : { *(.rodata*) }
  .data      : { *(.data*) *(.sdata*) }
  .bss       : { __bss_start = .; *(.bss*) *(.sbss*) *(COMMON); __bss_end = .; }
  . = ALIGN(16);
  . += 0x4000;                          /* 16 KiB stack */
  __stack_top = .;
  ASSERT(. < 0x80100000, "program too large")

  . = 0x80100000;
  .model_enc   : { *(.model_enc) }
  ASSERT(. < 0x80300000, "image too large")
  . = 0x80300000;
  .model_plain : { *(.model_plain) }
  . = ALIGN(16);
  .model_vec   : { *(.model_vec) }
  ASSERT(. < 0x80600000, "model too large")
}
