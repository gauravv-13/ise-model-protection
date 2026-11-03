# Software AES vs Zkne AES, bare metal.
#   make                    build for Spike  -> build/spike/aes_compare.elf
#   make spike              run on Spike
#   make PLATFORM=cva6      build for the CVA6 test harness (UART output)
#   make PLATFORM=cva6 ONLY=zkne   one method only, for power runs
# Source env/setup.sh first.

RISCV_PREFIX ?= riscv-none-elf-
CC        := $(RISCV_PREFIX)gcc
OBJDUMP   := $(RISCV_PREFIX)objdump
PLATFORM  ?= spike
MAX_BYTES ?= 65536

CFLAGS  := -march=rv64gc_zkne -mabi=lp64d -mcmodel=medany -O2 -g \
           -ffreestanding -fno-builtin-printf -Wall -Wextra -DMAX_BYTES=$(MAX_BYTES) \
           $(if $(filter cva6,$(PLATFORM)),-DPLATFORM_CVA6) $(if $(ONLY),-DONLY=$(ONLY))
LDFLAGS := -nostdlib -nostartfiles -T link.ld -Wl,--no-warn-rwx-segments

SRCS := crt0.S htif.c aes_sw.c aes_zkne.c main.c $(if $(filter cva6,$(PLATFORM)),aes_ot.c)
BUILD := build/$(PLATFORM)$(if $(ONLY),_$(ONLY)_$(MAX_BYTES))

all: $(BUILD)/aes_compare.elf $(BUILD)/aes_compare.dump

$(BUILD)/aes_compare.elf: $(SRCS) aes.h htif.h link.ld Makefile | $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) $(SRCS) -lgcc -o $@

$(BUILD)/aes_compare.dump: $(BUILD)/aes_compare.elf
	$(OBJDUMP) -d $< > $@

$(BUILD):
	mkdir -p $@

spike: $(BUILD)/aes_compare.elf
	spike --isa=rv64gc_zkne $<

clean:
	rm -rf $(BUILD)

.PHONY: all spike clean
