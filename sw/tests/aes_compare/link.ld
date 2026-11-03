/* Bare-metal layout for Spike and the CVA6 test harness: RAM at 0x80000000. */
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
}
